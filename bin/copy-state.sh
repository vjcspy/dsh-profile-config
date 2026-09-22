#!/usr/bin/env bash
# copy-state.sh — carry home-local runtime state from a running home into THIS
# home. This is everything the home owns that is NOT config and NOT derived:
#
#   sessions/                      append-only session transcripts
#   storages/                      session projection cache + workspace.json
#   attachments/                   image bytes referenced by session logs
#   plugins/                       plugin-owned state; REQUIRED for the model
#                                  providers — plugins/subscriptions/ holds the
#                                  subscription accounts (auth.json + the
#                                  discovered models.json). Without it every
#                                  `codex`-style subscription route fails with
#                                  "No eligible account".
#   extension-hub/                 extension-hub state (projectFolder)
#   profiles/*/.dsh-market/        per-profile plugin-market state
#
# NOT copied (derived, regenerated on boot): cache/, logs/, cordis.yml,
# node_modules/, pnpm-lock.yaml.
#
# RUN IT TWICE around the activation:
#   1. now, to pre-seed (optional but harmless)
#   2. again AFTER the old host is stopped — the session that is still open is
#      being appended to while it runs, so the first copy holds a truncated
#      log. The second run overwrites it with the complete file.
#
# Session directories are keyed by the ABSOLUTE cwd, which does not change when
# the home moves, so a straight copy is what preserves the GUI conversation
# list. Idempotent: re-running overwrites, never duplicates. Every path here is
# gitignored, so nothing lands in the repository.

set -euo pipefail

_self="${BASH_SOURCE[0]:-${(%):-%x}}"
if [ -z "${_self:-}" ] || [ ! -e "$_self" ]; then
  echo "copy-state.sh: cannot resolve script location" >&2
  exit 1
fi
REPO_ROOT="$(cd -- "$(dirname -- "$_self")/.." && pwd -P)"

SRC="${1:-$HOME/.dsh}"
SRC="$(cd -- "$SRC" && pwd -P)"

if [ "$SRC" = "$REPO_ROOT" ]; then
  echo "copy-state.sh: source home IS this repo ($SRC) — nothing to copy." >&2
  exit 1
fi

# The session that is currently open (if this runs inside an agent shell).
ACTIVE="${DSH_SESSION_ID:-}"

copy_dir() {
  local rel="$1"
  [ -d "$SRC/$rel" ] || return 0
  mkdir -p "$REPO_ROOT/$rel"
  if command -v rsync >/dev/null 2>&1; then
    # -a preserves modes/times; no --delete, so nothing is ever removed here.
    rsync -a "$SRC/$rel/" "$REPO_ROOT/$rel/"
  else
    cp -Rp "$SRC/$rel/." "$REPO_ROOT/$rel/"
  fi
  echo "  $rel/  ($(du -sh "$REPO_ROOT/$rel" | cut -f1))"
}

echo "copying state: $SRC -> $REPO_ROOT"
echo

for rel in sessions storages attachments plugins extension-hub; do
  copy_dir "$rel"
done

# Per-profile state directories.
for profile_dir in "$SRC"/profiles/*/; do
  [ -d "$profile_dir" ] || continue
  profile="$(basename "$profile_dir")"
  copy_dir "profiles/$profile/.dsh-market"
done

echo
echo "conversations: $(find "$REPO_ROOT/sessions" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')"
if [ -d "$REPO_ROOT/plugins/subscriptions" ]; then
  echo "subscription accounts: present ($(ls "$REPO_ROOT/plugins/subscriptions" | tr '\n' ' '))"
else
  echo "subscription accounts: ABSENT — codex-style subscription routes will report 'No eligible account'"
fi
if [ -n "$ACTIVE" ]; then
  echo
  echo "NOTE: the session that is currently open ($ACTIVE) was written while"
  echo "      running, so its log is a mid-write snapshot. Re-run this script"
  echo "      after stopping the host to finalize it."
fi
