#!/usr/bin/env bash
# session-state.sh - machine-derived project state, printed at session start.
#
# Purpose: a fresh session should learn which handoff is current from the
# repository, not from a human remembering to mention it. This prints Git
# state, the registered handoff, and the registered check, and it warns when a
# newer state-shaped document exists alongside the registered one.
#
# It is deliberately SILENT in repos that have not opted in, so installing the
# plugin does not add noise to every unrelated project. Opt in by creating
# .claude/state.conf at the repository root, or by committing a document named
# HANDOFF*.md / STATUS*.md / STATE*.md / NEXT-SESSION*.md / PROGRESS*.md.
#
# Running CHECK needs two switches, one of them outside the repository: the
# repo's CHECK_SAFE=yes, plus its path listed in ~/.claude/session-state-allow.
#
# Run `bash scripts/session-state.sh --selftest` to see what it would print
# here and, if it would print nothing, why.
#
# It never fails a session: every branch exits 0.

SELFTEST=0
[ "$1" = "--selftest" ] && SELFTEST=1

# --- portable helpers ------------------------------------------------------
mtime() { # epoch seconds for a file, 0 when unknown
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}
human_time() { # YYYY-MM-DD HH:MM from epoch seconds, empty when unknown
  date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || true
}

# --- locate the repository -------------------------------------------------
# Claude Code passes hook input as JSON on stdin. Use the cwd it reports when
# jq is available; fall back to $PWD otherwise. Never block on stdin.
DIR=""
if [ "$SELFTEST" = 0 ] && [ ! -t 0 ]; then
  input=$(cat 2>/dev/null)
  if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
    DIR=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)
  fi
fi
[ -z "$DIR" ] && DIR="$PWD"
cd "$DIR" 2>/dev/null || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
  [ "$SELFTEST" = 1 ] && echo "selftest: silent here - $DIR is not a Git repository."
  exit 0
fi
cd "$ROOT" || exit 0

CONF="$ROOT/.claude/state.conf"
CHECK=""; CHECK_SAFE=""; HANDOFF=""
if [ -f "$CONF" ]; then
  CHECK=$(grep -E '^CHECK=' "$CONF" | head -1 | cut -d= -f2-)
  CHECK_SAFE=$(grep -E '^CHECK_SAFE=' "$CONF" | head -1 | cut -d= -f2- | tr -d ' ')
  HANDOFF=$(grep -E '^HANDOFF=' "$CONF" | head -1 | cut -d= -f2-)
fi

# --- find state-shaped documents the repository tracks ---------------------
# An empty candidate list makes `ls -t` list the whole directory, which once
# reported an unrelated a.txt as a handoff. Guard the empty case.
CANDS=$(git ls-files 2>/dev/null \
  | grep -iE '(^|/)(HANDOFF|STATUS|STATE|NEXT-SESSION|PROGRESS)[^/]*\.md$')
NEWEST=""
if [ -n "$CANDS" ]; then
  NEWEST=$(printf '%s\n' "$CANDS" | while IFS= read -r f; do
             [ -f "$f" ] && printf '%s\t%s\n' "$(mtime "$f")" "$f"
           done | sort -rn | head -1 | cut -f2-)
fi

# --- silence in repos that have not opted in -------------------------------
if [ ! -f "$CONF" ] && [ -z "$NEWEST" ]; then
  if [ "$SELFTEST" = 1 ]; then
    echo "selftest: silent here - no .claude/state.conf and no tracked"
    echo "          HANDOFF*.md / STATUS*.md / STATE*.md / NEXT-SESSION*.md / PROGRESS*.md."
    echo "          Create .claude/state.conf to opt this repository in."
  fi
  exit 0
fi

echo "== PROJECT STATE: $(basename "$ROOT") =="
echo "(machine-derived at session start; prefer these over any number written in a document)"

# --- git -------------------------------------------------------------------
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
LAST=$(git log -1 --format='%h %cs %s' 2>/dev/null | cut -c1-90)
DIRTY=$(git status --short 2>/dev/null | grep -c .)
echo "git      : $BRANCH | last $LAST | $DIRTY uncommitted"

# --- the registered handoff, and whether anything contradicts it -----------
if [ -n "$HANDOFF" ]; then
  if [ ! -f "$ROOT/$HANDOFF" ]; then
    echo "handoff  : MISMATCH - state.conf names '$HANDOFF', which does not exist"
  elif [ -n "$NEWEST" ] && [ "$NEWEST" != "$HANDOFF" ]; then
    echo "handoff  : $HANDOFF"
    echo "           MISMATCH - '$NEWEST' is newer. One of them is lying; check before trusting either."
  else
    echo "handoff  : $HANDOFF ($(human_time "$(mtime "$ROOT/$HANDOFF")"))"
  fi
elif [ -n "$NEWEST" ]; then
  echo "handoff  : none registered. Newest state-shaped document is '$NEWEST' - unverified as current."
fi

# --- worktrees: aliased paths an untargeted grep can hit -------------------
WT=$(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | sed 's/^worktree //' | tail -n +2)
if [ -n "$WT" ]; then
  echo "worktree : $(printf '%s\n' "$WT" | grep -c .) present - an untargeted grep from here can match the wrong copy"
  while IFS= read -r w; do
    [ -z "$w" ] && continue
    echo "           $(basename "$w") on $(git -C "$w" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  done <<< "$WT"
fi

# --- the registered check --------------------------------------------------
# SECURITY: CHECK is a command that lives in the repository's own config file,
# so a repository you cloned must never be able to cause its own execution.
# Two independent switches are required, and one of them is outside the repo:
#
#   1. the repo's .claude/state.conf sets CHECK_SAFE=yes, and
#   2. the repo's absolute path is listed in ~/.claude/session-state-allow,
#      a file on this machine that no clone or pull can write.
#
# This is the direnv model: the repo may propose, only the local machine
# allows. SESSION_STATE_NO_CHECK=1 turns it off everywhere regardless.
ALLOWFILE="${SESSION_STATE_ALLOWFILE:-$HOME/.claude/session-state-allow}"
ALLOWED=0
# Git Bash spells the same directory C:/x, /c/x or C:\x depending on who asked.
# Compare a canonical form so a hand-added line still matches. Comparison stays
# exact apart from the drive prefix.
normpath() {
  local p="${1//\\//}"
  case "$p" in
    [A-Za-z]:/*) p="/$(printf '%s' "${p%%:*}" | tr 'A-Z' 'a-z')/${p#*:/}" ;;
  esac
  printf '%s' "${p%/}"
}
if [ -f "$ALLOWFILE" ]; then
  RN=$(normpath "$ROOT")
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    if [ "$(normpath "$line")" = "$RN" ]; then ALLOWED=1; break; fi
  done < "$ALLOWFILE"
fi

if [ -n "$CHECK" ] && [ "$SESSION_STATE_NO_CHECK" = "1" ]; then
  echo "check    : \`$CHECK\` registered but SESSION_STATE_NO_CHECK=1, so it was not run."
elif [ -n "$CHECK" ] && [ "$CHECK_SAFE" = "yes" ] && [ "$ALLOWED" = 0 ]; then
  echo "check    : \`$CHECK\` registered, but this repository is not allowed to run it on"
  echo "           this machine. Read the command first. To allow it:"
  echo "           echo '$ROOT' >> $ALLOWFILE"
elif [ -n "$CHECK" ] && [ "$CHECK_SAFE" = "yes" ]; then
  if command -v timeout >/dev/null 2>&1; then
    OUT=$(cd "$ROOT" && timeout 45 bash -c "$CHECK" 2>&1); RC=$?
  else
    OUT=$(cd "$ROOT" && bash -c "$CHECK" 2>&1); RC=$?
  fi
  if [ $RC -eq 124 ]; then
    echo "check    : TIMED OUT after 45s - \`$CHECK\`"
  else
    echo "check    : \`$CHECK\`"
    printf '%s\n' "$OUT" | tail -14 | sed 's/^/           /'
  fi
elif [ -n "$CHECK" ]; then
  echo "check    : \`$CHECK\` registered but not marked CHECK_SAFE=yes, so it was not run."
else
  echo "check    : none registered. Numbers written in documents here are unverified."
fi

exit 0
