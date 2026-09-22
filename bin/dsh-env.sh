#!/usr/bin/env bash
# dsh-env.sh — point $DSH_HOME at this repository (the repo working tree IS the
# DSH home). SOURCE this file; do not execute it.
#
#   source bin/dsh-env.sh        # bash
#   source bin/dsh-env.sh        # zsh (works identically)
#
# Contract:
#   - Sourced-only: NEVER calls `exit`.
#   - Resolves the repo root from this script's own path, works under both
#     bash and zsh.
#   - Exports DSH_HOME and prints the resolved path on every source, so a
#     wrong home is visible immediately.
#
# Why an env var: DSH resolves every path through resolveDshHome()
# (`configured ?? $DSH_HOME ?? ~/.dsh`), and $DSH_HOME is bootstrap-only — it
# cannot be set from any .env file (readEnvLayer() throws on DSH_* names), so
# it must be exported in the shell environment.

# Resolve this script's location:
#   bash  : ${BASH_SOURCE[0]}
#   zsh   : ${(%):-%x} (expands to the currently sourced file)
_self="${BASH_SOURCE[0]:-${(%):-%x}}"
# Fallback when neither expansion yields a path (e.g. piping the script in).
if [ -z "$_self" ] || [ ! -e "$_self" ]; then
  echo "dsh-env.sh: cannot resolve script location; source it from the repo instead" >&2
  return 1 2>/dev/null || true
fi

_dsh_env_repo_root="$(cd -- "$(dirname -- "$_self")/.." && pwd -P)"

export DSH_HOME="$_dsh_env_repo_root"
# Print the resolved home so a wrong one is visible immediately. Automated
# consumers (e.g. ~/.zshrc) set DSH_ENV_QUIET=1 to silence the per-shell line.
if [ -z "${DSH_ENV_QUIET:-}" ]; then
  echo "DSH_HOME=$_dsh_env_repo_root"
fi

# Cleanup (does not touch DSH_HOME).
unset _self _dsh_env_repo_root
