#!/usr/bin/env bash
# sync-from-live.sh — refresh THIS home's contents from a running home.
#
#   ./bin/sync-from-live.sh [source-home]     # default: ~/.dsh
#
# Why: the live host rewrites package.json / cordis.patch.yml /
# pnpm-workspace.yaml / settings.yaml whenever plugins or settings change. A
# snapshot taken earlier therefore does not merely miss those changes — it
# REVERTS them on activation. (Observed: the dsh-opencode-go migration landed
# after this home was first populated, and the stale manifest would have
# re-installed dsh-opencode-session instead.)
#
# Run this BEFORE stopping the old host, and again if time passes before you
# restart. It is idempotent.
#
# What it does:
#   1. copies each profile's tracked config (package.json, cordis.patch.yml,
#      pnpm-workspace.yaml) and patches/ from the source home
#   2. copies the source home's gitignored live files (settings.yaml, home
#      cordis.patch.yml, .credentials.yaml, .env) with mode 0600
#   3. re-applies the deliberate third-party pins (see the pin table below)
#   4. regenerates the tracked *.example templates
#
# It does NOT run `pnpm install` and does NOT copy session history — see the
# README Activation Runbook for the full sequence.

set -euo pipefail

_self="${BASH_SOURCE[0]:-${(%):-%x}}"
if [ -z "${_self:-}" ] || [ ! -e "$_self" ]; then
  echo "sync-from-live.sh: cannot resolve script location" >&2
  exit 1
fi
REPO_ROOT="$(cd -- "$(dirname -- "$_self")/.." && pwd -P)"

SRC="${1:-$HOME/.dsh}"
SRC="$(cd -- "$SRC" && pwd -P)"

if [ "$SRC" = "$REPO_ROOT" ]; then
  echo "sync-from-live.sh: source home IS this repo ($SRC) — nothing to sync." >&2
  exit 1
fi
if [ ! -d "$SRC/profiles" ]; then
  echo "sync-from-live.sh: no profiles/ under the source home: $SRC" >&2
  exit 1
fi

echo "syncing from: $SRC"
echo "          to: $REPO_ROOT"
echo

# --- 1. per-profile tracked config -----------------------------------------
for profile_dir in "$SRC"/profiles/*/; do
  profile="$(basename "$profile_dir")"
  dst="$REPO_ROOT/profiles/$profile"
  [ -d "$dst" ] || continue
  for f in package.json cordis.patch.yml pnpm-workspace.yaml; do
    if [ -f "$profile_dir$f" ]; then
      cp -p "$profile_dir$f" "$dst/$f"
      echo "  profile $profile: $f"
    fi
  done
  if [ -d "$profile_dir/patches" ]; then
    mkdir -p "$dst/patches"
    cp -p "$profile_dir"patches/*.patch "$dst/patches/" 2>/dev/null || true
    echo "  profile $profile: patches/"
  fi
done

# --- 2. home-level live files (gitignored, mode 0600) -----------------------
for f in settings.yaml cordis.patch.yml .credentials.yaml .env; do
  if [ -f "$SRC/$f" ]; then
    cp -p "$SRC/$f" "$REPO_ROOT/$f"
    chmod 600 "$REPO_ROOT/$f"
    echo "  home: $f (0600)"
  fi
done

# --- 3. re-apply deliberate pins -------------------------------------------
# The lockfile is gitignored, so a fresh `pnpm install` resolves the newest
# semver match. These pins keep activation a faithful reproduction of the
# running setup; the pin table is the single place to edit.
PIN_TABLE=(
  "profiles/web/package.json|dshmarket|1.45.1"
)
for entry in "${PIN_TABLE[@]}"; do
  IFS='|' read -r rel pkg version <<<"$entry"
  target="$REPO_ROOT/$rel"
  [ -f "$target" ] || continue
  python3 - "$target" "$pkg" "$version" <<'PYEOF'
import json, re, sys
path, pkg, version = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
# Match the dependency entry whatever range it currently carries.
pattern = re.compile(r'("%s"\s*:\s*)"[^"]*"' % re.escape(pkg))
new, n = pattern.subn(lambda m: m.group(1) + '"%s"' % version, text)
if n:
    open(path, "w", encoding="utf-8").write(new)
    print(f"  pinned {pkg} -> {version} in {path.split('dsh-profile-config/')[-1]}")
PYEOF
done

# --- 4. regenerate templates ------------------------------------------------
"$REPO_ROOT/bin/refresh-templates.sh" | sed 's/^/  /'

echo
echo "done. Next:"
echo "  git status --short                     # review; commit the re-sync"
echo "  (cd profiles/web && pnpm install)      # only if the manifest changed"
