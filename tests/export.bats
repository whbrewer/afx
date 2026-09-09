#!/usr/bin/env bats
# Tests for afx_export -- writing a session out as an Open Knowledge Format
# (OKF v0.2, https://github.com/GoogleCloudPlatform/open-knowledge-format)
# bundle. Reuses the same transcript fixtures/shape as port.bats since both
# commands share _afx_locate_transcript/_afx_port_render.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.afx"
  export AFX_SESSIONS="$HOME/.afx/sessions.jsonl"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AFX_CONFIG_DIRS AFX_CODEX_HOMES CODEX_HOME AFX_PALETTE AFX_HASH_COLOR
  export NO_COLOR=1
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

_write_claude_transcript() {
  local sid="$1" dir="$2" home="$3"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"
  {
    jq -nc '{type:"user", isSidechain:false, version:"2.1.265", timestamp:"2026-01-01T10:00:00Z", message:{role:"user", content:"help me write a script"}}'
    jq -nc '{type:"assistant", isSidechain:false, timestamp:"2026-01-01T10:00:05Z", message:{role:"assistant", content:[
      {type:"text", text:"Sure, on it."}
    ]}}'
    jq -nc '{type:"assistant", isSidechain:false, timestamp:"2026-01-01T10:00:10Z", message:{role:"assistant", content:[
      {type:"text", text:"Done, created file1.txt"}
    ]}}'
  } > "$projdir/$sid.jsonl"
}

_write_codex_transcript() {
  local sid="$1" home="$2" dir="$3"
  local sessdir="$home/sessions/2024/01/01"
  mkdir -p "$sessdir"
  {
    jq -nc --arg cwd "$dir" '{type:"session_meta", timestamp:"2026-01-01T10:00:00Z", payload:{id:"'"$sid"'", cwd:$cwd, cli_version:"0.151.0"}}'
    jq -nc '{type:"response_item", timestamp:"2026-01-01T10:00:01Z", payload:{type:"message", role:"user", content:[
      {type:"input_text", text:"run the tests"}
    ]}}'
    jq -nc '{type:"response_item", timestamp:"2026-01-01T10:00:05Z", payload:{type:"message", role:"assistant", content:[
      {type:"output_text", text:"All 5 tests passed."}
    ]}}'
  } > "$sessdir/$sid.jsonl"
}

# ==================== usage / guard-rail errors ====================

@test "afx_export: usage error without --format" {
  run afx_export abc123 --out "$BATS_TEST_TMPDIR/bundle"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: afx export"* ]]
}

@test "afx_export: usage error without --out" {
  run afx_export abc123 --format okf
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: afx export"* ]]
}

@test "afx_export: rejects a format other than okf" {
  run afx_export abc123 --format json --out "$BATS_TEST_TMPDIR/bundle"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--format must be okf"* ]]
}

@test "afx_export: no session matching an unknown hash" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_export zzzzzz --format okf --out "$BATS_TEST_TMPDIR/bundle"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such session: zzzzzz"* ]]
}

@test "afx_export: fails clearly when the transcript file is missing" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_export abc123 --format okf --out "$BATS_TEST_TMPDIR/bundle"
  [ "$status" -eq 1 ]
  [[ "$output" == *"transcript file not found"* ]]
}

# ==================== claude source ====================

@test "afx_export: writes a spec-shaped OKF concept doc for a Claude session" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456" out="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$dir"
  _write_claude_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "my note" "a short summary"

  run afx_export abc123 --format okf --out "$out"
  [ "$status" -eq 0 ]
  [ -f "$out/sessions/$sid.md" ]

  local doc="$out/sessions/$sid.md"
  # frontmatter delimiters and required/recommended keys (SPEC.md section 4.1)
  [ "$(sed -n '1p' "$doc")" = "---" ]
  grep -q '^type: Coding Agent Session$' "$doc"
  grep -q '^title: "my note"$' "$doc"
  grep -q '^tags: \[session, claude\]$' "$doc"
  grep -q '^generated: { by: "claude-code/2.1.265", at: "2026-01-01T10:00:10Z" }$' "$doc"
  grep -q '^resource: "file://' "$doc"
  grep -q '^sources:$' "$doc"
  grep -q '^afx_session_id: "abc123def456"$' "$doc"
  grep -q '^afx_tool: "claude"$' "$doc"
  grep -q '^# Transcript$' "$doc"
  grep -q "help me write a script" "$doc"
  grep -q "Done, created file1.txt" "$doc"
}

@test "afx_export: writes a bundle-root index.md with okf_version frontmatter" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456" out="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$dir"
  _write_claude_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "my note" "a short summary"

  run afx_export abc123 --format okf --out "$out"
  [ "$status" -eq 0 ]
  [ -f "$out/index.md" ]
  [ "$(sed -n '1p' "$out/index.md")" = "---" ]
  grep -q '^okf_version: "0.2"$' "$out/index.md"
  grep -q "sessions/$sid.md" "$out/index.md"
  grep -q "my note" "$out/index.md"
}

@test "afx_export: falls back to the first user message when no note/summary exists" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456" out="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$dir"
  _write_claude_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" ""

  run afx_export abc123 --format okf --out "$out"
  [ "$status" -eq 0 ]
  grep -q '^title: "help me write a script"$' "$out/sessions/$sid.md"
}

@test "afx_export: re-exporting the same session upserts in place, not a duplicate" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456" out="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$dir"
  _write_claude_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "my note" "a short summary"

  run afx_export abc123 --format okf --out "$out"
  [ "$status" -eq 0 ]
  run afx_export abc123 --format okf --out "$out"
  [ "$status" -eq 0 ]

  [ "$(find "$out/sessions" -name '*.md' | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(grep -c "sessions/$sid.md" "$out/index.md")" -eq 1 ]
}

# ==================== codex source ====================

@test "afx_export: writes a spec-shaped OKF concept doc for a Codex session" {
  local dir="$HOME/proj" home="$HOME/.codex" sid="019dda9d1cba78b2940f8f8df1878975" out="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$dir"
  _write_codex_transcript "$sid" "$home" "$dir"
  _write_row "$sid" "$dir" "$home" codex false "" "ran the test suite"

  run afx_export "${sid:0:6}" --format okf --out "$out"
  [ "$status" -eq 0 ]
  local doc="$out/sessions/$sid.md"
  [ -f "$doc" ]
  grep -q '^tags: \[session, codex\]$' "$doc"
  grep -q '^generated: { by: "codex/0.151.0", at: "2026-01-01T10:00:05Z" }$' "$doc"
  grep -q "run the tests" "$doc"
  grep -q "All 5 tests passed." "$doc"
}

@test "afx_export: multiple sessions accumulate in the same bundle's index" {
  local dir="$HOME/proj" home="$HOME/.claude" sid1="abc123def456" sid2="def456abc123" out="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$dir"
  _write_claude_transcript "$sid1" "$dir" "$home"
  _write_row "$sid1" "$dir" "$home" claude false "first session" "s1"
  run afx_export abc123 --format okf --out "$out"
  [ "$status" -eq 0 ]

  _write_claude_transcript "$sid2" "$dir" "$home"
  _write_row "$sid2" "$dir" "$home" claude false "second session" "s2"
  run afx_export def456 --format okf --out "$out"
  [ "$status" -eq 0 ]

  [ "$(find "$out/sessions" -name '*.md' | wc -l | tr -d ' ')" -eq 2 ]
  grep -q "first session" "$out/index.md"
  grep -q "second session" "$out/index.md"
}
