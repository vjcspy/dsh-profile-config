#!/usr/bin/env bash
# refresh-templates.sh — regenerate the tracked *.example templates from the
# LIVE (gitignored) home-level files.
#
#   ./bin/refresh-templates.sh
#
# Daily-use rule (README): after changing DSH settings, run this script and
# commit the template diff — template drift becomes a visible diff, and the
# pre-commit gitleaks hook is the safety net on this script's output.
#
# Redaction policy — SELECTIVE, not blanket:
#   - A value is replaced with <REDACTED> when its KEY name looks secret
#     (apiKey/api_key/token/secret/password/credential/...), OR when the value
#     itself matches a high-confidence secret shape (sk-…, ghp_…, xox…, a JWT,
#     or a long unbroken mixed-case+digit token).
#   - Every other value is preserved verbatim, so the template is a real
#     configuration backup (provider/model selections, theme, sidebar tabs,
#     MCP server definitions, …) and not just an empty key skeleton.
#   - Structure lines (bare keys, list items, {}, [], comments, block scalars)
#     pass through untouched.
#
# Why selective: the earlier blanket-<REDACTED> version versioned the key
# structure but none of the configuration, so a restore on another machine
# yielded an empty settings file. Real values are what the backup is for; the
# secrets stay out via the two rules above AND the fail-closed gitleaks
# pre-commit gate.
#
# Behavior:
#   - settings.yaml        -> settings.example.yaml
#   - cordis.patch.yml     -> cordis.patch.example.yml
#   - Refuses to overwrite a template if the live source file is missing.

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
  # Selectively redacts the YAML file given as $1, writing to stdout.
  python3 - "$1" <<'PYEOF'
import re
import sys

path = sys.argv[1]

# A scalar line: "  someKey: some value" (any indentation, optional list dash).
scalar_re = re.compile(r'^(\s*-?\s*[\w.\-"\'\[\]]+\s*:\s+)(\S.*)$')
# The key captured out of the same line shape, for name-based matching.
key_re = re.compile(r'^\s*-?\s*([\w.\-"\'\[\]]+)\s*:')

# Key names that always mean "this value is a secret".
SECRET_KEY_RE = re.compile(
    r'(api[_-]?key|apikey|token|secret|password|passwd|credential|'
    r'bearer|access[_-]?key|private[_-]?key|client[_-]?secret|auth)',
    re.IGNORECASE,
)

# Value shapes that are secrets regardless of the key they sit under.
# A UUID is explicitly excluded from the long-token rule: server ids are
# configuration, not credentials.
SECRET_VALUE_RE = re.compile(
    r'^(sk-[A-Za-z0-9_\-]{10,}'
    r'|ghp_[A-Za-z0-9]{20,}'
    r'|gho_[A-Za-z0-9]{20,}'
    r'|github_pat_[A-Za-z0-9_]{20,}'
    r'|xox[baprs]-[A-Za-z0-9\-]{10,}'
    r'|eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{5,}'
    r'|(?![0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$)'
    r'[A-Za-z0-9_\-]{32,})$'
)

# Values that are structural markers, never secrets — keep verbatim.
STRUCTURAL = ("{}", "[]", "|", ">", "|-", ">-", "", "~", "null", "true", "false")

with open(path, encoding="utf-8") as fh:
    for line in fh:
        stripped = line.rstrip("\n")
        # Preserve comments, blank lines and bare keys unchanged.
        if not stripped.strip() or stripped.lstrip().startswith("#"):
            sys.stdout.write(line)
            continue
        m = scalar_re.match(stripped)
        if not m:
            sys.stdout.write(line)
            continue
        value = m.group(2).strip()
        if value in STRUCTURAL:
            sys.stdout.write(line)
            continue
        km = key_re.match(stripped)
        key = km.group(1) if km else ""
        # Strip surrounding quotes before shape-matching a JSON/JWT-looking value.
        bare = value.strip('"\'')
        if SECRET_KEY_RE.search(key) or SECRET_VALUE_RE.match(bare):
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
  echo "refreshed: ${template}  (from ${live}, secrets redacted selectively)"
done

echo "done — review the diff and commit: git diff -- '*.example*' && git add '*.example*' '*.example.yaml' '*.example.yml'"
