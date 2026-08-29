# afx — a CLI for coding-agent sessions (Claude Code and Codex), and the
# client for artifax.dev.
# Source from .bashrc:  source ~/.local/bin/afx.sh
#
# A fork of xmarks (github.com/whbrewer/xmarks), rebranded and rebuilt as
# artifax.dev's own CLI. xmarks' single-letter commands (xs/xg/xl/...)
# become one dispatcher, `afx`, with two-word subcommands:
#
#   afx star [hash] [note...]   star/un-star (toggle). Inside a session,
#                          plain `afx star` stars it, no hash needed.
#                          Outside one, `afx star <hash>` targets any
#                          session by its `afx list` HASH; a bare
#                          `afx star` guesses the newest session for
#                          $PWD instead. Starring an already-starred
#                          session un-stars it (and clears its note).
#                          [note...] overwrites the auto summary/detail;
#                          cleared on un-star.
#   afx go [hash]          cd to its dir and resume the session (any
#                          session's HASH from `afx list`, starred or not)
#   afx list [-l|--long] [-s|--starred] [-r|--reverse] [-a|--all] [-d|--dir]
#            [-n N] [pattern]
#                          every session, oldest to newest (latest at
#                          the bottom); each row's HASH is an `afx go`
#                          shortcut, starred rows get a * beside it.
#                          Last 20 by default ($AFX_LIST_LIMIT overrides
#                          that default); sessions run from a directory
#                          literally named "tmp" are hidden by default
#                          too (one-shot/background runs tend to land
#                          there); -s limits to starred sessions,
#                          -d limits to sessions run from $PWD, a
#                          pattern filters (any of these lift the cap);
#                          -a shows every session, uncapped, tmp dirs
#                          included; -n N
#                          overrides the count shown either way; -l
#                          shows a git-log-style paragraph per session
#                          instead of the oneline table, newest session
#                          first (like real `git log`, unlike the
#                          oneline table above); -r reverses whichever
#                          of those is the default order
#   afx status             is this session / directory starred?
#   afx rm <hash>          permanently delete a session's row (unlike
#                          un-starring via `afx star`, this drops it from
#                          `afx list` entirely -- summary/detail/note gone
#                          for good). Asks for confirmation first.
#   afx find [-n N] [-r] <pattern>
#                          search every session's actual transcript --
#                          not just `afx list`'s summary/note/detail --
#                          for a real user prompt matching pattern.
#   afx jobs [-n N] [-r] [pattern]
#                          list background jobs (Bash calls made with
#                          run_in_background: true) across every session,
#                          oldest first.
#   afx push [hash] [--project <id>] [--allow-secret <finding-id>]...
#                          push a Claude Code session to artifax.dev
#                          (artifax.dev's PLAN-SESSIONS.md), then also sync
#                          this project's local memory (Claude's own
#                          auto-memory files under this dir's memory/,
#                          filtered to type: project/reference only -- see
#                          _afx_push_memory). Needs $ARTIFAX_API_TOKEN (a
#                          personal access token with the sessions:write
#                          scope -- see the artifax-publish skill for how to
#                          create one -- plus projects:write unless
#                          --project is given, plus memory:write if there's
#                          local memory to sync).
#                          --project is optional: omit it (and
#                          $ARTIFAX_PROJECT_ID) and afx first checks whether
#                          this exact session, or this directory/repo, has
#                          already been pushed before (~/.afx/session-
#                          projects.json and ~/.afx/dir-projects.json,
#                          respectively) and reuses that project if so;
#                          only a directory/repo that's never been pushed
#                          gets a fresh project of one. Either way the
#                          project used is recorded under both maps, so a
#                          later `afx push [hash]` -- from the same session
#                          or a brand-new one in the same repo -- lands back
#                          in that same project without needing --project
#                          again. Runs a
#                          client-side secret scan first and refuses to push
#                          outright on any high-confidence finding (fix the
#                          transcript, or re-run with
#                          --allow-secret <finding-id> for each finding
#                          you've reviewed and want to push anyway), then
#                          aliases every occurrence of the project's parent
#                          directory, hostname, and OS username to
#                          `<project>`/`<host-1>`/`<user>`, and truncates
#                          oversized tool output, before any of it leaves
#                          the machine. Only Claude Code sessions are
#                          supported right now. $ARTIFAX_API_URL overrides
#                          the API host (default https://artifax.dev).
#   afx pull <project-id-or-hash> [session-id-prefix] [--into <dir>]
#                          the inverse of push: pull a session back down
#                          from artifax.dev and make it resumable here,
#                          then also writes the project's memory (if the
#                          token has memory:read; skipped otherwise) into
#                          this dir's own local memory/, so a teammate
#                          pulling on a fresh machine gets the same
#                          accumulated project context available to their
#                          own future sessions, not just the raw history.
#                          Needs $ARTIFAX_API_TOKEN with the sessions:read
#                          scope. The first argument takes either a real
#                          artifax project id, OR the exact same local HASH
#                          `afx push <hash>` used -- resolved server-side
#                          via GET /api/v1/sessions to the project it lives
#                          in, so push and pull can share one identifier.
#                          session-id-prefix is a prefix of the
#                          *artifax* session id (the one `afx push`'s own
#                          "pushed: <id>" line prints), not a local
#                          `afx list` HASH -- omit it when the project has
#                          exactly one session, `afx pull` lists the
#                          candidates when there's more than one to choose
#                          from. `--into <dir>` picks where it lands
#                          (default $PWD).
#
# All state lives in one file, ~/.afx/sessions.jsonl (one JSON object
# per line, one per session, override with $AFX_SESSIONS):
#   {date, session_id, dir, home, tool, reason, summary, detail, starred, note}
# date/reason/summary are auto-tracked by the hooks: the UserPromptSubmit
# hook seeds a row right after the first prompt (reason "in_progress",
# summary = that prompt's own text, no LLM call), so a session that dies
# without a clean exit -- a dropped SSH connection, say -- still shows up
# instead of vanishing entirely; SessionEnd overwrites reason/summary with
# the real outcome (a heuristic first message, patched in place with an
# LLM summary shortly after, unless AFX_AUTOSUMMARY=first). That same
# LLM pass also writes detail, a longer commit-message-style paragraph
# (what was done, key decisions, outcome) -- summary stays a short
# one-liner for the table, detail is only ever shown in `afx list -l`'s
# per-session view, since it doesn't fit a table row.
# starred/note are only ever touched by `afx star`, which toggles starred
# and clears note on un-star. note is optional free text that, when
# given, always wins over detail/summary for display; when absent,
# listings fall back to detail, then the short auto summary -- so a
# session never needs a manual description to be meaningfully listed.
# tool is "claude" or "codex" (default "claude") and home is the
# CLAUDE_CONFIG_DIR / CODEX_HOME the session lives in, so sessions from
# different accounts and tools coexist and resume correctly.
#
# Candidate homes when guessing: $AFX_CONFIG_DIRS (colon-separated)
# else every existing ~/.claude*; $AFX_CODEX_HOMES else $CODEX_HOME
# else every existing ~/.codex*. $AFX_SUMMARY_MODEL picks the model the
# SessionEnd hook's background job uses for summary/detail (default
# haiku, the cheapest/fastest tier); see hooks/afx-summarize-async.

# Resolved inside each function (not at source time): Claude Code's shell
# snapshots restore functions but not unexported variables, so a top-level
# assignment would be lost in `!` shells inside sessions.

# One-time setup: creates ~/.afx if it doesn't exist, and -- the first
# time afx ever runs on a machine that already has xmarks state -- imports
# ~/.xmarks/sessions.jsonl into ~/.afx/sessions.jsonl so switching from
# xmarks to afx doesn't lose starred sessions or history. Copies rather
# than moves: xmarks keeps working independently of afx from then on, the
# two just diverge. Cheap and idempotent -- safe to call from every
# command; once ~/.afx/sessions.jsonl exists this is just a stat check.
_afx_migrate () {
  local dir="$HOME/.afx"
  mkdir -p "$dir"
  if [ ! -e "$dir/sessions.jsonl" ] && [ -f "$HOME/.xmarks/sessions.jsonl" ]; then
    cp "$HOME/.xmarks/sessions.jsonl" "$dir/sessions.jsonl"
  fi
}

_afx_claude_dirs () {
  if [ -n "${AFX_CONFIG_DIRS:-}" ]; then
    printf '%s\n' "$AFX_CONFIG_DIRS" | tr ':' '\n'
  else
    local d
    for d in "$HOME"/.claude "$HOME"/.claude-*; do
      [ -d "$d/projects" ] && printf '%s\n' "$d"
    done
  fi
}

_afx_codex_homes () {
  if [ -n "${AFX_CODEX_HOMES:-}" ]; then
    printf '%s\n' "$AFX_CODEX_HOMES" | tr ':' '\n'
  elif [ -n "${CODEX_HOME:-}" ]; then
    printf '%s\n' "$CODEX_HOME"
  else
    local d
    for d in "$HOME"/.codex "$HOME"/.codex-*; do
      [ -d "$d/sessions" ] && printf '%s\n' "$d"
    done
  fi
}

_afx_proj_dir () {
  # Claude Code stores sessions under <config_dir>/projects/<munged cwd>,
  # where every non-alphanumeric character of the cwd becomes '-'.
  printf '%s/projects/%s' "$1" "$(printf '%s' "$2" | sed 's/[^A-Za-z0-9]/-/g')"
}

_afx_codex_latest () {
  # Newest codex session for cwd $2 under home $1. Codex files are date-
  # organized with no per-project dir, so scan newest-first (path order is
  # chronological) and match session_meta.cwd on line one.
  local f
  while IFS= read -r f; do
    if [ "$(head -1 "$f" | jq -r '.payload.cwd // empty' 2>/dev/null)" = "$2" ]; then
      printf '%s\n' "$f"; return 0
    fi
  done < <(find "$1/sessions" -name '*.jsonl' 2>/dev/null | sort -r | head -200)
  return 1
}

_afx_is_codex () {
  # Codex rollout files start with a session_meta record.
  head -c 200 "$1" 2>/dev/null | grep -q '"type":"session_meta"'
}

_afx_account () {
  # Short display name for a home dir: ~/.claude-work → work, ~/.codex → default.
  local b; b="$(basename "$1")"
  case "$b" in
    .claude|.codex) echo default ;;
    .claude-*) echo "${b#.claude-}" ;;
    .codex-*) echo "${b#.codex-}" ;;
    *) echo "$b" ;;
  esac
}

_afx_truncate () {
  # Truncate $1 to at most $2 chars total, ellipsis included, so the
  # displayed width never exceeds $2.
  local s="$1" max="$2"
  if [ "${#s}" -gt "$max" ]; then
    printf '%s...' "${s:0:$((max - 3))}"
  else
    printf '%s' "$s"
  fi
}

_afx_date_fmt () {
  # $1 = a stored "YYYY-MM-DD HH:MM" date, $2 = output format. GNU `date -d`
  # parses that directly; BSD/macOS date has no -d and needs the input
  # format spelled out via -j -f instead.
  date -d "$1" "$2" 2>/dev/null || date -j -f '%Y-%m-%d %H:%M' "$1" "$2" 2>/dev/null
}

_afx_relative_date () {
  # $1 = a stored "YYYY-MM-DD HH:MM" date, for `afx list`'s compact table
  # (`afx list -l` keeps the full timestamp). Falls back to the raw string
  # if it can't be parsed (e.g. a hand-edited row).
  local then_epoch now_epoch diff
  then_epoch="$(_afx_date_fmt "$1" +%s)" || { printf '%s' "$1"; return; }
  now_epoch="$(date +%s)"
  diff=$((now_epoch - then_epoch))
  if [ "$diff" -lt 60 ]; then
    printf 'now'
  elif [ "$diff" -lt 3600 ]; then
    printf '%dm' "$((diff / 60))"
  elif [ "$diff" -lt 86400 ]; then
    printf '%dh' "$((diff / 3600))"
  elif [ "$diff" -lt 604800 ]; then
    printf '%dd' "$((diff / 86400))"
  elif [ "$(_afx_date_fmt "$1" +%Y)" = "$(date +%Y)" ]; then
    _afx_date_fmt "$1" '+%b %d'
  else
    _afx_date_fmt "$1" '+%b %d %Y'
  fi
}

_afx_page () {
  # Page like git does: only when stdout is the terminal itself, so
  # `afx list | grep foo` or `afx list > file` still gets plain, unpaged
  # text. Honors $PAGER; falls back to `less -FRX` (-F: quit if it fits
  # one screen, -R: show color codes as color instead of garbage, -X:
  # don't clear the screen on exit) so scrollback isn't wiped; falls back
  # further to `cat` if neither is available. A bare `PAGER=less` (e.g.
  # set by /etc/profile on some systems) gets -FRX added too -- otherwise
  # it pages even single-screen output, unlike our own less fallback.
  if [ -t 1 ]; then
    if [ "${PAGER:-}" = less ]; then
      less -FRX
    elif [ -n "${PAGER:-}" ]; then
      $PAGER
    elif command -v less >/dev/null 2>&1; then
      less -FRX
    else
      cat
    fi
  else
    cat
  fi
}

_afx_display_dir () {
  # $1 = raw dir, $2 = "1" for the full ~-shortened path (`afx list -l`);
  # else just the basename, so default listings stay narrow.
  local dir="$1"
  case "$dir" in
    "$HOME") dir="~" ;;
    "$HOME"/*) dir="~${dir#"$HOME"}" ;;
  esac
  if [ "$2" != 1 ] && [ "$dir" != "~" ] && [ "$dir" != "/" ]; then
    dir="$(basename "$dir")"
  fi
  printf '%s' "$dir"
}

_afx_nearest_idx () {
  # Index into levels $2.. closest to value $1 (integer-only).
  local v="$1"; shift
  local best=0 bestd=100000 i=0 d lvl
  for lvl in "$@"; do
    d=$(( lvl - v )); [ "$d" -lt 0 ] && d=$(( -d ))
    [ "$d" -lt "$bestd" ] && { bestd=$d; best=$i; }
    i=$(( i + 1 ))
  done
  printf '%d' "$best"
}

_afx_256_nearest () {
  # Nearest xterm 256-color index for RGB $1 $2 $3 -- checks both the
  # 6x6x6 color cube (16-231) and the grayscale ramp (232-255) and picks
  # whichever lands closer, same approach terminal-color libraries use.
  # Integer-only so it needs no bc/python dependency.
  local r="$1" g="$2" b="$3" levels="0 95 135 175 215 255"
  local ri gi bi lv
  ri="$(_afx_nearest_idx "$r" $levels)"
  gi="$(_afx_nearest_idx "$g" $levels)"
  bi="$(_afx_nearest_idx "$b" $levels)"
  lv=($levels)
  local cr=${lv[ri]} cg=${lv[gi]} cb=${lv[bi]}
  local cube_index=$(( 16 + 36*ri + 6*gi + bi ))
  local cube_dist=$(( (r-cr)*(r-cr) + (g-cg)*(g-cg) + (b-cb)*(b-cb) ))

  local avg=$(( (r+g+b)/3 )) grays="" i
  for i in $(seq 0 23); do grays="$grays $(( 8 + 10*i ))"; done
  local gi2; gi2="$(_afx_nearest_idx "$avg" $grays)"
  local gray_index=$(( 232 + gi2 ))
  local gval=$(( 8 + 10*gi2 ))
  local gray_dist=$(( (r-gval)*(r-gval) + (g-gval)*(g-gval) + (b-gval)*(b-gval) ))

  if [ "$cube_dist" -le "$gray_dist" ]; then printf '%d' "$cube_index"
  else printf '%d' "$gray_index"; fi
}

_afx_fg () {
  # $1 $2 $3 = R G B. 24-bit truecolor only when $COLORTERM says the
  # terminal actually renders it -- tmux and a plain "xterm-256color"
  # TERM (still the common default, even on terminals that could do
  # better) routinely don't, and either drop \033[38;2;...m entirely or
  # render it as the wrong color, which is why AFX_PALETTE could look
  # like it wasn't doing anything. The 256-color fallback is understood
  # by effectively everything that claims 256-color support to begin with.
  case "${COLORTERM:-}" in
    truecolor|24bit) printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3" ;;
    *)                printf '\033[38;5;%dm' "$(_afx_256_nearest "$1" "$2" "$3")" ;;
  esac
}

_afx_parse_color () {
  # $1 as "#RRGGBB" / "RRGGBB" (hex) or "R,G,B" (decimal) -> prints
  # "R G B"; fails (no output) on anything else, including unset/empty,
  # so callers can `if rgb="$(_afx_parse_color "$x")"` to fall through to
  # a default.
  local c="${1//[[:space:]]/}"
  case "$c" in
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      c="${c#'#'}"; printf '%d %d %d' "0x${c:0:2}" "0x${c:2:2}" "0x${c:4:2}" ;;
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      printf '%d %d %d' "0x${c:0:2}" "0x${c:2:2}" "0x${c:4:2}" ;;
    [0-9]*,[0-9]*,[0-9]*)
      printf '%s' "${c//,/ }" ;;
    *) return 1 ;;
  esac
}

_afx_first_msg () {
  # First real user message of a session file ($1), one line, trimmed.
  if _afx_is_codex "$1"; then
    jq -r 'select(.type == "event_msg" and .payload.type == "user_message")
           | .payload.message' "$1" 2>/dev/null
  else
    jq -r 'select(.type == "user" and .isSidechain != true)
           | .message.content
           | if type == "string" then .
             else (map(select(.type == "text") | .text) | join(" ")) end' \
        "$1" 2>/dev/null
  fi | sed 's/^[[:space:]]*//' | grep -v -e '^<' -e '^$' \
     | head -1 | tr '\t' ' ' | cut -c1-70
}

_afx_lock () {
  # Advisory lock so concurrent afx star/rm calls don't race on
  # sessions.jsonl. `mkdir` is atomic on every POSIX filesystem, unlike
  # `flock` -- which macOS doesn't ship and has no equivalent for by
  # default -- so this one primitive works on both. Waits up to ~5s for a
  # live holder; past that, assumes the holder died without cleaning up
  # (e.g. a killed shell) and reclaims the lock rather than deadlocking
  # every call after it.
  local lockdir="$1.lock.d" i=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
      rmdir "$lockdir" 2>/dev/null
      mkdir "$lockdir" 2>/dev/null
      break
    fi
    sleep 0.1
  done
}

_afx_unlock () {
  rmdir "$1.lock.d" 2>/dev/null
}

afx_star () {
  _afx_migrate
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  # A hash prefix naming an existing session, given outside a session, is
  # consumed as the target; every other argument (in-session always, or
  # anything left after a hash) is note text.
  local session_id="${CLAUDE_CODE_SESSION_ID:-}"
  local arg1="${1:-}"
  local hash_arg=""
  if [ -z "$session_id" ] && [ -n "$arg1" ] && [ -s "$SESSIONS_FILE" ] \
       && jq -e --arg h "$arg1" 'select(.session_id | startswith($h))' "$SESSIONS_FILE" >/dev/null 2>&1; then
    hash_arg="$arg1"; shift
  fi
  local note="$*"
  local sid file home tool markdir="$PWD"
  if [ -n "$session_id" ]; then
    # Running inside a Claude Code session (e.g. via `! afx star`): no
    # guessing, no hash needed -- always this exact session.
    # (Codex exports no session id to child shells, so no codex equivalent.)
    tool=claude
    sid="$session_id"
    home="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    file="$(_afx_proj_dir "$home" "$PWD")/$sid.jsonl"
    # The shell may have cd'd away from the session's start dir; find the
    # session by id and mark its real cwd, so `afx go` lands in the right
    # place.
    [ -f "$file" ] \
      || file="$(find "$home/projects" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
    if [ -f "$file" ]; then
      markdir="$(grep -o '"cwd":"[^"]*"' "$file" | head -1 | cut -d'"' -f4)"
      markdir="${markdir:-$PWD}"
    fi
  elif [ -n "$hash_arg" ]; then
    # Target an existing session directly by its `afx list` HASH, wherever
    # it lives -- no cwd guessing needed.
    local line; line="$(jq -c --arg h "$hash_arg" 'select(.session_id | startswith($h))' "$SESSIONS_FILE" | tail -1)"
    sid="$(jq -r '.session_id' <<<"$line")"
    markdir="$(jq -r '.dir' <<<"$line")"
    home="$(jq -r '.home' <<<"$line")"
    tool="$(jq -r '.tool // "claude"' <<<"$line")"
  else
    # Newest session for this dir across all claude config dirs + codex homes.
    local d f files=()
    while IFS= read -r d; do
      files+=( "$(_afx_proj_dir "$d" "$PWD")"/*.jsonl )
    done < <(_afx_claude_dirs)
    while IFS= read -r d; do
      f="$(_afx_codex_latest "$d" "$PWD")" && files+=( "$f" )
    done < <(_afx_codex_homes)
    file="$(ls -t "${files[@]}" 2>/dev/null | head -1)"
    [ -n "$file" ] || { echo "afx star: no claude/codex sessions found for $PWD" >&2; return 1; }
    if _afx_is_codex "$file"; then
      tool=codex
      home="${file%/sessions/*}"
      sid="$(head -1 "$file" | jq -r '.payload.id')"
    else
      tool=claude
      home="${file%/projects/*}"
      sid="$(basename "$file" .jsonl)"
    fi
  fi
  # Preserve date/reason/summary/detail from any row the hooks already
  # wrote for this session -- only starred/note/dir/home/tool change here.
  # A brand-new row (no hook has run yet, or a codex session the hooks
  # never touch) falls back to the session's first message as its summary.
  local existing date reason summary detail starred existing_note
  existing="$([ -f "$SESSIONS_FILE" ] && jq -c --arg s "$sid" 'select(.session_id == $s)' "$SESSIONS_FILE" | tail -1)"
  if [ -n "$existing" ]; then
    date="$(jq -r '.date' <<<"$existing")"
    reason="$(jq -r '.reason // empty' <<<"$existing")"
    summary="$(jq -r '.summary // empty' <<<"$existing")"
    detail="$(jq -r '.detail // empty' <<<"$existing")"
    starred="$(jq -r '.starred // false' <<<"$existing")"
    existing_note="$(jq -r '.note // empty' <<<"$existing")"
  else
    date="$(date '+%F %H:%M')"
    reason=""
    summary="$(_afx_first_msg "$file")"
    detail=""
    starred=false
    existing_note=""
  fi
  # afx star toggles: starring an already-starred session un-stars it
  # instead of needing a separate command; un-starring always clears the
  # note (matching the old `xd`'s behavior), while (re-)starring keeps
  # whatever note was already there if none was typed just now.
  local new_starred=true
  [ "$starred" = true ] && new_starred=false
  if [ "$new_starred" = true ]; then
    [ -n "$note" ] || note="$existing_note"
  else
    note=""
  fi
  _afx_lock "$SESSIONS_FILE"
  {
    [ -f "$SESSIONS_FILE" ] && jq -c --arg s "$sid" 'select(.session_id != $s)' "$SESSIONS_FILE"
    jq -nc --arg date "$date" --arg sid "$sid" --arg dir "$markdir" \
      --arg home "$home" --arg tool "$tool" --arg reason "$reason" --arg summary "$summary" \
      --arg detail "$detail" --argjson starred "$new_starred" --arg note "$note" \
      '{date: $date, session_id: $sid, dir: $dir, home: $home, tool: $tool,
        reason: (if $reason == "" then null else $reason end),
        summary: (if $summary == "" then null else $summary end),
        detail: (if $detail == "" then null else $detail end),
        starred: $starred,
        note: (if $note == "" then null else $note end)}'
  } > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
  _afx_unlock "$SESSIONS_FILE"
  if [ "$new_starred" = true ]; then
    echo "starred ${sid:0:6} → $sid  [$tool/$(_afx_account "$home")]  ($markdir)"
  else
    echo "unstarred ${sid:0:6} (session kept — see afx list)"
  fi
}

afx_go () {
  _afx_migrate
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  [ -s "$SESSIONS_FILE" ] || { echo "afx go: no sessions yet" >&2; return 1; }
  local hash="${1:-}" line
  if [ -z "$hash" ]; then
    if command -v fzf >/dev/null 2>&1; then
      line="$(jq -r 'select(.starred == true) | [(.session_id[0:6]), (.note // .summary // "-"), (.summary // "-")] | @tsv' "$SESSIONS_FILE" \
        | fzf --delimiter='\t' --with-nth=1,2,3)" || return 1
      hash="$(printf '%s' "$line" | cut -f1)"
    else
      afx_list -s; printf 'usage: afx go <hash>\n' >&2; return 1
    fi
  fi
  local dir sid home tool
  # Any session's HASH resumes it, starred or not.
  line="$(jq -c --arg h "$hash" 'select(.session_id | startswith($h))' "$SESSIONS_FILE" | tail -1)"
  [ -n "$line" ] || { echo "afx go: no such session: $hash" >&2; return 1; }
  dir="$(jq -r '.dir' <<<"$line")"
  sid="$(jq -r '.session_id' <<<"$line")"
  home="$(jq -r '.home' <<<"$line")"
  tool="$(jq -r '.tool // "claude"' <<<"$line")"
  [ -d "$dir" ] || { echo "afx go: directory gone: $dir" >&2; return 1; }
  cd "$dir" || return 1
  if [ "$tool" = codex ]; then
    home="${home:-$HOME/.codex}"
    if [ -z "$(find "$home/sessions" -name "*$sid.jsonl" -print -quit 2>/dev/null)" ]; then
      echo "afx go: codex session $sid no longer exists in $home — you're in $dir" >&2
      return 1
    fi
    CODEX_HOME="$home" codex resume "$sid"
  else
    home="${home:-$HOME/.claude}"
    if [ ! -f "$(_afx_proj_dir "$home" "$dir")/$sid.jsonl" ]; then
      echo "afx go: session $sid no longer exists in $home — you're in $dir" >&2
      return 1
    fi
    CLAUDE_CONFIG_DIR="$home" claude --resume "$sid"
  fi
}

afx_list () {
  _afx_migrate
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  local long=0 starred_only=0 reverse=0 limit="${AFX_LIST_LIMIT:-20}" limit_set=0 show_all=0 dir_only=0
  while :; do
    case "${1:-}" in
      -l|--long|--full) long=1; shift ;;
      -s|--starred) starred_only=1; shift ;;
      -r|--reverse) reverse=1; shift ;;
      -a|--all) show_all=1; shift ;;
      -d|--dir) dir_only=1; shift ;;
      -n) limit="${2:-}"
          case "$limit" in
            ''|*[!0-9]*) echo "afx list: -n requires a number" >&2; return 1 ;;
          esac
          limit_set=1; shift 2 ;;
      *) break ;;
    esac
  done
  [ -s "$SESSIONS_FILE" ] || {
    echo "afx list: no sessions yet — install the SessionEnd hook: make install-hook" >&2
    return 1
  }
  # Color (like git) only for an interactive terminal, and never if the
  # user opted out with $NO_COLOR -- piping to a file or another command
  # gets plain text either way. Every colored field is wrapped the same
  # way on every row (even "-"), so the constant escape-code overhead
  # cancels out in column -t's width math instead of skewing it.
  local c_hash="" c_mark="" c_dim="" c_warn="" c_reset="" c_invert=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    # Palette: $AFX_PALETTE / $AFX_HASH_COLOR if already set in the
    # environment win; otherwise ~/.afx/settings may set them (a small
    # sourced shell file, e.g. lines reading `AFX_PALETTE=light` or
    # `AFX_HASH_COLOR=#55BAB4`); otherwise "dark". AFX_HASH_COLOR takes
    # any "#RRGGBB"/"RRGGBB"/"R,G,B" color and overrides the hash color
    # regardless of AFX_PALETTE, for picking an exact shade rather than
    # one of the two built-in palettes. The built-ins are ORNL brand
    # secondary/accent hues, chosen per palette for contrast against a
    # dark vs. light terminal background.
    [ -n "${AFX_PALETTE:-}${AFX_HASH_COLOR:-}" ] || { [ -f "$HOME/.afx/settings" ] && . "$HOME/.afx/settings"; }
    local hash_rgb
    if hash_rgb="$(_afx_parse_color "${AFX_HASH_COLOR:-}")"; then
      c_hash="$(_afx_fg $hash_rgb)"
    elif [ "${AFX_PALETTE:-dark}" = light ]; then
      c_hash="$(_afx_fg 45 105 161)"   # Infinity
    else
      c_hash="$(_afx_fg 167 251 196)"  # Mist
    fi
    if [ "${AFX_PALETTE:-dark}" = light ]; then
      c_mark="$(_afx_fg 166 33 144)"   # Plasma
    else
      c_mark="$(_afx_fg 45 105 161)"   # Infinity
    fi
    c_dim=$'\033[2m'
    c_warn="$(_afx_fg 235 93 42)"      # Spark, same in both palettes
    c_reset=$'\033[0m'
    c_invert=$'\033[7m'  # swapped fg/bg, for the table header row
  fi
  # -s (or a pattern) is already a small, deliberate subset -- no cap,
  # unless -n overrides it explicitly. Otherwise last 20 (or -n's count),
  # oldest to newest (latest at the bottom). -a lifts the cap outright.
  local pattern="${1:-}"
  local use_cap=1
  [ "$limit_set" = 0 ] && { [ "$starred_only" = 1 ] || [ -n "$pattern" ] || [ "$show_all" = 1 ] || [ "$dir_only" = 1 ]; } && use_cap=0
  local filtered
  # Sessions run from a dir literally named "tmp" (one-shot/background runs,
  # e.g. `claude -p`, tend to land there) are noise in the default view --
  # filtered out below unless -a is given as the escape hatch to see them.
  filtered="$(
    { if [ "$starred_only" = 1 ]; then jq -c 'select(.starred == true)' "$SESSIONS_FILE"
      else cat "$SESSIONS_FILE"; fi; } \
    | { [ "$show_all" = 1 ] && cat || jq -c 'select((.dir | split("/") | last) != "tmp")'; } \
    | { [ "$dir_only" = 1 ] && jq -c --arg d "$PWD" 'select(.dir == $d)' || cat; } \
    | tac \
    | { [ -n "$pattern" ] && grep -i -- "$pattern" || cat; }
  )"
  # Total (pre-cap) count, so the compact view can tell the user how much
  # more is available beyond the default 20-row window.
  local total=0
  [ -n "$filtered" ] && total="$(printf '%s\n' "$filtered" | wc -l | tr -d ' ')"
  local rows
  rows="$(printf '%s\n' "$filtered" | { [ "$use_cap" = 1 ] && head -n "$limit" || cat; } | tac)"
  # AGENT is only worth a column/line when the listed sessions actually mix
  # tools; with everything on claude (the common case) it's a no-op value.
  local show_tool=0
  [ -n "$rows" ] && [ "$(jq -sc 'any(.[]; .tool == "codex")' <<<"$rows")" = true ] && show_tool=1
  # Same no-op-value reasoning for ACCOUNT: only worth a column when the
  # listed sessions actually span more than one home dir. _afx_account's
  # mapping isn't expressible in jq, so resolve each row's effective home
  # (mirroring the tool-based default below) and count distinct accounts.
  local show_account=0
  if [ -n "$rows" ]; then
    local accounts
    accounts="$(printf '%s\n' "$rows" | jq -r '[(.home // ""), (.tool // "claude")] | join("")' \
      | while IFS=$'\x1f' read -r h t; do
          [ -n "$h" ] || { [ "$t" = codex ] && h="$HOME/.codex" || h="$HOME/.claude"; }
          _afx_account "$h"
        done | sort -u | wc -l | tr -d ' ')"
    [ "$accounts" -gt 1 ] && show_account=1
  fi
  # \x1f (not a literal tab) joins these fields: summary/note/reason can be
  # null, and bash's `read` collapses adjacent tab delimiters (tab counts
  # as IFS whitespace regardless of what IFS is set to) which would
  # silently shift every field after an empty one.
  local IFS=$'\x1f' date sid dir home reason summary detail note starred tool
  # $rows is oldest-to-newest. Default: compact table keeps that order
  # (newest at the bottom); -l flips it, matching real `git log`'s
  # newest-first convention. -r/--reverse flips whichever is the default
  # for the view in use (so `afx list -l -r` matches `git log --reverse`).
  local flip=0
  [ "$long" != "$reverse" ] && flip=1
  if [ "$long" = 1 ]; then
    local first=1
    { printf '%s\n' "$rows" | { [ "$flip" = 1 ] && tac || cat; } \
    | jq -r '[.date, .session_id, .dir, .home, (.reason // ""), (.summary // ""), (.detail // ""),
              (.note // ""), (.starred // false), (.tool // "")] | join("")' \
    | while read -r date sid dir home reason summary detail note starred tool; do
        tool="${tool:-claude}"
        [ -n "$home" ] || { [ "$tool" = codex ] && home="$HOME/.codex" || home="$HOME/.claude"; }
        dir="$(_afx_display_dir "$dir" 1)"
        [ "$first" = 1 ] || printf '\n'
        first=0
        printf '%ssession %s%s\n' "$c_hash" "$sid" "$c_reset"
        [ "$starred" = true ] && printf 'Starred: %syes%s\n' "$c_mark" "$c_reset"
        [ "$tool" = codex ] && printf 'Tool:    %s%s%s\n' "$c_dim" "$tool" "$c_reset"
        [ "$reason" = in_progress ] && printf 'Status:  %sin progress%s\n' "$c_warn" "$c_reset"
        printf 'Account: %s\n' "$(_afx_account "$home")"
        printf 'Dir:     %s\n' "$dir"
        printf 'Date:    %s%s%s\n' "$c_dim" "$date" "$c_reset"
        printf '\n'
        printf '%s\n' "${note:-${detail:-${summary:--}}}" | fold -s -w 76 | sed 's/^/    /'
      done
    } | _afx_page
  else
    # AGE is right-justified by hand below: `column -t -R` is a GNU
    # (util-linux) extension, not available in BSD/macOS column.
    local agewidth=3 w
    while IFS= read -r w; do
      [ "${#w}" -gt "$agewidth" ] && agewidth="${#w}"
    done <<<"$(printf '%s\n' "$rows" | jq -r '.date' | while IFS= read -r w; do _afx_relative_date "$w"; printf '\n'; done)"
    { # The header's HASH cell must carry the same escape-code byte count
      # as a data row's colored hash field (6 chars + mark, wrapped in
      # c_hash/c_mark/c_reset) -- otherwise BSD/macOS `column -t`, which
      # (unlike GNU's) can't tell ANSI codes are invisible, measures the
      # header's plain "HASH" as much shorter than the data rows and pads
      # every column after it far too wide.
      local hash_header="HASH"
      [ -n "$c_hash" ] && hash_header="${c_hash}$(printf '%-6s' HASH)${c_reset}${c_mark} ${c_reset}"
      { if [ "$show_tool" = 1 ] && [ "$show_account" = 1 ]; then
          printf '%s\tAGENT\tACCOUNT\tDIR\tSUMMARY\tPROMPTS\t%*s\n' "$hash_header" "$agewidth" AGE
        elif [ "$show_tool" = 1 ]; then
          printf '%s\tAGENT\tDIR\tSUMMARY\tPROMPTS\t%*s\n' "$hash_header" "$agewidth" AGE
        elif [ "$show_account" = 1 ]; then
          printf '%s\tACCOUNT\tDIR\tSUMMARY\tPROMPTS\t%*s\n' "$hash_header" "$agewidth" AGE
        else
          printf '%s\tDIR\tSUMMARY\tPROMPTS\t%*s\n' "$hash_header" "$agewidth" AGE
        fi
        local maxlen="${AFX_NOTE_MAXLEN:-52}"
        printf '%s\n' "$rows" | { [ "$flip" = 1 ] && tac || cat; } \
        | jq -r '[.date, .session_id, .dir, .home, (.reason // ""), (.summary // ""), (.note // ""),
                  (.starred // false), (.tool // ""), (.prompts // "")] | join("")' \
        | while read -r date sid dir home reason summary note starred tool prompts; do
            dir="$(_afx_display_dir "$dir" 0)"
            date="$(printf '%*s' "$agewidth" "$(_afx_relative_date "$date")")"
            local shown="${note:-$summary}"; shown="${shown:--}"
            prompts="${prompts:--}"
            # Starred rows get a * beside the hash, in the same color the
            # mark carries elsewhere, instead of a separate column. The
            # mark segment (star or space) is always emitted, colored
            # either way, so every row carries the same escape-code byte
            # count -- otherwise column -t's raw-byte width math (it
            # doesn't know ANSI codes aren't visible) misjudges the HASH
            # column whenever starred and unstarred rows are mixed.
            local mark=" "
            [ "$starred" = true ] && mark="*"
            local hashfield="${c_hash}${sid:0:6}${c_reset}${c_mark}${mark}${c_reset}"
            [ -n "$home" ] || { [ "${tool:-claude}" = codex ] && home="$HOME/.codex" || home="$HOME/.claude"; }
            local account; account="$(_afx_account "$home")"
            if [ "$show_tool" = 1 ] && [ "$show_account" = 1 ]; then
              printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$hashfield" "${tool:-claude}" "$account" "$dir" "$(_afx_truncate "$shown" "$maxlen")" "$prompts" "$date"
            elif [ "$show_tool" = 1 ]; then
              printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$hashfield" "${tool:-claude}" "$dir" "$(_afx_truncate "$shown" "$maxlen")" "$prompts" "$date"
            elif [ "$show_account" = 1 ]; then
              printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$hashfield" "$account" "$dir" "$(_afx_truncate "$shown" "$maxlen")" "$prompts" "$date"
            else
              printf '%s\t%s\t%s\t%s\t%s\n' \
                "$hashfield" "$dir" "$(_afx_truncate "$shown" "$maxlen")" "$prompts" "$date"
            fi
          done
      # -c 1000: column -t silently drops trailing columns that don't fit
      # the terminal width instead of wrapping.
      } | column -t -s"$(printf '\t')" -c 1000 \
      | { # Invert the header row (fg/bg swapped) after column -t has
          # already aligned everything -- done here, on the finished
          # text, so it can't disturb the byte-count-matching column -t
          # needs to align the HASH column on BSD/macOS (see above).
          # $c_reset ends the row's own color runs partway through, so
          # each one is followed by a fresh $c_invert to keep the swap
          # going until the row's real end.
          if [ -n "$c_invert" ]; then
            local header_line
            IFS= read -r header_line
            header_line="${header_line//"$c_reset"/$c_reset$c_invert}"
            printf '%s%s%s\n' "$c_invert" "$header_line" "$c_reset"
          fi
          cat
        }
      # Cue that the default 20-row cap is hiding older sessions -- easy
      # to forget it's there, so spell out the count and how to see more.
      if [ "$use_cap" = 1 ] && [ "$total" -gt "$limit" ]; then
        printf '%sshowing last %s of %s sessions -- afx list -a, afx list -n %s, or afx list <pattern> for more%s\n' \
          "$c_dim" "$limit" "$total" "$total" "$c_reset"
      fi
    } | _afx_page
  fi
}

# afx find <pattern>: search every session's actual transcript -- not just
# the `afx list` summary/note/detail -- for a real user prompt matching
# pattern. For "I know I asked this somewhere, which session was it?" when
# the auto-summary doesn't mention it. Two passes: a cheap raw-byte grep
# across every transcript file to shortlist candidates, then a jq parse
# of just those candidates to pull out real user-prompt text (skipping
# subagent/sidechain turns, the same schema _afx_first_msg already uses)
# and confirm the match against clean text instead of raw JSON bytes.
afx_find () {
  _afx_migrate
  local reverse=0 limit="" limit_set=0
  while :; do
    case "${1:-}" in
      -r|--reverse) reverse=1; shift ;;
      -n) limit="${2:-}"
          case "$limit" in
            ''|*[!0-9]*) echo "afx find: -n requires a number" >&2; return 1 ;;
          esac
          limit_set=1; shift 2 ;;
      --) shift; break ;;
      -*) echo "afx find: unknown option: $1" >&2; return 1 ;;
      *) break ;;
    esac
  done
  local pattern="${1:-}"
  [ -n "$pattern" ] || { echo "usage: afx find [-n N] [-r] <pattern>" >&2; return 1; }

  local c_hash="" c_mark="" c_dim="" c_reset="" c_invert=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_hash=$'\033[33m'
    c_mark=$'\033[36m'
    c_dim=$'\033[2m'
    c_reset=$'\033[0m'
    c_invert=$'\033[7m'
  fi

  # Every transcript file across every claude/codex home, tagged with the
  # home dir and tool it came from -- needed later for the AGENT column
  # and to know which schema to parse it with.
  local file_index
  file_index="$(
    { _afx_claude_dirs | while IFS= read -r d; do
        find "$d/projects" -name '*.jsonl' 2>/dev/null \
          | while IFS= read -r f; do printf '%s\x1f%s\x1f%s\n' "$d" claude "$f"; done
      done
      _afx_codex_homes | while IFS= read -r d; do
        find "$d/sessions" -name '*.jsonl' 2>/dev/null \
          | while IFS= read -r f; do printf '%s\x1f%s\x1f%s\n' "$d" codex "$f"; done
      done
    }
  )"
  [ -n "$file_index" ] || { echo "afx find: no session transcripts found" >&2; return 1; }

  # Pass 1: cheap raw-byte grep across every file, just to shortlist which
  # ones are even worth a jq parse -- most won't match at all. No xargs
  # -d (a GNU-only flag) so this stays portable to BSD/macOS grep.
  local candidates
  candidates="$(
    printf '%s\n' "$file_index" | while IFS=$'\x1f' read -r home tool f; do
      grep -qil -- "$pattern" "$f" 2>/dev/null && printf '%s\x1f%s\x1f%s\n' "$home" "$tool" "$f"
    done
  )"
  [ -n "$candidates" ] || { echo "afx find: no match for '$pattern'" >&2; return 1; }

  # Pass 2: parse just the candidates and pull out real user-prompt text.
  # Newlines are flattened so each hit is exactly one physical output
  # line -- raw prompt text, unlike `afx list`'s metadata fields, routinely
  # contains them.
  local hits
  hits="$(
    printf '%s\n' "$candidates" | while IFS=$'\x1f' read -r home tool f; do
      if [ "$tool" = codex ]; then
        local sid cwd
        sid="$(head -1 "$f" | jq -r '.payload.session_id // empty' 2>/dev/null)"
        cwd="$(head -1 "$f" | jq -r '.payload.cwd // empty' 2>/dev/null)"
        jq -r --arg sid "$sid" --arg cwd "$cwd" --arg home "$home" --arg tool "$tool" '
          select(.type == "event_msg" and .payload.type == "user_message")
          | [.timestamp, $sid, $cwd, $home, $tool,
             ((.payload.message // "") | gsub("[\n\r\t]"; " "))]
          | join("")' "$f" 2>/dev/null
      else
        jq -r --arg home "$home" --arg tool "$tool" '
          select(.type == "user" and .isSidechain != true)
          | [.timestamp, .sessionId, .cwd, $home, $tool,
             ((.message.content
               | if type == "string" then .
                 else (map(select(.type == "text") | .text) | join(" ")) end)
              | gsub("[\n\r\t]"; " "))]
          | join("")' "$f" 2>/dev/null
      fi
    done | grep -i -- "$pattern"
  )"
  [ -n "$hits" ] || { echo "afx find: no match for '$pattern'" >&2; return 1; }

  # One row per session: earliest matching message (truncated for
  # display) plus how many messages in that session matched -- a
  # follow-up rephrasing counts too, instead of spamming one row each.
  local grouped
  grouped="$(
    printf '%s\n' "$hits" | jq -R -s -r '
      split("\n") | map(select(length > 0) | split(""))
      | map({ts:.[0], sid:.[1], cwd:.[2], home:.[3], tool:.[4], text:.[5]})
      | group_by(.sid)
      | map(sort_by(.ts) as $g | $g[0] + {count: ($g | length)})
      | sort_by(.ts)
      | .[] | [.ts, .sid, .cwd, .home, .tool, (.count | tostring), .text] | join("")
    '
  )"

  local show_tool=0
  [ "$(printf '%s\n' "$hits" | cut -d $'\x1f' -f5 | sort -u | wc -l | tr -d ' ')" -gt 1 ] && show_tool=1

  # Starred sessions get the same * marker `afx list` gives them.
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  local starred_sids=""
  [ -s "$SESSIONS_FILE" ] && starred_sids="$(jq -r 'select(.starred == true) | .session_id' "$SESSIONS_FILE" 2>/dev/null)"

  local total; total="$(printf '%s\n' "$grouped" | wc -l | tr -d ' ')"
  local rows="$grouped"
  [ "$limit_set" = 1 ] && rows="$(printf '%s\n' "$grouped" | tail -n "$limit")"
  [ "$reverse" = 1 ] && rows="$(printf '%s\n' "$rows" | tac)"

  local agewidth=3 w
  while IFS= read -r w; do
    [ "${#w}" -gt "$agewidth" ] && agewidth="${#w}"
  done <<<"$(printf '%s\n' "$rows" | cut -d $'\x1f' -f1 | while IFS= read -r ts; do _afx_relative_date "${ts:0:10} ${ts:11:5}"; printf '\n'; done)"

  {
    local hash_header="HASH"
    [ -n "$c_hash" ] && hash_header="${c_hash}$(printf '%-6s' HASH)${c_reset}${c_mark} ${c_reset}"
    local maxlen="${AFX_NOTE_MAXLEN:-52}"
    { if [ "$show_tool" = 1 ]; then
        printf '%s\tAGENT\tDIR\tMATCH\t%*s\n' "$hash_header" "$agewidth" AGE
      else
        printf '%s\tDIR\tMATCH\t%*s\n' "$hash_header" "$agewidth" AGE
      fi
      printf '%s\n' "$rows" | while IFS=$'\x1f' read -r ts sid cwd home tool count text; do
        local dir; dir="$(_afx_display_dir "$cwd" 0)"
        local age; age="$(printf '%*s' "$agewidth" "$(_afx_relative_date "${ts:0:10} ${ts:11:5}")")"
        local shown="$text"
        [ "$count" -gt 1 ] && shown="$shown (+$((count - 1)) more)"
        local mark=" "
        printf '%s\n' "$starred_sids" | grep -qxF -- "$sid" && mark="*"
        local hashfield="${c_hash}${sid:0:6}${c_reset}${c_mark}${mark}${c_reset}"
        if [ "$show_tool" = 1 ]; then
          printf '%s\t%s\t%s\t%s\t%s\n' \
            "$hashfield" "$tool" "$dir" "$(_afx_truncate "$shown" "$maxlen")" "$age"
        else
          printf '%s\t%s\t%s\t%s\n' \
            "$hashfield" "$dir" "$(_afx_truncate "$shown" "$maxlen")" "$age"
        fi
      done
    } | column -t -s"$(printf '\t')" -c 1000 \
    | { if [ -n "$c_invert" ]; then
          local header_line
          IFS= read -r header_line
          header_line="${header_line//"$c_reset"/$c_reset$c_invert}"
          printf '%s%s%s\n' "$c_invert" "$header_line" "$c_reset"
        fi
        cat
      }
    if [ "$limit_set" = 1 ] && [ "$total" -gt "$limit" ]; then
      printf '%sshowing last %s of %s matching sessions -- afx find -n %s '"'"'%s'"'"' for more%s\n' \
        "$c_dim" "$limit" "$total" "$total" "$pattern" "$c_reset"
    fi
  } | _afx_page
}

# afx jobs [-n N] [-r] [pattern]: list background jobs (Bash calls made
# with run_in_background: true) across every session, oldest first -- for
# "I kicked this off last night, which session was it in?" without
# needing to remember any keyword. One row per job (a session can start
# several). Requires the PostToolUse hook (make install-hook) -- it's
# what populates jobs.jsonl in the first place.
afx_jobs () {
  _afx_migrate
  local reverse=0 limit="${AFX_JOBS_LIMIT:-20}" limit_set=0
  while :; do
    case "${1:-}" in
      -r|--reverse) reverse=1; shift ;;
      -n) limit="${2:-}"
          case "$limit" in
            ''|*[!0-9]*) echo "afx jobs: -n requires a number" >&2; return 1 ;;
          esac
          limit_set=1; shift 2 ;;
      --) shift; break ;;
      -*) echo "afx jobs: unknown option: $1" >&2; return 1 ;;
      *) break ;;
    esac
  done
  local pattern="${1:-}"

  local jobs="${AFX_JOBS:-$HOME/.afx/jobs.jsonl}"
  [ -s "$jobs" ] || {
    echo "afx jobs: no background jobs recorded yet -- install the PostToolUse hook: make install-hook" >&2
    return 1
  }

  local c_hash="" c_mark="" c_dim="" c_reset="" c_invert=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_hash=$'\033[33m'
    c_mark=$'\033[36m'
    c_dim=$'\033[2m'
    c_reset=$'\033[0m'
    c_invert=$'\033[7m'
  fi

  local use_cap=1
  [ "$limit_set" = 0 ] && [ -n "$pattern" ] && use_cap=0
  local filtered
  filtered="$(cat "$jobs" | tac | { [ -n "$pattern" ] && grep -i -- "$pattern" || cat; })"
  local total=0
  [ -n "$filtered" ] && total="$(printf '%s\n' "$filtered" | wc -l | tr -d ' ')"
  local rows
  rows="$(printf '%s\n' "$filtered" | { [ "$use_cap" = 1 ] && head -n "$limit" || cat; } | tac)"
  [ -n "$rows" ] || { echo "afx jobs: no match for '$pattern'" >&2; return 1; }
  [ "$reverse" = 1 ] && rows="$(printf '%s\n' "$rows" | tac)"

  # Starred sessions get the same * marker `afx list` gives them.
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  local starred_sids=""
  [ -s "$SESSIONS_FILE" ] && starred_sids="$(jq -r 'select(.starred == true) | .session_id' "$SESSIONS_FILE" 2>/dev/null)"

  local agewidth=3 w
  while IFS= read -r w; do
    [ "${#w}" -gt "$agewidth" ] && agewidth="${#w}"
  done <<<"$(printf '%s\n' "$rows" | jq -r '.date' | while IFS= read -r w; do _afx_relative_date "$w"; printf '\n'; done)"

  {
    local hash_header="HASH"
    [ -n "$c_hash" ] && hash_header="${c_hash}$(printf '%-6s' HASH)${c_reset}${c_mark} ${c_reset}"
    local maxlen="${AFX_NOTE_MAXLEN:-52}"
    { printf '%s\tDIR\tCOMMAND\t%*s\n' "$hash_header" "$agewidth" AGE
      printf '%s\n' "$rows" \
      | jq -r '[.date, .session_id, .dir, (.command | gsub("[\n\r\t]"; " "))] | join("")' \
      | while IFS=$'\x1f' read -r date sid dir command; do
          dir="$(_afx_display_dir "$dir" 0)"
          local age; age="$(printf '%*s' "$agewidth" "$(_afx_relative_date "$date")")"
          local mark=" "
          printf '%s\n' "$starred_sids" | grep -qxF -- "$sid" && mark="*"
          local hashfield="${c_hash}${sid:0:6}${c_reset}${c_mark}${mark}${c_reset}"
          printf '%s\t%s\t%s\t%s\n' "$hashfield" "$dir" "$(_afx_truncate "$command" "$maxlen")" "$age"
        done
    } | column -t -s"$(printf '\t')" -c 1000 \
    | { if [ -n "$c_invert" ]; then
          local header_line
          IFS= read -r header_line
          header_line="${header_line//"$c_reset"/$c_reset$c_invert}"
          printf '%s%s%s\n' "$c_invert" "$header_line" "$c_reset"
        fi
        cat
      }
    if [ "$use_cap" = 1 ] && [ "$total" -gt "$limit" ]; then
      printf '%sshowing last %s of %s background jobs -- afx jobs -n %s for more%s\n' \
        "$c_dim" "$limit" "$total" "$total" "$c_reset"
    fi
  } | _afx_page
}

# afx status: is this session saved? Inside a Claude Code session
# (`! afx status`) checks that exact session; outside, shows any starred
# sessions for the current directory.
afx_status () {
  _afx_migrate
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  local hits
  local session_id="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -n "$session_id" ]; then
    hits="$(jq -r --arg s "$session_id" \
      'select(.session_id == $s and .starred == true) | "  " + .session_id[0:6] + "  (" + (.note // .summary // "-") + ")"' \
      "$SESSIONS_FILE" 2>/dev/null)"
    if [ -n "$hits" ]; then
      echo "this session is starred:"; printf '%s\n' "$hits"
    else
      echo "this session is NOT starred — star it with: afx star [note...]"
      return 1
    fi
  else
    hits="$(jq -r --arg d "$PWD" \
      'select(.dir == $d and .starred == true) | "  " + .session_id[0:6] + "  (" + (.note // .summary // "-") + ")"' \
      "$SESSIONS_FILE" 2>/dev/null)"
    if [ -n "$hits" ]; then
      echo "starred sessions for $PWD:"; printf '%s\n' "$hits"
    else
      echo "no starred sessions for $PWD"
      return 1
    fi
  fi
}

# afx rm: permanently delete a session's row by its `afx list` HASH --
# unlike un-starring (which keeps the row, just drops the star), this
# removes it from sessions.jsonl entirely, so it's gone from `afx list`
# for good. Confirms first since there's no undo.
afx_rm () {
  _afx_migrate
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  local arg1="${1:-}"
  [ -n "$arg1" ] || { echo "usage: afx rm <hash>" >&2; return 1; }
  [ -s "$SESSIONS_FILE" ] || { echo "afx rm: no sessions yet" >&2; return 1; }
  local line; line="$(jq -c --arg h "$arg1" 'select(.session_id | startswith($h))' "$SESSIONS_FILE" | tail -1)"
  [ -n "$line" ] || { echo "afx rm: no such session: $arg1" >&2; return 1; }
  local sid desc
  sid="$(jq -r '.session_id' <<<"$line")"
  # note/summary, not detail: matches whatever `afx list`'s compact table
  # (where this hash came from) actually showed for this row. .detail is
  # the long commit-message-style writeup meant for `afx list -l`'s
  # paragraph view, not a one-line confirmation prompt.
  desc="$(_afx_truncate "$(jq -r '.note // .summary // "-"' <<<"$line")" "${AFX_NOTE_MAXLEN:-52}")"
  local reply
  # `read -p` prints the prompt in bash, but in zsh `-p` means "read from
  # the coprocess" instead -- printing the prompt separately works the
  # same way in both.
  printf 'delete session %s (%s)? [y/N] ' "${sid:0:6}" "$desc"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "afx rm: aborted"; return 1 ;;
  esac
  _afx_lock "$SESSIONS_FILE"
  jq -c --arg s "$sid" 'select(.session_id != $s)' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" \
    && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
  _afx_unlock "$SESSIONS_FILE"
  echo "deleted ${sid:0:6} (was: \"$desc\")"
}

# --- afx push: push a session to artifax.dev (artifax.dev PLAN-SESSIONS.md §19/§20) ---
#
# Requires $ARTIFAX_API_TOKEN (a personal access token with the
# sessions:write scope -- see the artifax-publish skill for how to create
# one) and a target project: --project <id>, or $ARTIFAX_PROJECT_ID as a
# default. $ARTIFAX_API_URL overrides the API host (default
# https://artifax.dev), for the same Cloudflare-edge-reset fallback the
# artifax-publish skill documents.
#
# Runs gate 1 (PLAN-SESSIONS.md §20.2) before a single byte leaves the
# machine: a secret scan that refuses the push outright on any
# high-confidence finding (override one at a time with
# --allow-secret <finding-id>, printed by the scan itself), then
# path/hostname/username aliasing, then truncation of oversized tool
# output. Only Claude Code sessions are supported right now -- Codex's
# rollout format hasn't been verified against the server-side parser
# (apps/web/lib/session-transcript.ts in the artifax.dev repo), so a
# codex session is refused with a clear message rather than silently
# mis-parsed.

# The regex rule set (gitleaks-style, not exhaustive) lives in
# ~/.afx/secret-rules.json so it can be improved without reinstalling afx
# (PLAN-SESSIONS.md §20.2). Seeded once with a real starter set; never
# overwritten after that, so local edits/additions persist.
_afx_seed_secret_rules () {
  local f="$HOME/.afx/secret-rules.json"
  [ -f "$f" ] && return 0
  mkdir -p "$HOME/.afx"
  cat > "$f" <<'JSON'
{
  "version": "1",
  "rules": [
    { "id": "aws_access_key_id", "pattern": "AKIA[0-9A-Z]{16}", "ci": false, "description": "AWS access key ID" },
    { "id": "aws_secret_access_key", "pattern": "aws_secret_access_key[^A-Za-z0-9]{0,40}[A-Za-z0-9/+=]{40}", "ci": true, "description": "AWS secret access key" },
    { "id": "github_token", "pattern": "gh[pousr]_[A-Za-z0-9]{36,}", "ci": false, "description": "GitHub personal access / OAuth / app token" },
    { "id": "slack_token", "pattern": "xox[baprs]-[0-9A-Za-z-]{10,}", "ci": false, "description": "Slack token" },
    { "id": "google_api_key", "pattern": "AIza[0-9A-Za-z_-]{35}", "ci": false, "description": "Google API key" },
    { "id": "private_key_header", "pattern": "-----BEGIN (RSA |EC |OPENSSH |DSA |ENCRYPTED |)PRIVATE KEY-----", "ci": false, "description": "Private key material" },
    { "id": "generic_secret_assignment", "pattern": "(password|passwd|secret|api_key|apikey|access_token)[^A-Za-z0-9]{0,3}[:=][^A-Za-z0-9]{0,3}[\"'][^\"']{8,}[\"']", "ci": true, "description": "A password/secret/token-shaped literal assigned inline" },
    { "id": "anthropic_api_key", "pattern": "sk-ant-[A-Za-z0-9_-]{20,}", "ci": false, "description": "Anthropic API key" },
    { "id": "openai_api_key", "pattern": "sk-[A-Za-z0-9]{20,}T3BlbkFJ[A-Za-z0-9]{20,}", "ci": false, "description": "OpenAI API key" }
  ]
}
JSON
}

# Prints one "<rule_id>#<line_number>: <description>" per high-confidence
# hit not already covered by an --allow-secret id ($2...). Empty output +
# exit 0 means clean.
_afx_scan_secrets () {
  local file="$1"; shift
  local -a allowed=("$@")
  _afx_seed_secret_rules
  local rules="$HOME/.afx/secret-rules.json"
  local found=0 n i=0 rule_id pattern ci
  n="$(jq -r '.rules | length' "$rules")"
  while [ "$i" -lt "$n" ]; do
    rule_id="$(jq -r ".rules[$i].id" "$rules")"
    pattern="$(jq -r ".rules[$i].pattern" "$rules")"
    ci="$(jq -r ".rules[$i].ci" "$rules")"
    local grep_opts=(-nE)
    [ "$ci" = true ] && grep_opts+=(-i)
    while IFS=: read -r lineno _rest; do
      [ -n "$lineno" ] || continue
      local finding_id="${rule_id}#${lineno}" is_allowed=0 a
      for a in "${allowed[@]:-}"; do
        [ "$a" = "$finding_id" ] && is_allowed=1 && break
      done
      if [ "$is_allowed" = 1 ]; then
        echo "afx push: secret finding $finding_id allowed via --allow-secret" >&2
      else
        echo "$finding_id: $(jq -r ".rules[$i].description" "$rules")"
        found=1
      fi
    done < <(grep "${grep_opts[@]}" "$pattern" "$file" 2>/dev/null)
    i=$((i + 1))
  done
  return $found
}

_afx_sed_escape () {
  # Escapes a literal string for use as a sed pattern with '|' as delimiter.
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

# Replaces every occurrence of the project's parent dir / hostname /
# OS username with <project>/<host-1>/<user> throughout $1, writing the
# result to $2 -- applied to the whole file as text (not just structured
# cwd fields), since §20.2 requires message content and tool output to be
# aliased too, not just metadata. Order matters: the longest, most
# specific token (the path prefix) goes first, generic ones last, so a
# short username that happens to be a substring of the hostname (or vice
# versa) can't clobber part of the other's replacement.
_afx_alias_paths () {
  local in="$1" out="$2" project_parent="$3" hostname="$4" osuser="$5"
  local esc_parent esc_host esc_user
  esc_parent="$(_afx_sed_escape "$project_parent")"
  esc_host="$(_afx_sed_escape "$hostname")"
  esc_user="$(_afx_sed_escape "$osuser")"
  sed -e "s|${esc_parent}|<project>|g" "$in" \
    | { [ -n "$hostname" ] && sed -e "s|${esc_host}|<host-1>|g" || cat; } \
    | { [ -n "$osuser" ] && sed -e "s|${esc_user}|<user>|g" || cat; } \
    > "$out"
}

# Truncates any tool stdout/stderr or tool_result content over $3 chars
# (default 8000, override with $AFX_PUSH_EXCERPT_CHARS) to a head+tail
# excerpt with a marker -- §20.2's "size reduction" step, run after
# aliasing so a truncated blob can't split an alias mid-token.
_afx_shrink_outputs () {
  local in="$1" out="$2" max="${3:-8000}"
  jq -c --argjson max "$max" '
    def shrink:
      if type == "string" and (length > $max) then
        (.[0:($max/2|floor)] + "\n…[truncated \((length - $max) | tostring) chars by afx push gate 1]…\n" + .[-($max/2|floor):])
      else . end;
    (if has("toolUseResult") and (.toolUseResult.stdout? != null) then .toolUseResult.stdout |= shrink else . end)
    | (if has("toolUseResult") and (.toolUseResult.stderr? != null) then .toolUseResult.stderr |= shrink else . end)
    | (if (.message.content? | type) == "array" then
        .message.content |= map(if .type == "tool_result" and (.content | type) == "string" then .content |= shrink else . end)
      else . end)
  ' "$in" > "$out"
}

# Remembers which artifax project a session was auto-created into, keyed by
# the Claude Code session id -- so re-pushing the same (grown) session
# without --project lands in the SAME project every time instead of
# scattering its revisions across a fresh project-of-one on every push.
# An explicit --project always overrides and re-records the mapping.
_afx_session_project_map_get () {
  local f="$HOME/.afx/session-projects.json"
  [ -f "$f" ] || return 0
  jq -r --arg s "$1" '.[$s] // empty' "$f" 2>/dev/null
}

_afx_session_project_map_set () {
  local f="$HOME/.afx/session-projects.json"
  mkdir -p "$HOME/.afx"
  [ -f "$f" ] || echo '{}' > "$f"
  _afx_lock "$f"
  jq --arg s "$1" --arg p "$2" '.[$s] = $p' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  _afx_unlock "$f"
}

# A repo's working tree root if $1 is inside one, else $1 itself -- so pushes
# from any subdirectory of the same repo (or from the repo root every time)
# share one directory-project mapping instead of one per exact cwd.
_afx_repo_key () {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$1"
}

# Same idea as the session-id map above, but keyed by _afx_repo_key instead
# of session id -- so a brand-new session pushed from a directory/repo that's
# already been pushed from before lands in that SAME project automatically,
# rather than `afx push` auto-creating a fresh project-of-one for every
# never-before-seen session. Checked only as a fallback after the session map
# (a session explicitly re-targeted to a different project via --project
# should keep going back there, not get overridden by the dir's default).
_afx_dir_project_map_get () {
  local f="$HOME/.afx/dir-projects.json"
  [ -f "$f" ] || return 0
  jq -r --arg d "$1" '.[$d] // empty' "$f" 2>/dev/null
}

_afx_dir_project_map_set () {
  local f="$HOME/.afx/dir-projects.json"
  mkdir -p "$HOME/.afx"
  [ -f "$f" ] || echo '{}' > "$f"
  _afx_lock "$f"
  jq --arg d "$1" --arg p "$2" '.[$d] = $p' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  _afx_unlock "$f"
}

# --- project memory: pushed alongside a session, pulled alongside a bundle ----------
#
# Reuses Claude Code's own local auto-memory files -- one markdown file per entry under
# <config_dir>/projects/<munged cwd>/memory/*.md, YAML frontmatter (name/description/
# metadata.type) then a body -- rather than a separate afx-owned store. Only
# metadata.type: project|reference is ever pushed: type: user|feedback describes the
# working relationship with one specific person, not a fact about the project, and
# never leaves this machine. Non-fatal on any failure here: a memory sync problem must
# never fail the session push/pull it rides alongside.

# Prints one JSON array (possibly empty, "[]") of {name,kind,description,body} built
# from every eligible *.md file in $2's memory dir. $1/$2 are the same ($home, $dir)
# pair _afx_proj_dir already takes.
_afx_memory_read_local () {
  local home="$1" dir="$2"
  local mem_dir; mem_dir="$(_afx_proj_dir "$home" "$dir")/memory"
  local entries="[]"
  [ -d "$mem_dir" ] || { printf '%s' "$entries"; return 0; }

  local f
  for f in "$mem_dir"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "MEMORY.md" ] && continue

    local fm_end; fm_end="$(awk '/^---$/{c++; if(c==2){print NR; exit}}' "$f")"
    [ -n "$fm_end" ] || continue # not well-formed frontmatter: skip silently, don't fail the push

    local head; head="$(sed -n "1,${fm_end}p" "$f")"
    local name kind description
    name="$(sed -n 's/^name:[[:space:]]*//p' <<<"$head" | head -1 | sed 's/^"\(.*\)"$/\1/')"
    kind="$(sed -n 's/^[[:space:]]*type:[[:space:]]*//p' <<<"$head" | head -1)"
    description="$(sed -n 's/^description:[[:space:]]*//p' <<<"$head" | head -1 | sed 's/^"\(.*\)"$/\1/')"
    [ "$kind" = "project" ] || [ "$kind" = "reference" ] || continue
    [ -n "$name" ] || continue

    local body_start=$((fm_end + 1))
    [ -z "$(sed -n "${body_start}p" "$f")" ] && body_start=$((body_start + 1)) # skip one leading blank line, if present
    local body_file; body_file="$(mktemp)"
    tail -n "+${body_start}" "$f" > "$body_file"

    entries="$(jq -n --argjson entries "$entries" --arg name "$name" --arg kind "$kind" --arg description "$description" --rawfile body "$body_file" \
      '$entries + [{name: $name, kind: $kind, description: $description, body: $body}]')"
    rm -f "$body_file"
  done
  printf '%s' "$entries"
}

# Pushes whatever _afx_memory_read_local finds for ($home, $dir) into project $2.
_afx_push_memory () {
  local api_url="$1" project_id="$2" home="$3" dir="$4"
  local entries; entries="$(_afx_memory_read_local "$home" "$dir")"
  local n; n="$(jq 'length' <<<"$entries")"
  [ "$n" -gt 0 ] || return 0

  echo "afx push: pushing $n memory entries..."
  local resp status
  resp="$(curl -sS -w '\n%{http_code}' -X POST "$api_url/api/v1/projects/$project_id/memory" \
    -H "Authorization: Bearer $ARTIFAX_API_TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --argjson entries "$entries" '{entries: $entries}')")"
  status="$(tail -1 <<<"$resp")"
  resp="$(sed '$d' <<<"$resp")"
  if [ "$status" = 200 ]; then
    echo "afx push: memory synced: $(jq -r '[.items[] | "\(.name):\(.status)"] | join(", ")' <<<"$resp")"
  else
    echo "afx push: memory push failed ($status): $resp -- session itself still pushed fine" >&2
  fi
}

# Writes every entry in $1 (a bundle response's .memory array, already fetched by the
# caller -- no separate request needed) into $3's local memory dir under $2, recreating
# each file's frontmatter and appending an index line to MEMORY.md if one isn't there
# already (never touches an existing index line, matching _afx_register_claude_project's
# own "never disturb what's already there" care).
_afx_pull_memory () {
  local bundle_resp="$1" home="$2" dir="$3" project_id="$4"
  local count; count="$(jq '.memory | length' <<<"$bundle_resp" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || return 0

  local mem_dir; mem_dir="$(_afx_proj_dir "$home" "$dir")/memory"
  mkdir -p "$mem_dir"
  local index_file="$mem_dir/MEMORY.md"
  [ -f "$index_file" ] || : > "$index_file"

  local i name description kind body modified
  for ((i = 0; i < count; i++)); do
    name="$(jq -r ".memory[$i].name" <<<"$bundle_resp")"
    kind="$(jq -r ".memory[$i].kind" <<<"$bundle_resp")"
    body="$(jq -r ".memory[$i].body" <<<"$bundle_resp")"
    modified="$(jq -r ".memory[$i].updated_at" <<<"$bundle_resp")"
    description="$(jq -r ".memory[$i].description" <<<"$bundle_resp")"
    local description_escaped="${description//\"/\\\"}"

    {
      printf -- '---\n'
      printf 'name: %s\n' "$name"
      printf 'description: "%s"\n' "$description_escaped"
      printf 'metadata: \n'
      printf '  node_type: memory\n'
      printf '  type: %s\n' "$kind"
      printf '  originSessionId: pulled-from-artifax-project-%s\n' "$project_id"
      printf '  modified: %s\n' "$modified"
      printf -- '---\n'
      printf '\n'
      printf '%s\n' "$body"
    } >"$mem_dir/$name.md"

    if ! grep -qF "($name.md)" "$index_file" 2>/dev/null; then
      printf -- '- [%s](%s.md) — %s\n' "$(tr '-' ' ' <<<"$name")" "$name" "$description" >>"$index_file"
    fi
  done
  echo "afx pull: pulled $count memory entries into $mem_dir"
}

afx_push () {
  local SESSIONS_FILE="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  local hash_arg="" project_id="${ARTIFAX_PROJECT_ID:-}" project_explicit=0
  local -a allow_secrets=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project_id="$2"; project_explicit=1; shift 2 ;;
      --allow-secret) allow_secrets+=("$2"); shift 2 ;;
      -*) echo "afx push: unknown option $1" >&2; return 1 ;;
      *) if [ -z "$hash_arg" ]; then hash_arg="$1"; shift; else echo "afx push: unexpected argument $1" >&2; return 1; fi ;;
    esac
  done
  [ -n "$project_id" ] && project_explicit=1

  [ -n "${ARTIFAX_API_TOKEN:-}" ] || { echo "afx push: \$ARTIFAX_API_TOKEN not set (needs the sessions:write scope, plus projects:write if you don't pass --project): see the artifax-publish skill" >&2; return 1; }
  local c
  for c in jq curl gzip sha256sum; do
    command -v "$c" >/dev/null 2>&1 || { echo "afx push: $c is required" >&2; return 1; }
  done

  local api_url="${ARTIFAX_API_URL:-https://artifax.dev}"
  local session_id="${CLAUDE_CODE_SESSION_ID:-}"
  local sid file home tool
  if [ -n "$session_id" ] && [ -z "$hash_arg" ]; then
    tool=claude; sid="$session_id"; home="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    file="$(_afx_proj_dir "$home" "$PWD")/$sid.jsonl"
    [ -f "$file" ] || file="$(find "$home/projects" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
  elif [ -n "$hash_arg" ]; then
    [ -s "$SESSIONS_FILE" ] || { echo "afx push: no sessions recorded yet" >&2; return 1; }
    local line; line="$(jq -c --arg h "$hash_arg" 'select(.session_id | startswith($h))' "$SESSIONS_FILE" | tail -1)"
    [ -n "$line" ] || { echo "afx push: no session matching hash $hash_arg" >&2; return 1; }
    sid="$(jq -r '.session_id' <<<"$line")"; home="$(jq -r '.home' <<<"$line")"; tool="$(jq -r '.tool // "claude"' <<<"$line")"
    file="$(_afx_proj_dir "$home" "$(jq -r '.dir' <<<"$line")")/$sid.jsonl"
  else
    echo "afx push: run \`! afx push\` inside a session, or pass a HASH from \`afx list\`" >&2; return 1
  fi
  [ "$tool" = claude ] || { echo "afx push: only Claude Code sessions are supported right now (this is $tool): codex support is a documented follow-up" >&2; return 1; }
  [ -f "$file" ] || { echo "afx push: transcript file not found: $file" >&2; return 1; }

  local cwd_dir; cwd_dir="$(grep -o '"cwd":"[^"]*"' "$file" | head -1 | cut -d'"' -f4)"
  [ -n "$cwd_dir" ] || cwd_dir="$PWD"
  local project_parent; project_parent="$(dirname "$cwd_dir")"
  local hostname_val; hostname_val="$(hostname 2>/dev/null || echo "")"
  local osuser_val; osuser_val="$(whoami 2>/dev/null || echo "")"
  local dir_key; dir_key="$(_afx_repo_key "$cwd_dir")"

  # Pulled up front (used both for auto-project naming below and the push
  # metadata later) rather than computed twice.
  local existing prompt_count end_reason summary detail
  existing="$([ -f "$SESSIONS_FILE" ] && jq -c --arg s "$sid" 'select(.session_id == $s)' "$SESSIONS_FILE" | tail -1)"
  prompt_count="$(jq -r '.prompts // empty' <<<"${existing:-null}" 2>/dev/null)"
  end_reason="$(jq -r '.reason // empty' <<<"${existing:-null}" 2>/dev/null)"
  summary="$(jq -r '.summary // empty' <<<"${existing:-null}" 2>/dev/null)"
  detail="$(jq -r '.detail // empty' <<<"${existing:-null}" 2>/dev/null)"

  if [ "$project_explicit" != 1 ]; then
    project_id="$(_afx_session_project_map_get "$sid")"
    if [ -n "$project_id" ]; then
      echo "afx push: reusing project $project_id from a previous push of this session"
    else
      project_id="$(_afx_dir_project_map_get "$dir_key")"
      [ -n "$project_id" ] && echo "afx push: reusing project $project_id already on record for $dir_key"
    fi
  fi

  echo "afx push: pushing ${sid:0:6} ($cwd_dir)${project_id:+ to project $project_id}"

  echo "afx push: gate 1: scanning for secrets..."
  local secret_report; secret_report="$(_afx_scan_secrets "$file" "${allow_secrets[@]:-}")"
  if [ -n "$secret_report" ]; then
    echo "afx push: refused: high-confidence secret findings:" >&2
    echo "$secret_report" | sed 's/^/  /' >&2
    echo "afx push: fix these, or re-run with --allow-secret <finding-id> for each one you've reviewed and want to push anyway" >&2
    return 1
  fi

  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  echo "afx push: gate 1: aliasing paths/host/user..."
  _afx_alias_paths "$file" "$tmpdir/aliased.jsonl" "$project_parent" "$hostname_val" "$osuser_val"
  echo "afx push: gate 1: shrinking large tool outputs..."
  _afx_shrink_outputs "$tmpdir/aliased.jsonl" "$tmpdir/shrunk.jsonl" "${AFX_PUSH_EXCERPT_CHARS:-8000}"

  # No project given, and none on record for this session: create a
  # project of one, same default the web /publish flow already applies to
  # a plain artifact publish (apps/web/lib/publish.ts's createProjectOfOne)
  # -- a session never HAS to be filed under an existing project first.
  if [ -z "$project_id" ]; then
    echo "afx push: no project on record: creating a project of one..."
    local proj_title proj_summary create_resp create_status
    proj_title="${summary:-$(basename "$cwd_dir")}"
    [ -n "$proj_title" ] || proj_title="session ${sid:0:6}"
    proj_summary="Auto-created by afx push for Claude Code session ${sid:0:6}."
    create_resp="$(curl -sS -w '\n%{http_code}' -X POST "$api_url/api/v1/projects" \
      -H "Authorization: Bearer $ARTIFAX_API_TOKEN" -H "Content-Type: application/json" \
      -d "$(jq -nc --arg t "$proj_title" --arg s "$proj_summary" '{title:$t, summary:$s}')")"
    create_status="$(tail -1 <<<"$create_resp")"
    create_resp="$(sed '$d' <<<"$create_resp")"
    if [ "$create_status" != 201 ]; then
      echo "afx push: couldn't auto-create a project ($create_status): $create_resp" >&2
      echo "afx push: pass --project <id> explicitly, or check your token has the projects:write scope" >&2
      return 1
    fi
    project_id="$(jq -r '.id' <<<"$create_resp")"
    echo "afx push: created project $project_id ($proj_title)"
  fi

  # -n (no name/timestamp): plain `gzip -c` embeds the source file's mtime in the gzip
  # header, and $tmpdir is fresh every run (mktemp -d above) -- so byte-identical
  # decompressed content hashed differently on every push, defeating both the server's
  # upload dedup (POST /api/v1/uploads' "have_it" check) and PLAN-SESSIONS.md §19.4's
  # unchanged-revision check.
  gzip -cn "$tmpdir/shrunk.jsonl" > "$tmpdir/transcript.jsonl.gz"
  local sha256 byte_size
  sha256="$(sha256sum "$tmpdir/transcript.jsonl.gz" | cut -d' ' -f1)"
  byte_size="$(wc -c < "$tmpdir/transcript.jsonl.gz" | tr -d ' ')"
  echo "afx push: transcript aliased+shrunk+gzipped: $byte_size bytes, sha256 ${sha256:0:12}..."

  echo "afx push: requesting upload slot..."
  local upload_resp upload_status
  upload_resp="$(curl -sS -w '\n%{http_code}' -X POST "$api_url/api/v1/uploads" \
    -H "Authorization: Bearer $ARTIFAX_API_TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -nc --arg sha "$sha256" --argjson sz "$byte_size" '{kind:"session_transcript", sha256:$sha, byte_size:$sz, content_encoding:"gzip"}')")"
  upload_status="$(tail -1 <<<"$upload_resp")"
  upload_resp="$(sed '$d' <<<"$upload_resp")"
  if [ "$upload_status" != 200 ]; then
    echo "afx push: upload request failed ($upload_status): $upload_resp" >&2
    return 1
  fi
  local upload_kind; upload_kind="$(jq -r '.status' <<<"$upload_resp")"
  if [ "$upload_kind" = upload ]; then
    local put_url; put_url="$(jq -r '.upload_url' <<<"$upload_resp")"
    echo "afx push: uploading..."
    local put_status; put_status="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$put_url" -H "Content-Type: application/gzip" --data-binary "@$tmpdir/transcript.jsonl.gz")"
    if [ "$put_status" != 200 ]; then
      echo "afx push: upload PUT failed ($put_status)" >&2
      return 1
    fi
  else
    echo "afx push: server already has this content (dedup): skipping upload"
  fi

  echo "afx push: pushing session metadata..."
  local push_body; push_body="$(jq -nc \
    --arg source "claude_code" --arg extid "$sid" --arg host "$hostname_val" --arg user "$osuser_val" \
    --arg summary "$summary" --arg detail "$detail" --arg end_reason "$end_reason" \
    --arg cwd_alias "<project>/$(basename "$cwd_dir")" --argjson prompt_count "${prompt_count:-null}" \
    --arg sha "$sha256" --argjson sz "$byte_size" \
    '{source: $source, external_id: $extid,
      host: (if $host == "" then null else {hostname: $host, os_user: $user} end),
      summary: (if $summary == "" then null else $summary end),
      detail: (if $detail == "" then null else $detail end),
      end_reason: (if $end_reason == "" then null else $end_reason end),
      cwd_alias: $cwd_alias, prompt_count: $prompt_count,
      transcript_sha256: $sha, byte_size: $sz}')"

  local push_resp push_status
  push_resp="$(curl -sS -w '\n%{http_code}' -X POST "$api_url/api/v1/projects/$project_id/sessions" \
    -H "Authorization: Bearer $ARTIFAX_API_TOKEN" -H "Content-Type: application/json" -d "$push_body")"
  push_status="$(tail -1 <<<"$push_resp")"
  push_resp="$(sed '$d' <<<"$push_resp")"

  # Record (or reconfirm) which project this session lives in -- including
  # when --project was explicit, so a LATER omitted push reuses whatever
  # was last actually used rather than the map going stale.
  if [ "$push_status" = 200 ] || [ "$push_status" = 201 ]; then
    _afx_session_project_map_set "$sid" "$project_id"
    _afx_dir_project_map_set "$dir_key" "$project_id"
  fi

  case "$push_status" in
    200) echo "afx push: unchanged: server already has this exact revision ($(jq -r '.id' <<<"$push_resp"), revision $(jq -r '.revision' <<<"$push_resp"))" ;;
    201) echo "afx push: pushed: $(jq -r '.id' <<<"$push_resp") revision $(jq -r '.revision' <<<"$push_resp") ($(jq -r '.message_count' <<<"$push_resp") messages, $(jq -r '.event_count' <<<"$push_resp") events)" ;;
    409) echo "afx push: diverged: the server's copy of this session has grown differently than yours. $(jq -r '.error.message' <<<"$push_resp")" >&2; return 1 ;;
    *) echo "afx push: push failed ($push_status): $push_resp" >&2; return 1 ;;
  esac

  # Session push succeeded (the two return-1 cases above never reach here): also sync
  # this project's local memory, same command, no separate step.
  _afx_push_memory "$api_url" "$project_id" "$home" "$cwd_dir"
}

# --- afx pull: pull a session from artifax.dev and make it resumable here (§22 phase S2) ---
#
# Unlike afx go/star/rm/push's HASH argument (a local afx session_id
# prefix), afx pull's arguments are artifax's own identifiers: a project
# id (required) and, optionally, a prefix of the artifax session id GET
# .../bundle returns (afx push's own "pushed: <id>" line is exactly that
# id). No local data source lists these, so afx pull gets no tab
# completion.
#
# Registers the pull target in .claude.json's projects map -- validated necessary the
# hard way earlier in this project's own history (PLAN-SESSIONS.md §22.1 risk 1):
# `claude --resume` refuses to find a session whose jsonl is correctly placed under
# ~/.claude/projects/<munged>/ if the directory it resolves to was never registered
# there, even though the file itself is right where it looks.

# Registers $2 (an absolute dir) in $1's (a CLAUDE_CONFIG_DIR) .claude.json projects map
# if not already present. Never touches an existing entry -- pulling into a directory
# that already has real Claude Code history/config must not disturb it.
_afx_register_claude_project () {
  local home="$1" dir="$2"
  local f="$home/.claude.json"
  [ -f "$f" ] || echo '{}' > "$f"
  _afx_lock "$f"
  jq --arg d "$dir" '.projects[$d] //= {
    allowedTools: [], mcpContextUris: [], mcpServers: {},
    enabledMcpjsonServers: [], disabledMcpjsonServers: [],
    hasTrustDialogAccepted: true,
    hasClaudeMdExternalIncludesApproved: false,
    hasClaudeMdExternalIncludesWarningShown: false
  }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  _afx_unlock "$f"
}

# Gives a pulled session an `afx go`-able row -- the same shape the UserPromptSubmit hook
# itself writes -- so `afx go <hash>` works right away instead of needing a manual
# `claude --resume` first. Always upserts, never insert-only: a session pulled a second
# time (e.g. into a different --into dir, or under a different CLAUDE_CONFIG_DIR) must
# have dir/home refreshed to match where it actually landed THIS time, or `afx go` would
# keep resolving to a stale, possibly wrong, location from an earlier pull. starred/note
# survive the upsert untouched (pulled straight from whatever row already existed, same
# as `afx star`'s own read-before-write care) so a re-pull can never silently erase either.
_afx_sessions_row_upsert () {
  local f="$1" date sid dir home tool reason summary
  date="$2"; sid="$3"; dir="$4"; home="$5"; tool="$6"; reason="$7"; summary="$8"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || : > "$f"
  local existing starred note detail
  existing="$(jq -c --arg s "$sid" 'select(.session_id == $s)' "$f" 2>/dev/null | tail -1)"
  starred="$(jq -r '.starred // false' <<<"${existing:-null}" 2>/dev/null)"
  note="$(jq -r '.note // empty' <<<"${existing:-null}" 2>/dev/null)"
  detail="$(jq -r '.detail // empty' <<<"${existing:-null}" 2>/dev/null)"
  _afx_lock "$f"
  {
    jq -c --arg s "$sid" 'select(.session_id != $s)' "$f" 2>/dev/null
    jq -nc --arg date "$date" --arg sid "$sid" --arg dir "$dir" --arg home "$home" \
      --arg tool "$tool" --arg reason "$reason" --arg summary "$summary" \
      --argjson starred "${starred:-false}" --arg note "$note" --arg detail "$detail" \
      '{date:$date, session_id:$sid, dir:$dir, home:$home, tool:$tool, reason:$reason,
        summary:(if $summary=="" then null else $summary end),
        detail:(if $detail=="" then null else $detail end),
        starred:$starred, note:(if $note=="" then null else $note end), prompts:null}'
  } > "$f.tmp" && mv "$f.tmp" "$f"
  _afx_unlock "$f"
}

afx_pull () {
  local project_id="" session_prefix="" into_dir=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --into) into_dir="$2"; shift 2 ;;
      -*) echo "afx pull: unknown option $1" >&2; return 1 ;;
      *) if [ -z "$project_id" ]; then project_id="$1"; shift;
         elif [ -z "$session_prefix" ]; then session_prefix="$1"; shift;
         else echo "afx pull: unexpected argument $1" >&2; return 1; fi ;;
    esac
  done
  [ -n "$project_id" ] || { echo "afx pull: usage: afx pull <project-id-or-hash> [session-id-prefix] [--into <dir>]" >&2; return 1; }
  [ -n "${ARTIFAX_API_TOKEN:-}" ] || { echo "afx pull: \$ARTIFAX_API_TOKEN not set (needs the sessions:read scope)" >&2; return 1; }
  local c
  for c in jq curl gunzip; do
    command -v "$c" >/dev/null 2>&1 || { echo "afx pull: $c is required" >&2; return 1; }
  done

  local api_url="${ARTIFAX_API_URL:-https://artifax.dev}"

  # A real artifax project id is a 26-char uppercase Crockford-base32 ULID. Anything
  # else is treated as a local session-hash prefix -- the exact same value `afx push
  # <hash>` already accepts -- and resolved server-side via GET /api/v1/sessions to the
  # project it lives in. This is what lets `afx push xyz123` and, on another machine,
  # `afx pull xyz123` use the literal same identifier: no project id to copy anywhere.
  if ! [[ "$project_id" =~ ^[0-9A-HJKMNP-TV-Z]{26}$ ]]; then
    local hash_arg="$project_id"
    echo "afx pull: $hash_arg doesn't look like a project id -- resolving as a session hash..."
    local lookup_resp lookup_status
    lookup_resp="$(curl -sS -w '\n%{http_code}' "$api_url/api/v1/sessions?external_id_prefix=$project_id" -H "Authorization: Bearer $ARTIFAX_API_TOKEN")"
    lookup_status="$(tail -1 <<<"$lookup_resp")"
    lookup_resp="$(sed '$d' <<<"$lookup_resp")"
    if [ "$lookup_status" != 200 ]; then
      echo "afx pull: couldn't resolve $hash_arg ($lookup_status): $lookup_resp" >&2
      return 1
    fi
    local distinct_projects match_count
    distinct_projects="$(jq -r '[.items[].project_id] | unique | .[]' <<<"$lookup_resp")"
    if [ -z "$distinct_projects" ]; then
      match_count=0
    else
      match_count="$(wc -l <<<"$distinct_projects" | tr -d ' ')"
    fi
    if [ "$match_count" -eq 0 ]; then
      echo "afx pull: no session found matching hash $hash_arg (or you don't have access to its project)" >&2
      return 1
    elif [ "$match_count" -gt 1 ]; then
      echo "afx pull: hash $hash_arg matches sessions in more than one project you can see -- use the full project id instead:" >&2
      echo "$distinct_projects" >&2
      return 1
    fi
    project_id="$distinct_projects"
    echo "afx pull: resolved $hash_arg -> project $project_id"
  fi

  echo "afx pull: fetching bundle for project $project_id..."
  local bundle_resp bundle_status
  bundle_resp="$(curl -sS -w '\n%{http_code}' "$api_url/api/v1/projects/$project_id/bundle" -H "Authorization: Bearer $ARTIFAX_API_TOKEN")"
  bundle_status="$(tail -1 <<<"$bundle_resp")"
  bundle_resp="$(sed '$d' <<<"$bundle_resp")"
  if [ "$bundle_status" != 200 ]; then
    echo "afx pull: couldn't fetch bundle ($bundle_status): $bundle_resp" >&2
    return 1
  fi

  local session_count; session_count="$(jq '.sessions | length' <<<"$bundle_resp")"
  if [ "$session_count" -eq 0 ]; then
    echo "afx pull: no sessions in project $project_id" >&2
    return 1
  fi

  local matches
  if [ -n "$session_prefix" ]; then
    matches="$(jq -c --arg p "$session_prefix" '[.sessions[] | select(.id | startswith($p))]' <<<"$bundle_resp")"
  else
    matches="$(jq -c '.sessions' <<<"$bundle_resp")"
  fi
  local match_count; match_count="$(jq 'length' <<<"$matches")"

  if [ "$match_count" -eq 0 ]; then
    echo "afx pull: no session matching '$session_prefix' in this project" >&2
    return 1
  elif [ "$match_count" -gt 1 ]; then
    echo "afx pull: multiple sessions match: pick one by id prefix:" >&2
    jq -r '.[] | "  " + .id[0:12] + "  " + .source + "  " + (.summary // "(no summary)")' <<<"$matches" >&2
    return 1
  fi

  local one; one="$(jq -c '.[0]' <<<"$matches")"
  local sid_artifax external_id source_val summary download_url
  sid_artifax="$(jq -r '.id' <<<"$one")"
  external_id="$(jq -r '.external_id // empty' <<<"$one")"
  source_val="$(jq -r '.source' <<<"$one")"
  summary="$(jq -r '.summary // empty' <<<"$one")"
  download_url="$(jq -r '.download_url' <<<"$one")"

  [ "$source_val" = claude_code ] || { echo "afx pull: only claude_code sessions can be resumed right now (this is $source_val)" >&2; return 1; }
  [ -n "$external_id" ] || { echo "afx pull: this session has no external_id (pushed without a resumable local session): nothing to resume" >&2; return 1; }

  [ -n "$into_dir" ] || into_dir="$PWD"
  case "$into_dir" in /*) ;; *) into_dir="$PWD/$into_dir" ;; esac
  mkdir -p "$into_dir"
  into_dir="$(cd "$into_dir" && pwd)"

  echo "afx pull: pulling session ${sid_artifax:0:12} into $into_dir..."
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  curl -sS -o "$tmpdir/transcript.jsonl.gz" "$download_url" || { echo "afx pull: download failed" >&2; return 1; }
  gunzip -c "$tmpdir/transcript.jsonl.gz" > "$tmpdir/transcript.jsonl"

  # Rewrite the <project> placeholder (afx push's own gate-1 aliasing) to the REAL local dir
  # chosen HERE -- not the original pusher's real path, which was never uploaded at all.
  sed -e "s|<project>|$(printf '%s' "$into_dir" | sed 's/[\/&|]/\\&/g')|g" "$tmpdir/transcript.jsonl" > "$tmpdir/rewritten.jsonl"

  local claude_home="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local proj_dir; proj_dir="$(_afx_proj_dir "$claude_home" "$into_dir")"
  mkdir -p "$proj_dir"
  cp "$tmpdir/rewritten.jsonl" "$proj_dir/$external_id.jsonl"

  _afx_register_claude_project "$claude_home" "$into_dir"

  local afx_sessions="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
  _afx_sessions_row_upsert "$afx_sessions" "$(date '+%F %H:%M')" "$external_id" "$into_dir" "$claude_home" claude pulled_from_artifax "$summary"

  # bundle_resp was already fetched above to find this session -- its .memory array (if
  # the token has memory:read; empty otherwise) rides along, no extra request needed.
  _afx_pull_memory "$bundle_resp" "$claude_home" "$into_dir" "$project_id"

  echo "afx pull: pulled. resume with:"
  echo "  cd $into_dir && claude --resume $external_id"
  echo "  (or: afx go ${external_id:0:6})"
}

afx_help () {
  cat <<'EOF'
afx — a CLI for coding-agent sessions (Claude Code and Codex), and the
client for artifax.dev.

  afx star [hash] [note...]   star/un-star the current (or given) session
  afx go [hash]                cd to its dir and resume the session
  afx list [opts] [pattern]    list every session (see afx list --help)
  afx status                   is this session/dir starred?
  afx rm <hash>                permanently delete a session's row
  afx find [-n N] [-r] <pat>   search transcripts for a real user prompt
  afx jobs [-n N] [-r] [pat]   list background jobs started from a session
  afx push [hash] [opts]       push a session to artifax.dev
  afx pull <project-id-or-hash> [opts]  pull a session back down from artifax.dev

Every session's HASH (from `afx list`) is a shortcut for star/go/rm/push.
Run `source afx.sh` from .bashrc/.zshrc for `afx go` to actually cd your
shell; see the README for full details and every option.
EOF
}

# afx: single dispatcher for every subcommand above.
afx () {
  local cmd="${1:-}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    star) afx_star "$@" ;;
    go) afx_go "$@" ;;
    list) afx_list "$@" ;;
    status) afx_status "$@" ;;
    rm) afx_rm "$@" ;;
    find) afx_find "$@" ;;
    jobs) afx_jobs "$@" ;;
    push) afx_push "$@" ;;
    pull) afx_pull "$@" ;;
    help|--help|-h|"") afx_help ;;
    *) echo "afx: unknown command: $cmd (see: afx help)" >&2; return 1 ;;
  esac
}

# Tab completion: first word completes a subcommand; a second word
# completes a session HASH for the subcommands that take one.
_afx_complete () {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "star go list status rm find jobs push pull help" -- "$cur") )
    return 0
  fi
  case "${COMP_WORDS[1]}" in
    star|go|rm|push)
      local f="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
      [ -r "$f" ] || return 0
      local hashes; hashes="$(jq -r '.session_id[0:6]' "$f" 2>/dev/null)"
      COMPREPLY=( $(compgen -W "$hashes" -- "$cur") )
      ;;
  esac
}
if [ -n "$BASH_VERSION" ]; then
  complete -F _afx_complete afx
fi

# Same completion for plain zsh (no bashcompinit): needs the zsh
# completion system already loaded (`autoload -Uz compinit && compinit`
# in .zshrc) -- if compdef isn't defined yet, this silently does nothing,
# same as the bash guard above.
if [ -n "$ZSH_VERSION" ] && typeset -f compdef >/dev/null 2>&1; then
  _afx_complete_zsh () {
    if [ "$CURRENT" -eq 2 ]; then
      compadd star go list status rm find jobs push pull help
      return
    fi
    case "${words[2]}" in
      star|go|rm|push)
        local f="${AFX_SESSIONS:-$HOME/.afx/sessions.jsonl}"
        [ -r "$f" ] || return 0
        local -a hashes
        hashes=($(jq -r '.session_id[0:6]' "$f" 2>/dev/null))
        compadd -- "${hashes[@]}"
        ;;
    esac
  }
  compdef _afx_complete_zsh afx
fi
