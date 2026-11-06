#!/usr/bin/env bats
# Tests for campaigns: afx campaign / afx tag / afx close / afx brief and
# _afx_classify, against a sandboxed $HOME. The LLM is replaced by
# $AFX_CLASSIFY_CMD, a shell command that prints a canned reply.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.afx" "$HOME/turb/sickle" "$HOME/turb/lfr" "$HOME/tools/afx" "$HOME/misc"
  export AFX_SESSIONS="$HOME/.afx/sessions.jsonl"
  export AFX_CAMPAIGNS="$HOME/.afx/campaigns.json"
  export AFX_META="$HOME/.afx/meta.jsonl"
  export AFX_HOST=testhost
  unset CLAUDE_CODE_SESSION_ID AFX_HIDE_DIRS AFX_PALETTE AFX_HASH_COLOR
  export NO_COLOR=1
  source "$BATS_TEST_DIRNAME/../afx.sh"
}

# $1 sid, $2 dir, $3 summary, $4 date (default: now)
_write_row() {
  jq -nc --arg date "${4:-$(date '+%F %H:%M')}" --arg sid "$1" --arg dir "$2" --arg summary "$3" \
    '{date:$date, session_id:$sid, dir:$dir, home:"~/.claude", tool:"claude", reason:"exit",
      summary:$summary, detail:null, starred:false, note:null}' >> "$AFX_SESSIONS"
}

# ==================== afx campaign ====================

@test "afx campaign add: stores title and ~-relative dirs" {
  run afx campaign add turb MaxEnt sampling --dir "$HOME/turb"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.turb.title' "$AFX_CAMPAIGNS")" = "MaxEnt sampling" ]
  [ "$(jq -r '.turb.dirs[0]' "$AFX_CAMPAIGNS")" = "~/turb" ]
}

@test "afx campaign add: re-adding appends dirs and keeps the title" {
  afx campaign add turb MaxEnt --dir "$HOME/turb/sickle"
  afx campaign add turb --dir "$HOME/turb/lfr"
  [ "$(jq -r '.turb.title' "$AFX_CAMPAIGNS")" = "MaxEnt" ]
  [ "$(jq -c '.turb.dirs' "$AFX_CAMPAIGNS")" = '["~/turb/lfr","~/turb/sickle"]' ]
}

@test "afx campaign add: rejects reserved and malformed names" {
  run afx campaign add none
  [ "$status" -eq 1 ]
  run afx campaign add "has space"
  [ "$status" -eq 1 ]
  # relative dirs must exist here; absolute ones may live on another machine
  cd "$HOME"
  run afx campaign add ok --dir does-not-exist
  [ "$status" -eq 1 ]
  run afx campaign add ok --dir /lustre/orion/proj
  [ "$status" -eq 0 ]
}

@test "afx campaign list: counts sessions per campaign by dir" {
  afx campaign add turb --dir "$HOME/turb"
  afx campaign add tools --dir "$HOME/tools"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "one"
  _write_row bbbbbb222222 "$HOME/turb/lfr" "two"
  _write_row cccccc333333 "$HOME/tools/afx" "three"
  run afx campaign list
  [ "$status" -eq 0 ]
  [[ "$(grep '^turb' <<<"$output")" == *"2 sessions"* ]]
  [[ "$(grep '^tools' <<<"$output")" == *"1 sessions"* ]]
}

@test "afx campaign rm: removes the campaign" {
  afx campaign add turb --dir "$HOME/turb"
  run afx campaign rm turb
  [ "$status" -eq 0 ]
  [ "$(jq 'has("turb")' "$AFX_CAMPAIGNS")" = false ]
  run afx campaign rm turb
  [ "$status" -eq 1 ]
}

# ==================== afx brief ====================

@test "afx brief: groups by dir, longest matching dir wins" {
  afx campaign add turb --dir "$HOME/turb"
  afx campaign add sickle --dir "$HOME/turb/sickle"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "sickle work"
  _write_row bbbbbb222222 "$HOME/turb/lfr" "lfr work"
  run afx brief
  [ "$status" -eq 0 ]
  # each row is listed right under its own campaign's header
  [[ "$(grep -A1 '^sickle ' <<<"$output")" == *"aaaaaa"* ]]
  [[ "$(grep -A1 '^turb ' <<<"$output")" == *"bbbbbb"* ]]
}

@test "afx brief: unmatched sessions are unfiled, with their top dirs" {
  afx campaign add turb --dir "$HOME/turb"
  # outside $HOME: bats' $HOME is under /tmp, which brief treats as scratch
  _write_row aaaaaa111111 /srv/stray "stray"
  run afx brief
  [[ "$output" == *"unfiled"* ]]
  [[ "$output" == *"top dirs: /srv/stray (1)"* ]]
  [[ "$output" == *"aaaaaa"* ]]
}

@test "afx brief: hides tmp-dir sessions unless tagged" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 /tmp "scratch"
  run afx brief
  [[ "$output" != *"aaaaaa"* ]]
  afx tag aaaaaa turb
  run afx brief
  [[ "$(grep -A1 '^turb ' <<<"$output")" == *"aaaaaa"* ]]
}

@test "afx brief: sessions older than -d are quiet, not listed" {
  afx campaign add turb --dir "$HOME/turb"
  afx campaign add tools --dir "$HOME/tools"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "old" "2020-01-01 10:00"
  run afx brief -d 7
  [[ "$output" != *"aaaaaa"* ]]
  [[ "$output" == *"quiet: "*"turb ("* ]]
  [[ "$output" == *"tools (no sessions)"* ]]
}

@test "afx brief: shows state, title and next items from meta" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "first prompt text"
  _afx_meta_upsert aaaaaa111111 '{"state":"waiting","title":"Training UNet models","next":["review the sweep CSV"]}'
  run afx brief
  [[ "$output" == *"waiting  aaaaaa"* ]]
  [[ "$output" == *"Training UNet models"* ]]
  [[ "$output" != *"first prompt text"* ]]
  [[ "$output" == *"→ review the sweep CSV"* ]]
}

@test "afx brief: tags next items by who does them; --for filters" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "mixed"
  _write_row bbbbbb222222 "$HOME/turb/lfr" "human only"
  _write_row cccccc333333 "$HOME/turb/lfr" "legacy"
  _afx_meta_upsert aaaaaa111111 '{"state":"in-progress","next":[{"do":"rerun the tests","by":"agent"},{"do":"pick a threshold","by":"human"}]}'
  _afx_meta_upsert bbbbbb222222 '{"state":"blocked","next":[{"do":"email the PI","by":"human"}]}'
  _afx_meta_upsert cccccc333333 '{"state":"in-progress","next":["old untagged step"]}'
  run afx brief
  [[ "$output" == *"→ agent: rerun the tests"* ]]
  [[ "$output" == *"→ you: pick a threshold"* ]]
  [[ "$output" == *"→ old untagged step"* ]]
  run afx brief --for agent
  [ "$status" -eq 0 ]
  [[ "$output" == *"aaaaaa"*"→ agent: rerun the tests"* ]]
  [[ "$output" != *"pick a threshold"* ]]
  [[ "$output" != *"bbbbbb"* ]]
  [[ "$output" != *"old untagged step"* ]]
  [[ "$output" == *"3 open, 0 done"* ]]
  run afx brief --human
  [[ "$output" == *"→ you: pick a threshold"* ]]
  [[ "$output" == *"→ you: email the PI"* ]]
  [[ "$output" != *"rerun the tests"* ]]
  [[ "$output" != *"cccccc"* ]]
  run afx brief --for robots
  [ "$status" -ne 0 ]
}

@test "afx brief: shows the host of a session from another machine" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "elsewhere"
  _afx_meta_upsert aaaaaa111111 '{"host":"frontier","state":"in-progress"}'
  run afx brief
  [[ "$output" == *"@frontier"* ]]
}

@test "afx brief: -c limits to one campaign" {
  afx campaign add turb --dir "$HOME/turb"
  afx campaign add tools --dir "$HOME/tools"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "t"
  _write_row bbbbbb222222 "$HOME/tools/afx" "x"
  run afx brief -c tools
  [[ "$output" == *"bbbbbb"* ]]
  [[ "$output" != *"aaaaaa"* ]]
}

@test "afx brief: -n caps rows per campaign" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "a"
  _write_row bbbbbb222222 "$HOME/turb/sickle" "b"
  _write_row cccccc333333 "$HOME/turb/sickle" "c"
  run afx brief -n 2
  [[ "$output" == *"+1 more"* ]]
}

# ==================== afx tag / afx close ====================

@test "afx tag: overrides the dir's campaign; - clears it" {
  afx campaign add turb --dir "$HOME/turb"
  afx campaign add tools --dir "$HOME/tools"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "really afx work"
  run afx tag aaaaaa tools
  [ "$status" -eq 0 ]
  run afx brief
  [[ "$(grep -A1 '^tools ' <<<"$output")" == *"aaaaaa"* ]]
  afx tag aaaaaa -
  run afx brief
  [[ "$(grep -A1 '^turb ' <<<"$output")" == *"aaaaaa"* ]]
}

@test "afx tag: none hides the session from brief" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "noise"
  afx tag aaaaaa none
  run afx brief
  [[ "$output" != *"aaaaaa"* ]]
}

@test "afx tag: rejects an unknown campaign or session" {
  _write_row aaaaaa111111 "$HOME/turb/sickle" "x"
  run afx tag aaaaaa nope
  [ "$status" -eq 1 ]
  afx campaign add turb --dir "$HOME/turb"
  run afx tag ffffff turb
  [ "$status" -eq 1 ]
}

@test "afx tag: a bare campaign tags the current session inside one" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/misc" "x"
  CLAUDE_CODE_SESSION_ID=aaaaaa111111 run afx tag turb
  [ "$status" -eq 0 ]
  [ "$(jq -r '.campaign' "$AFX_META")" = turb ]
}

@test "afx close: marks done, drops next, and brief stops listing it" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "x"
  _afx_meta_upsert aaaaaa111111 '{"state":"in-progress","next":["do it"]}'
  run afx close aaaaaa
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.state, .next]' "$AFX_META")" = '["done",[]]' ]
  run afx brief
  [[ "$output" != *"aaaaaa"* ]]
  [[ "$output" == *"0 open, 1 done"* ]]
  run afx brief -a
  [[ "$output" == *"aaaaaa"* ]]
}

@test "_afx_meta_upsert: merges fields and keeps the first host" {
  _afx_meta_upsert s1 '{"campaign":"turb"}'
  AFX_HOST=other _afx_meta_upsert s1 '{"state":"done"}'
  [ "$(wc -l < "$AFX_META" | tr -d ' ')" = 1 ]
  [ "$(jq -c '[.campaign, .state, .host]' "$AFX_META")" = '["turb","done","testhost"]' ]
}

# ==================== _afx_classify ====================

@test "_afx_classify: parses a fenced reply, keeps known campaigns, caps next" {
  afx campaign add turb --dir "$HOME/turb"
  export AFX_CLASSIFY_CMD='cat >/dev/null; printf "Sure:\n\`\`\`json\n{\"title\":\"Trained models\",\"campaign\":\"turb\",\"state\":\"waiting\",\"next\":[\"a\",\"b\",\"c\",\"d\"]}\n\`\`\`\n"'
  run _afx_classify s1 "text"
  [ "$status" -eq 0 ]
  [ "$output" = "turb waiting" ]
  [ "$(jq -c '[.campaign_guess, .state, (.next | length), .title]' "$AFX_META")" = '["turb","waiting",3,"Trained models"]' ]
}

@test "_afx_classify: keeps agent/human tags; bare or unknown tags become human" {
  export AFX_CLASSIFY_CMD='cat >/dev/null; echo "{\"state\":\"in-progress\",\"next\":[{\"do\":\"run  tests\",\"by\":\"agent\"},{\"do\":\"decide\",\"by\":\"human\"},{\"do\":\"x\",\"by\":\"robot\"},\"bare\",{\"by\":\"agent\"}]}"'
  run _afx_classify s1 "text"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.next' "$AFX_META")" = '[{"do":"run tests","by":"agent"},{"do":"decide","by":"human"},{"do":"x","by":"human"}]' ]
}

@test "_afx_classify: the prompt asks who can do each step" {
  export AFX_CLASSIFY_CMD="cat > '$BATS_TEST_TMPDIR/prompt'; echo '{}'"
  _afx_classify s1 "text"
  grep -q '"by": "agent" or "human"' "$BATS_TEST_TMPDIR/prompt"
}

@test "_afx_classify: unknown campaign and bad state are normalized" {
  export AFX_CLASSIFY_CMD='cat >/dev/null; echo "{\"campaign\":\"made-up\",\"state\":\"finished\",\"next\":[]}"'
  run _afx_classify s1 "text"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.campaign_guess, .state]' "$AFX_META")" = '[null,"in-progress"]' ]
}

@test "_afx_classify: a non-JSON reply stores nothing and fails" {
  export AFX_CLASSIFY_CMD='cat >/dev/null; echo "I cannot help with that."'
  run _afx_classify s1 "text"
  [ "$status" -eq 1 ]
  [ ! -s "$AFX_META" ]
}

@test "_afx_classify: the prompt lists registered campaigns" {
  afx campaign add turb MaxEnt sampling --dir "$HOME/turb"
  export AFX_CLASSIFY_CMD="cat > '$BATS_TEST_TMPDIR/prompt'; echo '{}'"
  _afx_classify s1 "text"
  grep -q -- "- turb: MaxEnt sampling (dirs: ~/turb)" "$BATS_TEST_TMPDIR/prompt"
}

@test "afx campaign classify: backfills unclassified rows, skips classified ones" {
  afx campaign add turb --dir "$HOME/turb"
  _write_row aaaaaa111111 "$HOME/turb/sickle" "a"
  _write_row bbbbbb222222 "$HOME/turb/lfr" "b"
  _afx_meta_upsert bbbbbb222222 '{"state":"done"}'
  export AFX_CLASSIFY_CMD='cat >/dev/null; echo "{\"campaign\":\"turb\",\"state\":\"blocked\",\"next\":[\"x\"]}"'
  run afx campaign classify --dry-run
  [[ "$output" == "1 session(s) to classify"* ]]
  run afx campaign classify
  [ "$status" -eq 0 ]
  [[ "$output" == *"aaaaaa"*"turb blocked"* ]]
  [ "$(jq -r 'select(.session_id=="bbbbbb222222") | .state' "$AFX_META")" = done ]
}
