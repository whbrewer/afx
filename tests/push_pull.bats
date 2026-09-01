#!/usr/bin/env bats
# Tests for afx_push/afx_pull against a stubbed `curl` (tests/fixtures/curl-stub)
# instead of the real artifax.dev -- everything else (secret scan, path
# aliasing, gzip/sha256, sessions.jsonl bookkeeping, session/dir project
# maps) is the real code running against a real sandboxed $HOME.
#
# As in commands.bats: CLAUDE_CODE_SESSION_ID is unset in setup() so
# afx_push's "inside a session" branch isn't accidentally exercised by
# virtue of this suite itself running inside a Claude Code session.
#
# afx_pull tests always pass --into "$HOME/..." explicitly: omitting it
# defaults into_dir to $PWD, which during a real test run is somewhere in
# this actual repo checkout -- never leave that to the default here.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.afx" "$HOME/bin"
  export AFX_SESSIONS="$HOME/.afx/sessions.jsonl"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AFX_CONFIG_DIRS AFX_CODEX_HOMES CODEX_HOME AFX_PALETTE AFX_HASH_COLOR ARTIFAX_PROJECT_ID
  export NO_COLOR=1
  export ARTIFAX_API_TOKEN=test-token
  export AFX_TEST_CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  : > "$AFX_TEST_CURL_LOG"
  cp "$BATS_TEST_DIRNAME/fixtures/curl-stub" "$HOME/bin/curl"
  chmod +x "$HOME/bin/curl"
  export PATH="$HOME/bin:$PATH"
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

# $1 sid, $2 dir, $3 home, $4 message content
_write_transcript() {
  local sid="$1" dir="$2" home="$3" content="$4"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"
  printf '%s\n' '{"type":"user","isSidechain":false,"cwd":"'"$dir"'","message":{"content":"'"$content"'"}}' \
    > "$projdir/$sid.jsonl"
}

# ==================== afx_push: pre-network errors ====================

@test "afx_push: refuses without \$ARTIFAX_API_TOKEN" {
  unset ARTIFAX_API_TOKEN
  run afx_push somehash
  [ "$status" -eq 1 ]
  [[ "$output" == *'$ARTIFAX_API_TOKEN not set'* ]]
  [ ! -s "$AFX_TEST_CURL_LOG" ]
}

@test "afx_push: no session matching an unknown hash" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_push zzzzzz
  [ "$status" -eq 1 ]
  [[ "$output" == *"no session matching hash zzzzzz"* ]]
}

@test "afx_push: refuses a non-claude (codex) session" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.codex" codex false "" "did stuff"
  run afx_push abc123
  [[ "$output" == *"only Claude Code sessions are supported"* ]]
}

@test "afx_push: fails clearly when the transcript file is missing" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_push abc123
  [[ "$output" == *"transcript file not found"* ]]
}

@test "afx_push: the secret-scan gate refuses a high-confidence finding before any network call" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home" 'my key is AKIAIOSFODNN7EXAMPLE'
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  run afx_push abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused: high-confidence secret findings"* ]]
  [[ "$output" == *"aws_access_key_id#1"* ]]
  [ ! -s "$AFX_TEST_CURL_LOG" ]
}

# ==================== afx_push: mocked network ====================

@test "afx_push: --allow-secret bypasses a specific finding and the push proceeds" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home" 'my key is AKIAIOSFODNN7EXAMPLE'
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  run afx_push abc123 --allow-secret aws_access_key_id#1
  [ "$status" -eq 0 ]
  [[ "$output" == *"pushed: sess_1"* ]]
}

@test "afx_push: full happy path -- creates a project, uploads, and pushes session metadata" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home" 'hello world, please help'
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"

  run afx_push abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"created project proj_1"* ]]
  [[ "$output" == *"pushed: sess_1 revision 1 (1 messages, 1 events)"* ]]

  run jq -r --arg s "$sid" '.[$s]' "$HOME/.afx/session-projects.json"
  [ "$output" = "proj_1" ]

  grep -q "/api/v1/uploads" "$AFX_TEST_CURL_LOG"
  grep -q "http://fake/put" "$AFX_TEST_CURL_LOG"
}

@test "afx_push: skips the PUT upload when the server already has this content (dedup)" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home" 'hello world, please help'
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  export AFX_TEST_UPLOADS_BODY='{"status":"complete"}'

  run afx_push abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"server already has this content (dedup): skipping upload"* ]]
  ! grep -q "http://fake/put" "$AFX_TEST_CURL_LOG"
}

@test "afx_push: a 409 response is reported as a diverged push and fails" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home" 'hello world, please help'
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  export AFX_TEST_PUSH_STATUS=409
  export AFX_TEST_PUSH_BODY='{"error":{"message":"server has more messages than you do"}}'

  run afx_push abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"diverged"* ]]
  [[ "$output" == *"server has more messages than you do"* ]]
}

@test "afx_push: reuses a previously recorded project instead of auto-creating a new one" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  _write_transcript "$sid" "$dir" "$home" 'hello world, please help'
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"
  jq -n --arg s "$sid" '{($s): "proj_existing"}' > "$HOME/.afx/session-projects.json"

  run afx_push abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"reusing project proj_existing from a previous push of this session"* ]]
  [[ "$output" != *"creating a project of one"* ]]
}

# ==================== afx_pull: pre-network errors ====================

@test "afx_pull: refuses without \$ARTIFAX_API_TOKEN" {
  unset ARTIFAX_API_TOKEN
  run afx_pull 01ARZ3NDEKTSV4RRFFQ69G5FAV
  [ "$status" -eq 1 ]
  [[ "$output" == *'$ARTIFAX_API_TOKEN not set'* ]]
}

@test "afx_pull: usage error with no arguments" {
  run afx_pull
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: afx pull"* ]]
}

# ==================== afx_pull: mocked network ====================

@test "afx_pull: resolves a non-ULID argument as a session hash via the lookup endpoint" {
  export AFX_TEST_LOOKUP_BODY='{"items":[{"project_id":"proj_from_hash"}]}'
  export AFX_TEST_BUNDLE_BODY='{"sessions":[],"memory":[]}'
  run afx_pull abc123 --into "$HOME/pulled"
  [ "$status" -eq 1 ]
  [[ "$output" == *"resolved abc123 -> project proj_from_hash"* ]]
  [[ "$output" == *"no sessions in project proj_from_hash"* ]]
}

@test "afx_pull: refuses when a hash matches sessions in more than one project" {
  export AFX_TEST_LOOKUP_BODY='{"items":[{"project_id":"proj_a"},{"project_id":"proj_b"}]}'
  run afx_pull abc123 --into "$HOME/pulled"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matches sessions in more than one project"* ]]
}

@test "afx_pull: pulls a session by project id, writing the transcript and a sessions.jsonl row" {
  local into="$HOME/pulled"
  local fixture_dir="$BATS_TEST_TMPDIR/fixture"; mkdir -p "$fixture_dir"
  printf '%s\n' '{"type":"user","cwd":"<project>","message":{"content":"hi"}}' > "$fixture_dir/transcript.jsonl"
  gzip -c "$fixture_dir/transcript.jsonl" > "$fixture_dir/transcript.jsonl.gz"
  export AFX_TEST_DOWNLOAD_SRC="$fixture_dir/transcript.jsonl.gz"
  export AFX_TEST_BUNDLE_BODY='{"sessions":[{"id":"artsess_abcdefghijklmnop","external_id":"extsid123456","source":"claude_code","summary":"a pulled session","download_url":"http://fake/download"}],"memory":[]}'

  run afx_pull 01ARZ3NDEKTSV4RRFFQ69G5FAV --into "$into"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulled."* ]]

  local proj_dir; proj_dir="$(_afx_proj_dir "$HOME/.claude" "$into")"
  [ -f "$proj_dir/extsid123456.jsonl" ]
  grep -q "\"cwd\":\"$into\"" "$proj_dir/extsid123456.jsonl"  # <project> placeholder rewritten to the real dir

  run jq -r --arg s extsid123456 'select(.session_id==$s) | .dir' "$AFX_SESSIONS"
  [ "$output" = "$into" ]
}

@test "afx_pull: also writes any memory entries the bundle carries" {
  local into="$HOME/pulled"
  local fixture_dir="$BATS_TEST_TMPDIR/fixture"; mkdir -p "$fixture_dir"
  printf '%s\n' '{"type":"user","cwd":"<project>","message":{"content":"hi"}}' > "$fixture_dir/transcript.jsonl"
  gzip -c "$fixture_dir/transcript.jsonl" > "$fixture_dir/transcript.jsonl.gz"
  export AFX_TEST_DOWNLOAD_SRC="$fixture_dir/transcript.jsonl.gz"
  export AFX_TEST_BUNDLE_BODY='{"sessions":[{"id":"artsess_abcdefghijklmnop","external_id":"extsid123456","source":"claude_code","summary":"a pulled session","download_url":"http://fake/download"}],"memory":[{"name":"proj-notes","kind":"project","description":"some notes about the project","body":"the project uses bats for tests","updated_at":"2024-01-01T00:00:00Z"}]}'

  run afx_pull 01ARZ3NDEKTSV4RRFFQ69G5FAV --into "$into"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulled 1 memory entries"* ]]

  local mem_dir; mem_dir="$(_afx_proj_dir "$HOME/.claude" "$into")/memory"
  [ -f "$mem_dir/proj-notes.md" ]
  grep -q "the project uses bats for tests" "$mem_dir/proj-notes.md"
  grep -q "proj-notes.md" "$mem_dir/MEMORY.md"
}
