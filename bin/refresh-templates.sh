#!/usr/bin/env bash
# refresh-templates.sh — regenerate the tracked *.example templates from the
# LIVE (gitignored) home-level files, with all string values blanked.
#
#   ./bin/refresh-templates.sh
#
# Daily-use rule (README): after changing DSH settings, run this script and
# commit the template diff — template drift becomes a visible diff, and the
# pre-commit gitleaks hook is the safety net on this script's output.
#
# Implementation: pure bash + python3 (stdlib yaml NOT assumed — a tiny
# line-based redactor is used instead so there are zero npm/python deps).
#
# Behavior:
#   - settings.yaml        -> settings.example.yaml
#   - cordis.patch.yml     -> cordis.patch.example.yml
#   - Refuses to overwrite a template if the live source file is missing.
#   - Values are replaced with <REDACTED>; key structure preserved.

set -euo pipefail

_self="${BASH_SOURCE[0]:-${(%):-%x}}"
if [ -z "${_self:-}" ] || [ ! -e "$_self" ]; then
  echo "refresh-templates.sh: cannot resolve script location" >&2
  exit 1
fi
REPO_ROOT="$(cd -- "$(dirname -- "$_self")/.." && pwd -P)"

# Pair: <live file>|<template file>
PAIRS=(
  "settings.yaml|settings.example.yaml"
  "cordis.patch.yml|cordis.patch.example.yml"
)

redact() {
  # Redacts the YAML file given as $1, writing to stdout.
  # Line-based redaction of scalar values: for `key: value` lines (any
  # indentation) replace the value with <REDACTED>; keep structure lines
  # (`key:`, list items, comments, blank lines, block scalars) intact.
  python3 - "$1" <<'PYEOF'
import re
import sys

path = sys.argv[1]

# A scalar line: "  someKey: some value"  (value non-empty, not a bare
# structure char). We blank the value but keep quoted-style hints off —
# <REDACTED> is safe as a plain scalar.
scalar_re = re.compile(r'^(\s*-?\s*[\w.\-"\'\[\]]+\s*:\s+)(\S.*)$')

with open(path, encoding="utf-8") as fh:
    for line in fh:
        stripped = line.rstrip("\n")
        # Preserve comments, blank lines and bare keys unchanged.
        if not stripped.strip() or stripped.lstrip().startswith("#"):
            sys.stdout.write(line)
            continue
        m = scalar_re.match(stripped)
        if m:
            value = m.group(2)
            # Keep pure-structure values (empty map/seq markers) intact.
            if value.strip() in ("{}", "[]", "|", ">", "|-", ">-", "", "~", "null"):
                sys.stdout.write(line)
            else:
                sys.stdout.write(m.group(1) + "<REDACTED>\n")
        else:
            sys.stdout.write(line)
PYEOF
}

for pair in "${PAIRS[@]}"; do
  live="${pair%%|*}"
  template="${pair##*|}"
  live_path="${REPO_ROOT}/${live}"
  template_path="${REPO_ROOT}/${template}"

  if [ ! -f "$live_path" ]; then
    echo "ERROR: live file missing: ${live}" >&2
    echo "       refusing to overwrite template ${template} (stale template is safer than a blank one)." >&2
    echo "       Provision first: cp ${template} ${live} && fill in secrets." >&2
    exit 1
  fi

  redact "$live_path" > "${template_path}.tmp"
  mv "${template_path}.tmp" "$template_path"
  chmod 644 "$template_path"
  echo "refreshed: ${template}  (from ${live}, values <REDACTED>)"
done

echo "done — review the diff and commit: git diff -- '*.example*' && git add '*.example*' '*.example.yaml' '*.example.yml'"
