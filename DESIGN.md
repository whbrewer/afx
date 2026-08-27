# afx — design notes

## Why a fork, not a wrapper

afx is [xmarks](https://github.com/whbrewer/xmarks) forked and rebranded
as artifax.dev's own CLI, not a thin alias layer on top of it. xmarks
already talks to artifax.dev over plain HTTP (`xp`/`xr`, now `afx
push`/`afx pull`) with no shared code beyond that — so there's nothing a
wrapper would actually save, and afx is expected to grow features xmarks
has no reason to carry (deeper artifax.dev integration, project/session
management beyond push/pull, etc). xmarks keeps working as-is for anyone
already using it; it just isn't where new commands land.

## Bashmarks verbs, two words instead of one letter

xmarks' verbs: `s` save, `g` go, `l` list, `d` delete (from bashmarks).
xmarks' equivalents: `xs`, `xg`, `xl`, `xd`, plus `xp`/`xr` (push/pull to
artifax.dev), `xf` (find in transcripts), `xj` (jobs), `xq` (status).

afx equivalent, one dispatcher instead of eight single-letter commands:

| xmarks | afx |
|---|---|
| `xs` | `afx star` |
| `xg` | `afx go` |
| `xl` | `afx list` |
| `xq` | `afx status` |
| `xd` | `afx rm` |
| `xf` | `afx find` |
| `xj` | `afx jobs` |
| `xp` | `afx push` |
| `xr` | `afx pull` |

## One dispatcher instead of eight wrapper binaries

xmarks installs `xs` as a real executable, then symlinks `xg`/`xl`/`xd`/
`xf`/`xj`/`xp`/`xr` to it — each figures out which command it's playing
via `$(basename "$0")`. That trick exists because `xg` needs `cd` to
happen in the *caller's* shell, which only works if it's a shell function
(what sourcing `xmarks.sh` provides), not a subprocess — but a subprocess
form still has to exist for shells that never source `.bashrc` (Claude
Code's `! xg ...`).

Collapsing every command into one name removes the need for that
per-command duplication: `afx.sh` defines a single `afx()` function that
dispatches on its first argument, and the installed `afx` executable is
just `source afx.sh; afx "$@"`. Same two forms (function vs. subprocess,
same `cd` caveat), one pair of files instead of eight.

## State migration from xmarks

A fresh afx install with existing xmarks state shouldn't start empty:
the first time any `afx` command runs, if `~/.afx` doesn't exist yet and
`~/.xmarks/sessions.jsonl` does, it's copied over once. Copied, not
moved — xmarks keeps working against its own `~/.xmarks` untouched, the
two directories just diverge from that point on. Everything under
`~/.afx` (`secret-rules.json`, `session-projects.json`, `jobs.jsonl`)
otherwise starts fresh, since none of that is what a user actually
misses when switching tools.
