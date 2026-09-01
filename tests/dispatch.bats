#!/usr/bin/env bats
# Tests for `afx`'s own dispatcher -- routing a subcommand name to the
# right afx_* function, and its unknown-command/help fallbacks. Doesn't
# cover what star/go/list/etc. actually DO once dispatched to (those are
# state-mutating and belong in a separate, sandboxed-HOME suite); this
# only tests that `afx <word>` reaches the right place, or fails clearly
# when it doesn't recognize `<word>`.

setup() {
  source "$BATS_TEST_DIRNAME/../afx.sh"
}

@test "afx: unknown subcommand fails with exit 1 and a clear stderr message" {
  run afx foo
  [ "$status" -eq 1 ]
  [[ "$output" == *"afx: unknown command: foo"* ]]
  [[ "$output" == *"afx help"* ]]
}

@test "afx: no arguments at all falls through to help" {
  run afx
  [ "$status" -eq 0 ]
  [[ "$output" == *"afx — a CLI for coding-agent sessions"* ]]
}

@test "afx help / --help / -h all print the same help text" {
  run afx help
  local via_help="$output"
  run afx --help
  local via_dashdash="$output"
  run afx -h
  local via_dash="$output"
  [ "$via_help" = "$via_dashdash" ]
  [ "$via_help" = "$via_dash" ]
  [[ "$via_help" == *"afx star"*"afx go"*"afx list"* ]]
}

@test "afx help: lists every real subcommand" {
  run afx help
  for c in star go list status rm find jobs push pull cp mv; do
    [[ "$output" == *"afx $c"* ]]
  done
}
