# afx

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell: bash | zsh](https://img.shields.io/badge/shell-bash%20%7C%20zsh-89e051.svg)](#install)
[![Requires: jq](https://img.shields.io/badge/requires-jq-orange.svg)](#install)

artifax.dev's CLI: bashmarks-style bookmarks for coding-agent sessions
(Claude Code and Codex CLI) — save a mark, later jump back with one
command that cd's into the directory *and* resumes the exact session —
plus the client for pushing/pulling sessions to and from artifax.dev.

A fork of [xmarks](https://github.com/whbrewer/xmarks), rebranded and
rebuilt as one `afx` dispatcher: `xs`/`xg`/`xl`/`xd` become
`afx star`/`afx go`/`afx list`/`afx rm`, and so on. See `DESIGN.md` for
why. xmarks itself is no longer actively maintained; its short single-word
commands remain available for anyone already using them.

## Install

```bash
make install
echo 'source ~/.local/bin/afx.sh' >> ~/.bashrc
```

`make install` puts `afx.sh` plus the `afx` executable into `~/.local/bin`
(override with `PREFIX=...`); `make uninstall` removes them. The `afx`
executable exists because shells inside a Claude Code session
(`! afx ...`) never read `.bashrc`; in interactive shells the sourced
`afx` function shadows it. Only the function form can leave your shell in
the target session's directory after `afx go` — the binary version resumes
fine but can't do that for its parent shell — which is why the `source`
line above is still worth adding (put it above your bashrc's "not
interactive" guard).

Requires `jq` (for first-message previews). `fzf` is optional — if
present, `afx go` with no argument opens a fuzzy picker.

Sourcing `afx.sh` also registers tab completion — press `<TAB>` after
`afx` to complete a subcommand, then `<TAB>` again to complete an existing
session's HASH for subcommands that take one (`star`/`go`/`rm`/`push`).
Under bash this needs no separate step. Under zsh it needs the completion
system loaded first — if `afx <TAB>` doesn't do anything, add this to
`~/.zshrc` *before* the `source ~/.local/bin/afx.sh` line:

```bash
autoload -Uz compinit && compinit
```

Already using xmarks? The first time any `afx` command runs, it imports
`~/.xmarks/sessions.jsonl` into `~/.afx/sessions.jsonl` (a one-time copy,
not a move) if `~/.afx` doesn't exist yet — so starred sessions and
history carry over, and xmarks keeps working independently of afx from
then on.

## Usage

```bash
afx star [hash] [note...]   # star/un-star (toggle). Inside a session, plain
                      # `afx star` stars it, no hash needed. Outside one,
                      # `afx star <hash>` targets any session by its
                      # `afx list` HASH; a bare `afx star` guesses the
                      # newest session for the current dir instead.
                      # Starring an already-starred session un-stars it
                      # (and clears its note). [note...] is optional and,
                      # when given, always overwrites whatever description
                      # (auto or previous) was showing; it's cleared on
                      # un-star.
afx go [hash]         # cd there and resume the session (any session's
                      # HASH from `afx list`, starred or not)
afx list [-l|--long] [-s|--starred] [-r|--reverse] [-d|--dir] [-n N] [pattern]
                      # every session, oldest to newest (latest at the bottom);
                      # last 20 by default. -s limits to starred sessions;
                      # -d limits to sessions run from the current dir;
                      # a pattern filters by substring (any of these lift
                      # the cap); -n N overrides the count shown either way.
                      # -l is a git-log-style paragraph view (full hash,
                      # dir, untruncated summary), newest session first,
                      # instead of the oneline table. -r reverses
                      # whichever of those is the default order
afx status            # is this session/dir starred? (inside a session: `! afx status`)
afx rm <hash>         # permanently delete a session's row (asks for
                      # confirmation first). Unlike un-starring via
                      # `afx star`, the row is gone from `afx list` for good.
afx find [-n N] [-r] <pattern>  # search every session's actual transcript --
                      # not just `afx list`'s summary/note/detail -- for a real
                      # user prompt matching pattern. For "I know I asked
                      # this somewhere, which session was it?" One row
                      # per matching session (earliest match, oldest
                      # first, uncapped by default, same HASH `afx go`
                      # takes, starred rows marked the same way as
                      # `afx list`); a session with more than one matching
                      # message shows "(+N more)". -n caps the count, -r
                      # reverses the order. Two passes under the hood: a
                      # raw grep across every transcript file to shortlist
                      # candidates cheaply, then a jq parse of just those
                      # to match against clean prompt text instead of raw
                      # JSON bytes (so a hit inside a tool-call payload or
                      # assistant reply doesn't count).
afx jobs [-n N] [-r] [pattern]  # list background jobs (Bash calls run with
                      # run_in_background: true) across every session,
                      # oldest first -- for "I kicked this off last night,
                      # which session was it in?" without needing to
                      # remember any keyword. One row per job (a session
                      # can start several); same HASH/star conventions as
                      # `afx list`/`afx find`. A pattern filters by
                      # substring against the command. Needs the
                      # PostToolUse hook (below) -- it's what populates
                      # the job list in the first place.
afx push [hash] [--project <id>] [--allow-secret <finding-id>]...
                      # push a Claude Code session to artifax.dev, for
                      # sharing/collaboration/reproducibility (see
                      # artifax.dev's PLAN-SESSIONS.md), then also syncs
                      # this project's local memory -- Claude's own
                      # auto-memory files under this dir's memory/,
                      # filtered to type: project/reference only (a
                      # user/feedback entry describes the working
                      # relationship with one specific person, not a fact
                      # about the project, and never leaves this machine).
                      # Needs $ARTIFAX_API_TOKEN (a personal access token
                      # with the sessions:write scope -- see the
                      # artifax-publish skill for how to create one --
                      # plus projects:write unless --project is given,
                      # plus memory:write if there's local memory to sync).
                      # --project is optional: omit it (and
                      # $ARTIFAX_PROJECT_ID) and the first push creates a
                      # project of one, remembered in
                      # ~/.afx/session-projects.json by session id, so
                      # later pushes of the same session -- just
                      # `afx push <hash>` -- land back in that same
                      # project rather than a fresh one each time. Runs a
                      # client-side secret scan first and refuses to push
                      # outright on any high-confidence finding -- fix the
                      # transcript, or re-run with
                      # --allow-secret <finding-id> (printed by the
                      # refusal) for each finding you've reviewed and want
                      # to push anyway. Then aliases every occurrence of
                      # the project's parent directory, hostname, and OS
                      # username to `<project>`/`<host-1>`/`<user>`, and
                      # truncates oversized tool output, before any of it
                      # leaves the machine. Only Claude Code sessions are
                      # supported right now -- Codex support is a
                      # documented follow-up, not a silent gap.
                      # `$ARTIFAX_API_URL` overrides the API host (default
                      # `https://artifax.dev`).
afx pull <project-id-or-hash> [session-id-prefix] [--into <dir>]
                      # the inverse of push: pull a session back down from
                      # artifax.dev and make it resumable here, then also
                      # writes the project's memory (if the token has
                      # memory:read) into this dir's own local memory/, so
                      # a teammate pulling on a fresh machine gets the same
                      # accumulated project context available to their own
                      # future sessions. Needs $ARTIFAX_API_TOKEN with the
                      # sessions:read scope.
                      # The first argument takes either a real artifax
                      # project id, or the exact same local HASH `afx push
                      # <hash>` used -- resolved server-side to the project
                      # it lives in, so push and pull can share one value:
                      # `afx push 2f4afa` then, elsewhere, `afx pull 2f4afa`.
                      # session-id-prefix is a prefix of the *artifax*
                      # session id (the one `afx push`'s own "pushed: <id>"
                      # line prints), not a local `afx list` HASH -- omit
                      # it when the project has exactly one session,
                      # `afx pull` lists the candidates when there's more
                      # than one to choose from. `--into <dir>` picks
                      # where it lands (default $PWD); every path aliased
                      # to `<project>` at push time gets rewritten to that
                      # real directory -- the original pusher's actual
                      # path was never uploaded in the first place, so
                      # this is the puller's own choice, not a
                      # restoration. Registers the directory in
                      # `.claude.json` so `claude --resume` can actually
                      # find it and adds an `afx go`-able row to
                      # `~/.afx/sessions.jsonl` if the session isn't
                      # already tracked locally. Only `claude_code`
                      # sessions with a resumable local session id can be
                      # pulled right now.
```

The best way to star a session is from *inside* it:

```
! afx star the one where we designed the pact schema
```

Shells spawned by Claude Code export `CLAUDE_CODE_SESSION_ID`, so this stars
the exact session — no guessing, no hash needed. Run outside a session,
`afx star <hash>` targets any session directly by its `afx list` HASH; a
bare `afx star` falls back to the most recent session for the current
directory, across all tools and accounts. The `[note...]` is optional — if
you skip it, `afx list` falls back to the session's auto-generated
summary/detail once one exists (see below), so a session never needs a
manual description to show up meaningfully.

All state lives in one file, `~/.afx/sessions.jsonl` (one JSON object
per line, one per session, override with `$AFX_SESSIONS`). Starring
a session with `afx star` doesn't create a separate record — it just sets
`starred`/`note` on that session's existing row, alongside the
`date`/`reason`/`summary`/`detail` fields the hooks already track (see
below). If a session's transcript is gone, `afx go` still cd's to the
directory and warns.

## Session journal: auto-summaries on exit (and before)

`make install-hook` registers a `SessionEnd` hook and a `UserPromptSubmit`
hook in every `~/.claude*` settings.json (each backed up to `.bak` first).
When a Claude Code session ends, the SessionEnd hook updates that
session's row with the real outcome: `reason`, an auto-generated
`summary`, and a longer `detail` — by default it asks haiku via
`claude -p` for both in one call: `summary` is ≤12 words for the
`afx list` table columns, `detail` is a 2-4 sentence commit-message-style
paragraph (what was done, key decisions, outcome) shown in `afx list -l`'s
per-session view (a few seconds, a fraction of a cent per session).
Override the model with `AFX_SUMMARY_MODEL` (any `--model` value
`claude -p` accepts) or set `AFX_AUTOSUMMARY=first` to skip the LLM
entirely and use the session's first user message as `summary` (`detail`
stays unset in that case). Starred sessions keep their `name`/`note`
untouched — this only ever updates `date`/`reason`/`summary`/`detail`.

The UserPromptSubmit hook writes an earlier, cheaper version of that same
update the moment the *first* prompt is sent — no LLM call, just that
prompt's own text (truncated) as the summary, with `reason` set to
`in_progress`. This exists for sessions that never reach a clean exit —
an SSH connection dropping partway through, say — which would otherwise
vanish entirely; the first prompt is usually the best one-line summary of
the session's intent anyway. If SessionEnd does fire afterward, it
overwrites `reason`/`summary` with the real outcome as usual — never two
rows for one session. Later prompts in the same session are a no-op for
this hook (it exits as soon as it sees a row already exists).

Browse everything with `afx list` (oldest to newest, latest at the
bottom; last 20 by default) or `afx list <pattern>` to filter by
substring, uncapped. `-n <N>` overrides the count shown either way —
`afx list -n 5` for just the last 5, `afx list -s -n 3` for the 3 most
recent starred sessions. Every row gets a HASH column (the first 6
characters of its session id) that `afx go <hash>` resumes directly — so
a session never needs an `afx star` at all to be one command away — and
starred rows get a `*` beside their hash. `afx list -s`/`--starred`
narrows the same listing to just starred sessions. `afx list -d`/`--dir`
narrows it to sessions whose directory matches `$PWD` exactly — for "what
have I run from here?" after `cd`-ing somewhere. The default view is a
`git log --oneline`-style table: it hides ACCOUNT, shows just the dir's
basename, shortens SUMMARY to keep things narrow (preferring the
manual note over the auto-summary when a session has one), and trails
with an AGE column (`3h`, `2d`, falling back to `Jul 20` or `Jul 20
2025` past a week — kubectl's `AGE` convention) instead of a full
timestamp, plus a PROMPTS column: how many real user prompts that
session had. `afx list -l`/`--long` is `git log`-style instead — one
paragraph block per session, newest first (like real `git log`, the
reverse of the oneline table's oldest-first order), with the full
session id, account, full path, the exact `Date:`, and the note if set,
else the longer LLM-generated `detail`, else the short `summary`, wrapped
like a commit body. `-r`/`--reverse` flips whichever of those is the
default order for the view in use — `afx list -r` puts the newest
session at the top of the table, `afx list -l -r` matches real
`git log --reverse` and puts the oldest session first. Like git, both
views color the hash (and mark) and page through `$PAGER`/`less` when
run at a terminal — plain, unpaged text otherwise (piping to a file or
another command), and `NO_COLOR=1` turns colors off. Colors are drawn
from ORNL's brand palette and come in a `dark` variant (default, for a
dark terminal background) and a `light` one; set `AFX_PALETTE=light` in
the environment, or add the same line to `~/.afx/settings` (a small
shell file sourced automatically, if present), to switch. Want an exact
shade instead of one of the two built-ins? Set `AFX_HASH_COLOR` the same
way, to `#RRGGBB`, `RRGGBB`, or `R,G,B` — it overrides just the hash
color, regardless of `AFX_PALETTE`. True 24-bit color is only used when
`$COLORTERM` is `truecolor`/`24bit`; otherwise every color (built-in or
custom) is rendered as the nearest of xterm's standard 256 colors, which
basically every terminal claiming 256-color support handles correctly.
`make uninstall-hook` removes all three hooks.

The SessionEnd hook itself always returns in well under a second: it
writes the heuristic summary synchronously, then — if an LLM summary is
wanted — launches a fully detached background job (`afx-summarize-async`,
via `setsid`) that asks the LLM and patches the row in place once it's
ready. This matters because SessionEnd hooks get killed if they run too
long; a stalled or failed LLM call just leaves the heuristic summary in
place — the hook itself never waits on it.

## Background job tracking

`make install-hook` also registers a `PostToolUse` hook, matched to just
the `Bash` tool so it's a no-op for every other tool call. It fires after
every Bash call and, when that call was made with `run_in_background:
true`, appends a row (`date`, `session_id`, `dir`, `command`) to
`~/.afx/jobs.jsonl` (override with `$AFX_JOBS`) — a foreground command is
never logged. This is for "I kicked something off last night across four
or five sessions, which one was it?": browse the log with `afx jobs`
(see Usage above), which resumes into the right session the same way
`afx list`/`afx find` do — no need to remember any wording, since the
hook already recorded it as it happened. Like the SessionEnd hook, this
always returns immediately (PostToolUse fires after the tool result is
already back with Claude, so there's nothing to block).

## Multiple accounts and tools

Each row records which tool it belongs to (`claude` or `codex`) and the
home dir its session lives in (`CLAUDE_CONFIG_DIR` / `CODEX_HOME`, e.g.
`~/.claude-personal` vs `~/.claude-work`). `afx go` dispatches accordingly —
`CLAUDE_CONFIG_DIR=... claude --resume` or `CODEX_HOME=... codex resume` —
so sessions from every account and both tools share one file, and
`afx list` shows an ACCOUNT column for each (plus an AGENT column, but
only when starred sessions from both `claude` and `codex` actually
coexist — otherwise it's dropped as a repeated no-op value).

When saving from inside a Claude Code session, the session's own id and
config dir are used (Codex doesn't export a session id to child shells, so
there's no Codex equivalent). When guessing from a plain shell, `afx star`
searches every existing `~/.claude*` and `~/.codex*` home and takes the
newest session for the current dir, whichever tool it came from. Codex has
no per-project session layout, so its side of the search scans recent
rollout files for a matching `cwd`. Restrict or reorder candidates with
`AFX_CONFIG_DIRS` / `AFX_CODEX_HOMES` (colon-separated).
