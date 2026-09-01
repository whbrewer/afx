#!/usr/bin/env bats
# Tests for the state-mutating local commands (afx_star, afx_go, afx_list,
# afx_find, afx_rm, afx_cp, afx_mv) against a fully sandboxed $HOME --
# real filesystem operations, but never the user's actual ~/.afx or
# ~/.claude*, and never the network (push/pull aren't covered here).
#
# Every test unsets CLAUDE_CODE_SESSION_ID first: this suite itself runs
# inside a Claude Code session, which sets that variable in the real
# environment, and afx_star/afx_go/afx_status all branch on whether it's
# set -- left alone, tests would silently exercise the "inside a session"
# path instead of the "outside one" path they're meant to test.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.afx"
  export AFX_SESSIONS="$HOME/.afx/sessions.jsonl"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AFX_CONFIG_DIRS AFX_CODEX_HOMES CODEX_HOME AFX_PALETTE AFX_HASH_COLOR
  export NO_COLOR=1
  source "$BATS_TEST_DIRNAME/../afx.sh"
}

# $1 sid, $2 dir, $3 home, $4 tool, $5 starred (true/false), $6 note, $7 summary
_write_row() {
  jq -nc --arg date "2024-01-01 10:00" --arg sid "$1" --arg dir "$2" --arg home "$3" \
    --arg tool "$4" --argjson starred "$5" --arg note "$6" --arg summary "$7" \
    '{date:$date, session_id:$sid, dir:$dir, home:$home, tool:$tool, reason:null,
      summary:(if $summary=="" then null else $summary end), detail:null,
      starred:$starred, note:(if $note=="" then null else $note end)}' >> "$AFX_SESSIONS"
}

# ==================== afx_star ====================

@test "afx_star: starring an existing unstarred session by hash toggles it on" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_star abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"starred abc123 "* ]]
  run jq -r 'select(.session_id=="abc123def456") | .starred' "$AFX_SESSIONS"
  [ "$output" = "true" ]
}

@test "afx_star: starring an already-starred session toggles it off and clears the note" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude true "old note" "did stuff"
  run afx_star abc123
  [[ "$output" == *"unstarred abc123"* ]]
  run jq -r 'select(.session_id=="abc123def456") | .starred' "$AFX_SESSIONS"
  [ "$output" = "false" ]
  run jq -r 'select(.session_id=="abc123def456") | .note' "$AFX_SESSIONS"
  [ "$output" = "null" ]
}

@test "afx_star: trailing words become the note when (re-)starring" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_star abc123 my new note
  run jq -r 'select(.session_id=="abc123def456") | .note' "$AFX_SESSIONS"
  [ "$output" = "my new note" ]
}

@test "afx_star: (re-)starring with no note text keeps whatever note the row already had" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "carried note" "did stuff"
  run afx_star abc123
  run jq -r 'select(.session_id=="abc123def456") | .note' "$AFX_SESSIONS"
  [ "$output" = "carried note" ]
}

# ==================== afx_status ====================

@test "afx_status: reports starred sessions for \$PWD" {
  _write_row "abc123def456" "$PWD" "$HOME/.claude" claude true "" "did stuff"
  run afx_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"starred sessions for $PWD"* ]]
}

@test "afx_status: reports no starred sessions for \$PWD" {
  run afx_status
  [ "$status" -eq 1 ]
  [[ "$output" == *"no starred sessions for $PWD"* ]]
}

@test "afx_status: inside a session, checks that exact session id instead of \$PWD" {
  export CLAUDE_CODE_SESSION_ID="abc123def456"
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude true "" "did stuff"
  run afx_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"this session is starred"* ]]
}

# ==================== afx_list ====================

@test "afx_list: errors when there are no sessions yet" {
  run afx_list
  [ "$status" -eq 1 ]
  [[ "$output" == *"no sessions yet"* ]]
}

@test "afx_list: -s shows only starred sessions" {
  _write_row "aaa111" "$HOME/p1" "$HOME/.claude" claude false "" "unstarred one"
  _write_row "bbb222" "$HOME/p2" "$HOME/.claude" claude true "" "starred one"
  run afx_list -s
  [[ "$output" == *"starred one"* ]]
  [[ "$output" != *"unstarred one"* ]]
}

@test "afx_list: -d limits to sessions run from \$PWD" {
  _write_row "aaa111" "$PWD" "$HOME/.claude" claude false "" "here"
  _write_row "bbb222" "$HOME/elsewhere" "$HOME/.claude" claude false "" "there"
  run afx_list -d
  [[ "$output" == *"here"* ]]
  [[ "$output" != *"there"* ]]
}

@test "afx_list: a pattern filters rows by their summary text" {
  _write_row "aaa111" "$HOME/p1" "$HOME/.claude" claude false "" "fix the parser bug"
  _write_row "bbb222" "$HOME/p2" "$HOME/.claude" claude false "" "add new feature"
  run afx_list parser
  [[ "$output" == *"fix the parser bug"* ]]
  [[ "$output" != *"add new feature"* ]]
}

# ==================== afx_rm ====================

@test "afx_rm: aborts without deleting when not confirmed" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run bash -c "source '$BATS_TEST_DIRNAME/../afx.sh'; printf 'n\n' | afx_rm abc123"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborted"* ]]
  run jq -r 'select(.session_id=="abc123def456") | .session_id' "$AFX_SESSIONS"
  [ "$output" = "abc123def456" ]
}

@test "afx_rm: deletes the row on y confirmation, leaves the transcript alone by default" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"; : > "$projdir/$sid.jsonl"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  run bash -c "source '$BATS_TEST_DIRNAME/../afx.sh'; printf 'y\n' | afx_rm abc123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted abc123"* ]]
  [ ! -s "$AFX_SESSIONS" ]
  [ -f "$projdir/$sid.jsonl" ]
}

@test "afx_rm -D: deletes the row AND the transcript file on confirmation" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"; : > "$projdir/$sid.jsonl"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  run bash -c "source '$BATS_TEST_DIRNAME/../afx.sh'; printf 'y\n' | afx_rm -D abc123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"and its transcript file"* ]]
  [ ! -f "$projdir/$sid.jsonl" ]
}

# ==================== afx_go ====================

@test "afx_go: no sessions yet" {
  run afx_go abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"no sessions yet"* ]]
}

@test "afx_go: no such session for an unknown hash" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_go zzzzzz
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such session: zzzzzz"* ]]
}

@test "afx_go: fails clearly when the session's directory no longer exists" {
  _write_row "abc123def456" "$HOME/gone" "$HOME/.claude" claude false "" "did stuff"
  run afx_go abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"directory gone: $HOME/gone"* ]]
}

@test "afx_go: fails clearly when the transcript itself is missing" {
  local dir="$HOME/proj"; mkdir -p "$dir"
  _write_row "abc123def456" "$dir" "$HOME/.claude" claude false "" "did stuff"
  run afx_go abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"session abc123def456 no longer exists in"* ]]
}

@test "afx_go: cd's to the session's dir and resumes it via claude --resume" {
  local dir="$HOME/proj"; mkdir -p "$dir"
  local home="$HOME/.claude" sid="abc123def456"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"; : > "$projdir/$sid.jsonl"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"

  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "STUB claude $*"
echo "CONFIG_DIR=$CLAUDE_CONFIG_DIR"
echo "PWD=$PWD"
STUB
  chmod +x "$HOME/bin/claude"
  export PATH="$HOME/bin:$PATH"

  run afx_go abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB claude --resume $sid"* ]]
  [[ "$output" == *"CONFIG_DIR=$home"* ]]
  [[ "$output" == *"PWD=$dir"* ]]
}

# ==================== afx_find ====================

@test "afx_find: errors when no transcripts exist at all" {
  run afx_find anything
  [ "$status" -eq 1 ]
  [[ "$output" == *"no session transcripts found"* ]]
}

@test "afx_find: finds a real user prompt matching the pattern" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"
  printf '%s\n' '{"type":"user","isSidechain":false,"timestamp":"2024-01-01T10:00:00.000Z","sessionId":"'"$sid"'","cwd":"'"$dir"'","message":{"content":"please fix the parser bug"}}' \
    > "$projdir/$sid.jsonl"
  run afx_find parser
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix the parser bug"* ]]
}

@test "afx_find: reports no match for an unmatched pattern" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"
  printf '%s\n' '{"type":"user","isSidechain":false,"timestamp":"2024-01-01T10:00:00.000Z","sessionId":"'"$sid"'","cwd":"'"$dir"'","message":{"content":"hello world"}}' \
    > "$projdir/$sid.jsonl"
  run afx_find zzzznotfound
  [ "$status" -eq 1 ]
  [[ "$output" == *"no match for 'zzzznotfound'"* ]]
}

# ==================== afx_cp ====================

@test "afx_cp: usage error with fewer than 2 arguments" {
  run afx_cp abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: afx cp"* ]]
}

@test "afx_cp: no such session for an unknown hash" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_cp zzzzzz "$HOME/.claude-work"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such session: zzzzzz"* ]]
}

@test "afx_cp: refuses a non-claude (codex) session" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.codex" codex false "" "did stuff"
  run afx_cp abc123 "$HOME/.claude-work"
  [[ "$output" == *"only Claude Code sessions are supported"* ]]
}

@test "afx_cp: refuses when the destination account doesn't exist" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_cp abc123 "$HOME/.claude-doesnotexist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"doesn't exist"* ]]
}

@test "afx_cp: refuses copying an account to itself" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  mkdir -p "$(_afx_proj_dir "$home" "$dir")"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  run afx_cp abc123 "$home"
  [[ "$output" == *"same account"* ]]
}

@test "afx_cp: copies the project, leaves the source untouched, repoints sessions.jsonl" {
  local dir="$HOME/proj" src_home="$HOME/.claude" dest_home="$HOME/.claude-work" sid="abc123def456"
  local src_proj; src_proj="$(_afx_proj_dir "$src_home" "$dir")"
  mkdir -p "$src_proj" "$dest_home"
  printf 'transcript-content' > "$src_proj/$sid.jsonl"
  _write_row "$sid" "$dir" "$src_home" claude false "" "did stuff"

  run afx_cp abc123 "$dest_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"copying 1 session(s) for $dir"* ]]

  local dest_proj; dest_proj="$(_afx_proj_dir "$dest_home" "$dir")"
  [ -f "$dest_proj/$sid.jsonl" ]
  [ "$(cat "$dest_proj/$sid.jsonl")" = "transcript-content" ]
  [ -f "$src_proj/$sid.jsonl" ]  # source left in place

  run jq -r 'select(.session_id=="'"$sid"'") | .home' "$AFX_SESSIONS"
  [ "$output" = "$dest_home" ]

  run jq -e --arg d "$dir" '.projects[$d]' "$dest_home/.claude.json"
  [ "$status" -eq 0 ]
}

# ==================== afx_mv ====================

@test "afx_mv: aborts without touching anything when not confirmed" {
  local dir="$HOME/proj" src_home="$HOME/.claude" dest_home="$HOME/.claude-work" sid="abc123def456"
  local src_proj; src_proj="$(_afx_proj_dir "$src_home" "$dir")"
  mkdir -p "$src_proj" "$dest_home"
  printf 'transcript-content' > "$src_proj/$sid.jsonl"
  _write_row "$sid" "$dir" "$src_home" claude false "" "did stuff"

  run bash -c "source '$BATS_TEST_DIRNAME/../afx.sh'; printf 'n\n' | afx_mv abc123 '$dest_home'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborted"* ]]
  [ -f "$src_proj/$sid.jsonl" ]
  local dest_proj; dest_proj="$(_afx_proj_dir "$dest_home" "$dir")"
  [ ! -e "$dest_proj" ]
}

@test "afx_mv: moves the project on y confirmation, removing the verified source" {
  local dir="$HOME/proj" src_home="$HOME/.claude" dest_home="$HOME/.claude-work" sid="abc123def456"
  local src_proj; src_proj="$(_afx_proj_dir "$src_home" "$dir")"
  mkdir -p "$src_proj" "$dest_home"
  printf 'transcript-content' > "$src_proj/$sid.jsonl"
  _write_row "$sid" "$dir" "$src_home" claude false "" "did stuff"

  run bash -c "source '$BATS_TEST_DIRNAME/../afx.sh'; printf 'y\n' | afx_mv abc123 '$dest_home'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done. 1 session(s) moved"* ]]

  local dest_proj; dest_proj="$(_afx_proj_dir "$dest_home" "$dir")"
  [ -f "$dest_proj/$sid.jsonl" ]
  [ "$(cat "$dest_proj/$sid.jsonl")" = "transcript-content" ]
  [ ! -d "$src_proj" ]  # source removed after verification

  run jq -r 'select(.session_id=="'"$sid"'") | .home' "$AFX_SESSIONS"
  [ "$output" = "$dest_home" ]
}
