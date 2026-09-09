#!/usr/bin/env bats
# Tests for afx_port -- the cross-tool (Claude Code <-> Codex) session
# handoff. Everything here uses --dump/--out so no real `claude`/`codex`
# binary is ever invoked; afx_go/afx_cp/afx_mv already cover the "launch
# the native tool" side of things for same-tool resume.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.afx"
  export AFX_SESSIONS="$HOME/.afx/sessions.jsonl"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AFX_CONFIG_DIRS AFX_CODEX_HOMES CODEX_HOME AFX_PALETTE AFX_HASH_COLOR AFX_PORT_MAXCHARS
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

# A small but representative Claude Code transcript: a user ask, an
# assistant text + tool_use, the tool_result coming back as a "user" turn,
# a final assistant text, and one isSidechain turn that must NOT appear in
# the rendered output.
_write_claude_transcript() {
  local sid="$1" dir="$2" home="$3"
  local projdir; projdir="$(_afx_proj_dir "$home" "$dir")"
  mkdir -p "$projdir"
  {
    jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"help me write a script"}}'
    jq -nc '{type:"assistant", isSidechain:false, message:{role:"assistant", content:[
      {type:"text", text:"Sure, let me check the repo."},
      {type:"tool_use", id:"toolu_1", name:"Bash", input:{command:"ls"}}
    ]}}'
    jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:[
      {type:"tool_result", tool_use_id:"toolu_1", content:"file1.txt\nfile2.txt"}
    ]}}'
    jq -nc '{type:"assistant", isSidechain:false, message:{role:"assistant", content:[
      {type:"text", text:"Done, created file1.txt"}
    ]}}'
    jq -nc '{type:"user", isSidechain:true, message:{role:"user", content:"a subagent question that must not leak into the handoff"}}'
  } > "$projdir/$sid.jsonl"
}

# A small representative Codex rollout: a developer boilerplate message
# (must be skipped), a user message plus its event_msg duplicate (must
# also be skipped), a function_call/function_call_output pair, and a final
# assistant message.
_write_codex_transcript() {
  local sid="$1" home="$2"
  local sessdir="$home/sessions/2024/01/01"
  mkdir -p "$sessdir"
  {
    jq -nc '{type:"session_meta", payload:{id:"'"$sid"'", cwd:"'"$3"'"}}'
    jq -nc '{type:"response_item", payload:{type:"message", role:"developer", content:[
      {type:"input_text", text:"<permissions instructions> boilerplate that must not leak"}
    ]}}'
    jq -nc '{type:"response_item", payload:{type:"message", role:"user", content:[
      {type:"input_text", text:"run the tests"}
    ]}}'
    jq -nc '{type:"event_msg", payload:{type:"user_message", message:"run the tests"}}'
    jq -nc '{type:"response_item", payload:{type:"function_call", name:"shell", arguments:"{\"command\":[\"pytest\"]}", call_id:"call_1"}}'
    jq -nc '{type:"response_item", payload:{type:"function_call_output", call_id:"call_1", output:"5 passed"}}'
    jq -nc '{type:"response_item", payload:{type:"message", role:"assistant", content:[
      {type:"output_text", text:"All 5 tests passed."}
    ]}}'
  } > "$sessdir/$sid.jsonl"
}

# ==================== usage / guard-rail errors ====================

@test "afx_port: usage error without --to" {
  run afx_port abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: afx port"* ]]
}

@test "afx_port: rejects an invalid --to value" {
  run afx_port abc123 --to gemini
  [ "$status" -eq 1 ]
  [[ "$output" == *"--to must be claude or codex"* ]]
}

@test "afx_port: no session matching an unknown hash" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_port zzzzzz --to codex
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such session: zzzzzz"* ]]
}

@test "afx_port: refuses when the target tool is the same as the source" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_port abc123 --to claude
  [ "$status" -eq 1 ]
  [[ "$output" == *"already a claude session"* ]]
  [[ "$output" == *"afx go abc123"* ]]
}

@test "afx_port: fails clearly when the transcript file is missing" {
  _write_row "abc123def456" "$HOME/proj" "$HOME/.claude" claude false "" "did stuff"
  run afx_port abc123 --to codex
  [ "$status" -eq 1 ]
  [[ "$output" == *"transcript file not found"* ]]
}

# ==================== claude -> codex ====================

@test "afx_port: renders a Claude transcript for a Codex handoff via --dump" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  mkdir -p "$dir"
  _write_claude_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"

  run afx_port abc123 --to codex --dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"handoff from a claude coding-agent session"* ]]
  [[ "$output" == *"### User"* ]]
  [[ "$output" == *"help me write a script"* ]]
  [[ "$output" == *"**Tool call:** \`Bash\`"* ]]
  [[ "$output" == *"**Tool result** (\`Bash\`)"* ]]
  [[ "$output" == *"file1.txt"* ]]
  [[ "$output" == *"Done, created file1.txt"* ]]
  [[ "$output" != *"must not leak into the handoff"* ]]
}

@test "afx_port: --out writes the handoff to a file as well" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  mkdir -p "$dir"
  _write_claude_transcript "$sid" "$dir" "$home"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"

  local out="$BATS_TEST_TMPDIR/handoff.md"
  run afx_port abc123 --to codex --dump --out "$out"
  [ "$status" -eq 0 ]
  [ -s "$out" ]
  grep -q "help me write a script" "$out"
}

# ==================== codex -> claude ====================

@test "afx_port: renders a Codex transcript for a Claude handoff via --dump" {
  local dir="$HOME/proj" home="$HOME/.codex" sid="019dda9d1cba78b2940f8f8df1878975"
  mkdir -p "$dir"
  _write_codex_transcript "$sid" "$home" "$dir"
  _write_row "$sid" "$dir" "$home" codex false "" "did stuff"

  run afx_port "${sid:0:6}" --to claude --dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"handoff from a codex coding-agent session"* ]]
  [[ "$output" == *"### User"* ]]
  [[ "$output" == *"run the tests"* ]]
  [[ "$output" == *"**Tool call:** \`shell\`"* ]]
  [[ "$output" == *"**Tool result** (\`shell\`)"* ]]
  [[ "$output" == *"5 passed"* ]]
  [[ "$output" == *"All 5 tests passed."* ]]
  [[ "$output" != *"permissions instructions"* ]]
  # the event_msg duplicate of the user message must not double it up
  [ "$(grep -c '^### User$' <<<"$output")" -eq 1 ]
}

# ==================== oversized transcripts ====================

@test "afx_port: elides an oversized transcript per \$AFX_PORT_MAXCHARS" {
  local dir="$HOME/proj" home="$HOME/.claude" sid="abc123def456"
  mkdir -p "$(_afx_proj_dir "$home" "$dir")"
  {
    jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"the original ask"}}'
    for i in $(seq 1 200); do
      jq -nc --arg t "filler turn number $i with some padding text to grow the transcript" \
        '{type:"assistant", isSidechain:false, message:{role:"assistant", content:[{type:"text", text:$t}]}}'
    done
    jq -nc '{type:"assistant", isSidechain:false, message:{role:"assistant", content:[{type:"text", text:"the most recent turn"}]}}'
  } > "$(_afx_proj_dir "$home" "$dir")/$sid.jsonl"
  _write_row "$sid" "$dir" "$home" claude false "" "did stuff"

  export AFX_PORT_MAXCHARS=2000
  run afx_port abc123 --to codex --dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"the original ask"* ]]
  [[ "$output" == *"the most recent turn"* ]]
  [[ "$output" == *"characters elided from the middle"* ]]
}
