#!/usr/bin/env bats
# Unit tests for afx.sh's pure(ish) helper functions -- string/number
# formatting and lookups with no state-file or network side effects.
# State-mutating commands (star/go/list/find/rm/cp/mv) and network commands
# (push/pull) are intentionally out of scope here; see DESIGN.md for why
# those need a different (sandboxed-HOME) test setup.

setup() {
  # afx.sh only defines functions (plus a `complete` registration guarded
  # to bash), so sourcing it has no side effects beyond that.
  source "$BATS_TEST_DIRNAME/../afx.sh"
}

# --- _afx_truncate ---

@test "_afx_truncate: leaves a string shorter than max untouched" {
  run _afx_truncate "hello" 10
  [ "$output" = "hello" ]
}

@test "_afx_truncate: leaves a string exactly at max untouched" {
  run _afx_truncate "hello" 5
  [ "$output" = "hello" ]
}

@test "_afx_truncate: truncates and appends an ellipsis, total length == max" {
  run _afx_truncate "hello world" 8
  [ "$output" = "hello..." ]
  [ "${#output}" -eq 8 ]
}

# --- _afx_account ---

@test "_afx_account: .claude maps to default" {
  run _afx_account "$HOME/.claude"
  [ "$output" = "default" ]
}

@test "_afx_account: .codex maps to default" {
  run _afx_account "$HOME/.codex"
  [ "$output" = "default" ]
}

@test "_afx_account: .gemini maps to default" {
  run _afx_account "$HOME/.gemini"
  [ "$output" = "default" ]
}

@test "_afx_account: .claude-work maps to work" {
  run _afx_account "$HOME/.claude-work"
  [ "$output" = "work" ]
}

@test "_afx_account: .codex-work maps to work" {
  run _afx_account "$HOME/.codex-work"
  [ "$output" = "work" ]
}

@test "_afx_account: unrecognized basename passes through unchanged" {
  run _afx_account "/some/oddly-named-dir"
  [ "$output" = "oddly-named-dir" ]
}

# --- _afx_display_dir ---

@test "_afx_display_dir: \$HOME collapses to ~" {
  run _afx_display_dir "$HOME" 0
  [ "$output" = "~" ]
}

@test "_afx_display_dir: default mode shows only the basename" {
  run _afx_display_dir "$HOME/foo/bar" 0
  [ "$output" = "bar" ]
}

@test "_afx_display_dir: full mode (\$2=1) shows the ~-shortened full path" {
  run _afx_display_dir "$HOME/foo/bar" 1
  [ "$output" = "~/foo/bar" ]
}

@test "_afx_display_dir: root stays / even in default mode" {
  run _afx_display_dir "/" 0
  [ "$output" = "/" ]
}

@test "_afx_display_dir: a path outside \$HOME is left as-is in full mode" {
  run _afx_display_dir "/var/tmp/proj" 1
  [ "$output" = "/var/tmp/proj" ]
}

# --- _afx_nearest_idx ---

@test "_afx_nearest_idx: exact match picks that index" {
  run _afx_nearest_idx 95 0 95 135 175 215 255
  [ "$output" = "1" ]
}

@test "_afx_nearest_idx: value between two levels picks the closer one" {
  run _afx_nearest_idx 100 0 95 135 175 215 255
  [ "$output" = "1" ]
}

@test "_afx_nearest_idx: exact tie prefers the earlier (lower) index" {
  run _afx_nearest_idx 50 0 100
  [ "$output" = "0" ]
}

# --- _afx_256_nearest ---

@test "_afx_256_nearest: pure black maps to color-cube index 16" {
  run _afx_256_nearest 0 0 0
  [ "$output" = "16" ]
}

@test "_afx_256_nearest: pure white maps to color-cube index 231" {
  run _afx_256_nearest 255 255 255
  [ "$output" = "231" ]
}

@test "_afx_256_nearest: pure red maps to color-cube index 196" {
  run _afx_256_nearest 255 0 0
  [ "$output" = "196" ]
}

# --- _afx_parse_color ---

@test "_afx_parse_color: parses a #RRGGBB hex color" {
  run _afx_parse_color "#ff0000"
  [ "$status" -eq 0 ]
  [ "$output" = "255 0 0" ]
}

@test "_afx_parse_color: parses a bare RRGGBB hex color (no #)" {
  run _afx_parse_color "00ff00"
  [ "$output" = "0 255 0" ]
}

@test "_afx_parse_color: parses R,G,B decimal" {
  run _afx_parse_color "0,0,255"
  [ "$output" = "0 0 255" ]
}

@test "_afx_parse_color: strips embedded whitespace before parsing" {
  run _afx_parse_color "  #ff0000  "
  [ "$output" = "255 0 0" ]
}

@test "_afx_parse_color: fails (no output, nonzero exit) on garbage input" {
  run _afx_parse_color "not-a-color"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_afx_parse_color: fails on empty input" {
  run _afx_parse_color ""
  [ "$status" -ne 0 ]
}

# --- _afx_hash_len ---

@test "_afx_hash_len: defaults to 6 when every id already differs at 6 chars" {
  run _afx_hash_len <<< $'abcdef01\nfedcba98\n123456ff'
  [ "$output" = "6" ]
}

@test "_afx_hash_len: extends past 6 when ids collide at that length" {
  run _afx_hash_len <<< $'abcdef01\nabcdef02'
  [ "$output" = "8" ]
}

@test "_afx_hash_len: defaults to 6 on empty stdin" {
  run _afx_hash_len <<< ""
  [ "$output" = "6" ]
}

@test "_afx_hash_len: defaults to 6 for a single id" {
  run _afx_hash_len <<< "abcdef01"
  [ "$output" = "6" ]
}

# --- _afx_date_fmt ---

@test "_afx_date_fmt: formats a stored date to a requested strftime format" {
  run _afx_date_fmt "2024-01-15 10:30" "+%Y-%m-%d"
  [ "$output" = "2024-01-15" ]
}

@test "_afx_date_fmt: fails silently on an unparseable date" {
  run _afx_date_fmt "not-a-date" "+%Y"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# --- _afx_relative_date ---

@test "_afx_relative_date: a moment just now reads 'now'" {
  # The stored format is minute-precision only, so it can floor a "then"
  # timestamp down by up to 59s. Using the current, unmodified minute
  # (rather than e.g. "-30 seconds") keeps the diff under 60s regardless
  # of where in the minute this actually runs, avoiding a flaky boundary
  # case right after :00.
  local ts; ts="$(date '+%Y-%m-%d %H:%M')"
  run _afx_relative_date "$ts"
  [ "$output" = "now" ]
}

@test "_afx_relative_date: minutes ago reads Nm" {
  local ts; ts="$(date -d '-5 minutes' '+%Y-%m-%d %H:%M')"
  run _afx_relative_date "$ts"
  [[ "$output" =~ ^[0-9]+m$ ]]
}

@test "_afx_relative_date: hours ago reads Nh" {
  local ts; ts="$(date -d '-3 hours' '+%Y-%m-%d %H:%M')"
  run _afx_relative_date "$ts"
  [[ "$output" =~ ^[0-9]+h$ ]]
}

@test "_afx_relative_date: days ago (within a week) reads Nd" {
  local ts; ts="$(date -d '-2 days' '+%Y-%m-%d %H:%M')"
  run _afx_relative_date "$ts"
  [[ "$output" =~ ^[0-9]+d$ ]]
}

@test "_afx_relative_date: over a week ago falls back to a month/day format" {
  local ts; ts="$(date -d '-10 days' '+%Y-%m-%d %H:%M')"
  run _afx_relative_date "$ts"
  [[ "$output" =~ ^[A-Z][a-z]{2}\ [0-9]{2}( [0-9]{4})?$ ]]
}

@test "_afx_relative_date: falls back to the raw string when unparseable" {
  run _afx_relative_date "not-a-date"
  [ "$output" = "not-a-date" ]
}

# --- _afx_proj_dir ---

@test "_afx_proj_dir: munges every non-alphanumeric cwd character to '-'" {
  run _afx_proj_dir "$HOME/.claude" "/home/x/my-proj"
  [ "$output" = "$HOME/.claude/projects/-home-x-my-proj" ]
}

# --- _afx_repo_key ---

@test "_afx_repo_key: returns the git toplevel for a path inside a repo" {
  local repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/sub"
  git -C "$repo" init -q
  run _afx_repo_key "$repo/sub"
  [ "$output" = "$repo" ]
}

@test "_afx_repo_key: falls back to the literal path outside any repo" {
  local plain="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$plain"
  run _afx_repo_key "$plain"
  [ "$output" = "$plain" ]
}

# --- _afx_sed_escape ---

@test "_afx_sed_escape: escapes /, &, and |" {
  run _afx_sed_escape 'a/b&c|d'
  [ "$output" = 'a\/b\&c\|d' ]
}

@test "_afx_sed_escape: leaves ordinary characters untouched" {
  run _afx_sed_escape 'plain-text_123'
  [ "$output" = 'plain-text_123' ]
}
