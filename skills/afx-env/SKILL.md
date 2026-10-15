---
name: afx-env
description: Find which Python environment (venv/conda) to use for the current project on this machine. Use before running python, pip, pytest, or installing packages in any project, or when a command fails with missing modules or the wrong interpreter.
---

Python environments differ per machine and are not recorded in repos. This machine's map lives in `~/.afx/envs.jsonl`, managed by `afx env`.

- `afx env which` prints the interpreter for the current directory (exit 1 if none is mapped).
- `afx env which --activate` prints the activation command, if one is registered (needed for e.g. `module load` or conda setups).
- `afx env list` shows every registered environment.
- If nothing is mapped, run `afx env discover` to list candidates, then ask the user which one to register with `afx env add <name> <python> --repo <dir>`. Do not guess an environment and do not create a new one unasked.

Run code with the resolved interpreter, e.g. `"$(afx env which)" -m pytest`, rather than bare `python`, `pip`, or `pytest`.
