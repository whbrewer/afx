#!/usr/bin/env bats
# Tests for afx_scp/afx_rsync against stubbed `ssh`/`scp`/`rsync` (tests/
# fixtures/ssh-stub, xfer-stub) instead of a real second machine. The
# "remote machine" is simulated as a second, separately sandboxed $HOME
# ($AFX_TEST_REMOTE_HOME, see ssh-stub) on the same filesystem -- real
# directory copies and real jq-backed bookkeeping happen against it, just
# never over an actual network/sshd.
#
# As in commands.bats: CLAUDE_CODE_SESSION_ID is unset in setup() so these
# tests aren't accidentally exercising the "inside a session" path by
# virtue of this suite itself running inside one.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.afx" "$HOME/bin"
  export AFX_SESSIONS="$HOME/.afx/sessions.jsonl"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AFX_CONFIG_DIRS AFX_CODEX_HOMES CODEX_HOME AFX_PALETTE AFX_HASH_COLOR
  export NO_COLOR=1

  export AFX_TEST_SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
  export AFX_TEST_XFER_LOG="$BATS_TEST_TMPDIR/xfer.log"
  : > "$AFX_TEST_SSH_LOG"
  : > "$AFX_TEST_XFER_LOG"
  cp "$BATS_TEST_DIRNAME/fixtures/ssh-stub" "$HOME/bin/ssh"
  cp "$BATS_TEST_DIRNAME/fixtures/xfer-stub" "$HOME/bin/scp"
  cp "$BATS_TEST_DIRNAME/fixtures/xfer-stub" "$HOME/bin/rsync"
  chmod +x "$HOME/bin/ssh" "$HOME/bin/scp" "$HOME/bin/rsync"
  # The repo dir itself (containing the real, 9-line `afx` binary) goes on
  # PATH too: ssh-stub's simulated remote side runs `afx _register-remote`
  # for real, same as a genuine destination machine with afx installed
  # would -- it's the actual afx_register_remote code under test, not a
  # mock of it.
  export PATH="$HOME/bin:$BATS_TEST_DIRNAME/..:$PATH"

  export REMOTE_HOME="$BATS_TEST_TMPDIR/remote_home"
  mkdir -p "$REMOTE_HOME/.afx"
  export AFX_TEST_REMOTE_HOME="$REMOTE_HOME"

  source "$BATS_TEST_DIRNAME/../afx.sh"
}

# $1 sid, $2 dir, $3 home, $4 tool, $5 starred, $6 note, $7 summary
_write_row() {
  jq -nc --arg date "2024-01-01 10:00" --arg sid "$1" --arg dir "$2" --arg home "$3" \
    --arg tool "$4" --argjson starred "$5" --arg note "$6" --arg summary "$7" \
    '{date:$date, session_id:$sid, dir:$dir, home:$home, tool:$tool, reason:null,
      summary:(if $summary=="" then null else $summary end), detail:null,
      starred:$starred, note:(if $note=="" then null else $note end)}' >> "$AFX_SESSIONS"
}

# $1 sid, $2 dir, $3 home -- writes a minimal transcript plus a memory/ file
# alongside it, so tests can confirm both travel across in the raw directory
# copy (no separate memory-sync step needed here, unlike push/pull's API-based one).
_write_transcript() {
  local sid="$1" dir="$2" home="$3"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir/memory"
  printf '%s\n' '{"type":"user","isSidechain":false,"cwd":"'"$dir"'","message":{"content":"hi"}}' \
    > "$projdir/$sid.jsonl"
  printf 'some project notes\n' > "$projdir/memory/notes.md"
}

# ==================== usage / pre-transfer errors (both commands) ====================

@test "afx_scp: usage error with fewer than 2 arguments" {
  run afx_scp somehash
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: afx scp"* ]]
  [ ! -s "$AFX_TEST_SSH_LOG" ]
}

@test "afx_rsync: usage error with fewer than 2 arguments" {
  run afx_rsync somehash
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: afx rsync"* ]]
  [ ! -s "$AFX_TEST_SSH_LOG" ]
}

@test "afx_scp: no such session for an unknown hash" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_scp zzzzzz testhost
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such session: zzzzzz"* ]]
}

@test "afx_scp: refuses a non-claude (codex) session" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.codex" codex false "" "did stuff"
  run afx_scp abc123 testhost
  [ "$status" -eq 1 ]
  [[ "$output" == *"only Claude Code sessions are supported"* ]]
}

@test "afx_scp: no project directory found locally" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_scp abc123 testhost
  [ "$status" -eq 1 ]
  [[ "$output" == *"no project directory found"* ]]
}

@test "afx_scp: reports a dead/unreachable SSH target before touching any files" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  export AFX_TEST_SSH_UNREACHABLE_HOST="deadhost"

  run afx_scp abc123 "deadhost:$REMOTE_HOME/.claude"
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't confirm afx is installed"* ]]
  [ ! -s "$AFX_TEST_XFER_LOG" ]
}

@test "afx_scp: reports afx missing on \$PATH on an otherwise-reachable remote" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  export AFX_TEST_SSH_NO_REMOTE_AFX=1

  run afx_scp abc123 "somehost:$REMOTE_HOME/.claude"
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't confirm afx is installed"* ]]
  [ ! -s "$AFX_TEST_XFER_LOG" ]
}

@test "afx_scp: with no :<dest-home>, the destination home defaults to the source's" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"

  run afx_scp abc123 somehost
  [[ "$output" == *"-> somehost:$HOME/.claude/projects/"* ]]
}

# ==================== afx_scp / afx_rsync: full transfer + remote registration ====================

@test "afx_scp: copies the project to the remote home and registers it there, leaving the source untouched" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  local dest_home="$REMOTE_HOME/.claude"

  run afx_scp abc123 "testhost:$dest_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done. resume on testhost with:"* ]]
  [[ "$output" == *"source left untouched at"* ]]

  local src_proj_dir; src_proj_dir="$(_afx_proj_dir "$home" "$dir")"
  local dest_proj_dir; dest_proj_dir="$(_afx_proj_dir "$dest_home" "$dir")"

  # the transcript and the memory file both traveled in the raw directory copy
  [ -f "$dest_proj_dir/$sid.jsonl" ]
  [ -f "$dest_proj_dir/memory/notes.md" ]
  # the source is completely untouched
  [ -f "$src_proj_dir/$sid.jsonl" ]

  # registered on the "remote" side: a .claude.json project entry...
  run jq -r --arg d "$dir" '.projects[$d] // empty' "$dest_home/.claude.json"
  [ -n "$output" ]

  # ...and an afx-go-able sessions.jsonl row, scoped to the remote's own bookkeeping
  run jq -r --arg s "$sid" 'select(.session_id==$s) | .home' "$REMOTE_HOME/.afx/sessions.jsonl"
  [ "$output" = "$dest_home" ]
  run jq -r --arg s "$sid" 'select(.session_id==$s) | .reason' "$REMOTE_HOME/.afx/sessions.jsonl"
  [[ "$output" == scp_from_* ]]

  # the LOCAL sessions.jsonl row is never repointed -- unlike afx_cp/afx_mv,
  # this machine still owns the only resumable copy of $sid until the user
  # deletes it themselves
  run jq -r --arg s "$sid" 'select(.session_id==$s) | .home' "$AFX_SESSIONS"
  [ "$output" = "$home" ]
}

@test "afx_rsync: same, over the rsync path" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  local dest_home="$REMOTE_HOME/.claude"

  run afx_rsync abc123 "testhost:$dest_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done. resume on testhost with:"* ]]

  local dest_proj_dir; dest_proj_dir="$(_afx_proj_dir "$dest_home" "$dir")"
  [ -f "$dest_proj_dir/$sid.jsonl" ]

  run jq -r --arg s "$sid" 'select(.session_id==$s) | .reason' "$REMOTE_HOME/.afx/sessions.jsonl"
  [[ "$output" == rsync_from_* ]]
}
