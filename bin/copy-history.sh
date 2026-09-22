#!/usr/bin/env bash
# copy-history.sh — carry session history from a running home into THIS home.
#
#   ./bin/copy-history.sh [source-home]      # default: ~/.dsh
#
# What it copies (all gitignored runtime state, never committed):
#   sessions/     — append-only, zstd-compressed session transcripts
#   storages/     — session projection cache + workspace.json (the GUI list)
#   attachments/  — image bytes referenced by session logs
#
# RUN IT TWICE around the activation:
#   1. now, to pre-seed (optional but harmless)
#   2. again AFTER the old host is stopped — the session that is still open is
#      being appended to while it runs, so the first copy holds a truncated
#      log. The second run overwrites it with the complete file.
#
# Session directories are keyed by the ABSOLUTE cwd, which does not change when
# the home moves, so a straight copy is what preserves the GUI conversation
# list. Idempotent: re-running overwrites, never duplicates.

set -euo pipefail

_self="${BASH_SOURCE[0]:-${(%):-%x}}"
if [ -z "${_self:-}" ] || [ ! -e "$_self" ]; then
  echo "copy-history.sh: cannot resolve script location" >&2
  exit 1
fi
REPO_ROOT="$(cd -- "$(dirname -- "$_self")/.." && pwd -P)"

SRC="${1:-$HOME/.dsh}"
SRC="$(cd -- "$SRC" && pwd -P)"

if [ "$SRC" = "$REPO_ROOT" ]; then
  echo "copy-history.sh: source home IS this repo ($SRC) — nothing to copy." >&2
  exit 1
fi
if [ ! -d "$SRC/sessions" ]; then
  echo "copy-history.sh: no sessions/ under the source home: $SRC" >&2
  exit 1
fi

# The session that is currently open (if this runs inside an agent shell).
ACTIVE="${DSH_SESSION_ID:-}"

echo "copying history: $SRC -> $REPO_ROOT"
echo

for d in sessions storages attachments; do
  [ -d "$SRC/$d" ] || continue
  mkdir -p "$REPO_ROOT/$d"
  if command -v rsync >/dev/null 2>&1; then
    # -a preserves modes/times; no --delete, so nothing is ever removed here.
    rsync -a "$SRC/$d/" "$REPO_ROOT/$d/"
  else
    cp -Rp "$SRC/$d/." "$REPO_ROOT/$d/"
  fi
  size="$(du -sh "$REPO_ROOT/$d" | cut -f1)"
  echo "  $d/  ($size)"
done

echo
echo "sessions copied: $(find "$REPO_ROOT/sessions" -name 'session.*' -type f 2>/dev/null | wc -l | tr -d ' ') files"
echo "conversations:   $(find "$REPO_ROOT/sessions" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')"
if [ -n "$ACTIVE" ]; then
  echo
  echo "NOTE: the session that is currently open ($ACTIVE) was written while"
  echo "      running, so its log is a mid-write snapshot. Re-run this script"
  echo "      after stopping the host to finalize it."
fi
