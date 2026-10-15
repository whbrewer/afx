#!/usr/bin/env bats
# Tests for `afx env` (the per-machine Python environment map) and the
# afx-claude-pretooluse hook that enforces it. Sandboxed $HOME; "environments"
# are fake executables, so no real python/venv is needed.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.afx"
  export AFX_ENVS="$HOME/.afx/envs.jsonl"
  unset CLAUDE_CODE_SESSION_ID AFX_IN_HOOK
  export NO_COLOR=1
  source "$BATS_TEST_DIRNAME/../afx.sh"
  HOOK="$BATS_TEST_DIRNAME/../hooks/afx-claude-pretooluse"
  # fake env: <dir>/bin/python (executable) plus pyvenv.cfg for discover
  _mkenv() { mkdir -p "$1/bin"; printf '#!/bin/sh\n' > "$1/bin/python"; chmod +x "$1/bin/python"; : > "$1/pyvenv.cfg"; }
  _mkenv "$HOME/venvs/alpha"
  _mkenv "$HOME/venvs/beta"
  mkdir -p "$HOME/code/proj/sub" "$HOME/code/proj/nested" "$HOME/code/other"
}

@test "afx env add: registers a row with python and repo" {
  run afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.python' "$AFX_ENVS")" = "$HOME/venvs/alpha/bin/python" ]
  [ "$(jq -r '.repos[0]' "$AFX_ENVS")" = "$HOME/code/proj" ]
}

@test "afx env add: refuses a python that is not executable" {
  run afx env add bad "$HOME/nope/bin/python"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an executable file"* ]]
}

@test "afx env add: re-adding a name replaces its row, merging repos" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj" --notes hi
  afx env add alpha --repo "$HOME/code/other"
  [ "$(wc -l < "$AFX_ENVS")" -eq 1 ]
  [ "$(jq -r '.repos | length' "$AFX_ENVS")" -eq 2 ]
  [ "$(jq -r '.notes' "$AFX_ENVS")" = "hi" ]
}

@test "afx env add: does not follow the python symlink out of the venv" {
  ln -s /bin/sh "$HOME/venvs/beta/bin/python3"
  afx env add beta "$HOME/venvs/beta/bin/python3"
  [ "$(jq -r '.python' "$AFX_ENVS")" = "$HOME/venvs/beta/bin/python3" ]
}

@test "afx env which: resolves a subdirectory of a mapped repo" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  cd "$HOME/code/proj/sub"
  run afx env which
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/venvs/alpha/bin/python" ]
}

@test "afx env which: longest repo prefix wins" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  afx env add beta "$HOME/venvs/beta/bin/python" --repo "$HOME/code/proj/nested"
  run afx env which "$HOME/code/proj/nested"
  [ "$output" = "$HOME/venvs/beta/bin/python" ]
  run afx env which "$HOME/code/proj/sub"
  [ "$output" = "$HOME/venvs/alpha/bin/python" ]
}

@test "afx env which: a sibling dir sharing a name prefix does not match" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  mkdir -p "$HOME/code/proj-extra"
  run afx env which "$HOME/code/proj-extra"
  [ "$status" -eq 1 ]
}

@test "afx env which: by name, and --dir / --activate / --json" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --activate "source x/activate"
  run afx env which alpha
  [ "$output" = "$HOME/venvs/alpha/bin/python" ]
  run afx env which --dir alpha
  [ "$output" = "$HOME/venvs/alpha" ]
  run afx env which --activate alpha
  [ "$output" = "source x/activate" ]
  run afx env which --json alpha
  [ "$(jq -r '.name' <<<"$output")" = "alpha" ]
}

@test "afx env which: unmapped directory fails with exit 1" {
  run afx env which "$HOME/code/other"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no environment mapped"* ]]
}

@test "afx env rm: removes the row; unknown name fails" {
  afx env add alpha "$HOME/venvs/alpha/bin/python"
  run afx env rm alpha
  [ "$status" -eq 0 ]
  [ ! -s "$AFX_ENVS" ]
  run afx env rm alpha
  [ "$status" -eq 1 ]
}

@test "afx env list: shows rows and flags a missing interpreter" {
  afx env add alpha "$HOME/venvs/alpha/bin/python"
  run afx env list
  [[ "$output" == *"alpha"*"$HOME/venvs/alpha/bin/python"* ]]
  rm "$HOME/venvs/alpha/bin/python"
  run afx env list
  [[ "$output" == *"(missing)"* ]]
}

@test "afx env discover: lists candidates without writing by default" {
  run afx env discover "$HOME/venvs"
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
  [ ! -e "$AFX_ENVS" ]
}

@test "afx env discover: project .venv is named after the project and mapped to it" {
  _mkenv "$HOME/code/proj/.venv"
  run afx env discover --write "$HOME/code"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.name == "proj") | .repos[0]' "$AFX_ENVS")" = "$HOME/code/proj" ]
}

@test "afx env discover --write: skips an interpreter that is already registered" {
  afx env add mine "$HOME/venvs/alpha/bin/python"
  run afx env discover --write "$HOME/venvs"
  [[ "$output" == *"already registered"* ]]
  [ "$(jq -r 'select(.python == "'"$HOME"'/venvs/alpha/bin/python") | .name' "$AFX_ENVS")" = "mine" ]
}

@test "afx env: unknown subcommand fails" {
  run afx env frobnicate
  [ "$status" -eq 1 ]
}

# --- the PreToolUse hook ---

_hook () { jq -nc --arg c "$1" --arg d "$2" '{tool_input:{command:$c}, cwd:$d}' | "$HOOK"; }

@test "hook: blocks bare python in a mapped dir and names the interpreter" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  run _hook "python script.py" "$HOME/code/proj/sub"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$HOME/venvs/alpha/bin/python"* ]]
}

@test "hook: catches python later in a pipeline or after &&" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  run _hook "cd x && pip install foo" "$HOME/code/proj"
  [ "$status" -eq 2 ]
  run _hook "ls | pytest -q" "$HOME/code/proj"
  [ "$status" -eq 2 ]
}

@test "hook: allows a command that uses the mapped interpreter" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  run _hook "$HOME/venvs/alpha/bin/python script.py" "$HOME/code/proj"
  [ "$status" -eq 0 ]
}

@test "hook: allows activate / uv run / conda run" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  for c in "source foo/bin/activate && python x.py" "uv run python x.py" "conda run -n e python x.py"; do
    run _hook "$c" "$HOME/code/proj"
    [ "$status" -eq 0 ]
  done
}

@test "hook: allows non-python commands and unmapped dirs" {
  afx env add alpha "$HOME/venvs/alpha/bin/python" --repo "$HOME/code/proj"
  run _hook "ls -la" "$HOME/code/proj"
  [ "$status" -eq 0 ]
  run _hook "python script.py" "$HOME/code/other"
  [ "$status" -eq 0 ]
  run _hook "echo mypython" "$HOME/code/proj"
  [ "$status" -eq 0 ]
}

@test "hook: no registry at all is silent" {
  run _hook "python x.py" "$HOME/code/proj"
  [ "$status" -eq 0 ]
}
