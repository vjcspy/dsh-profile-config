# dsh-profile-config

Git-backed [DSH](https://github.com/deepseek-ai/deepseek-harness) profile home.
The working tree of this repository **IS** `$DSH_HOME` — activated via
`bin/dsh-env.sh` (see [Switchover Runbook](#-switchover-runbook-human-executed)).

DSH resolves every path through `resolveDshHome()`:
`configured ?? $DSH_HOME ?? ~/.dsh` — so pointing `DSH_HOME` here relocates the
*entire* home (`profiles/`, home-level `cordis.patch.yml`, `settings.yaml`, …)
with zero core changes. Daily use: any change made through the DSH UI or plugin
commands lands in this working tree; review with `git status && git diff` and
commit — **history IS the backup** (for everything except the gitignored
secret-bearing files, whose *structure* is versioned via `*.example` templates).

## Layout

```
dsh-profile-config/            # == $DSH_HOME after switchover
├── bin/dsh-env.sh             # sourced-only; exports + echoes DSH_HOME
├── bin/refresh-templates.sh   # regenerate *.example from live files (values redacted)
├── settings.example.yaml      # STRUCTURE template of the gitignored live settings.yaml
├── cordis.patch.example.yml   # STRUCTURE template of the gitignored home cordis.patch.yml
├── profiles/
│   ├── web/                   # package.json, cordis.patch.yml, pnpm-workspace.yaml, patches/
│   └── headless/              # package.json, cordis.patch.yml, pnpm-workspace.yaml
├── .gitignore                 # runtime state + backup trails + home-level secrets
├── .gitleaks.toml             # secret-scan config
└── .githooks/                 # pre-commit (gitleaks, loud-fail) + pre-push (history gate)
```

Untracked but present at runtime (gitignored): `settings.yaml`,
`cordis.patch.yml` (home level), `.credentials.yaml`, `.env` (if it exists).

**Why templates instead of tracked live files:** `settings.yaml` and the home
`cordis.patch.yml` are continuously host-rewritten (every settings change
re-serializes the whole document) AND hold literal API keys — a tracked copy
would either leak keys or be permanently dirty. The templates carry the key
structure; the live files stay untracked.

## Prerequisites (before `pnpm install`)

1. Aweave checkout at exactly `/Users/P823468/work/aweave` — the `file:`
   specifiers in `profiles/*/package.json` are absolute AND are rewritten by
   the host (`writeProfileManifest`), so they cannot be hand-edited to
   relative paths.
2. `git clone` + build: `dsh-chat-wide`, `dsh-debate-bridge`,
   `dsh-project-context` (into
   `workspaces/k/dsh/<plugin>` inside that Aweave checkout).
3. `deepseek-harness` built; `~/.local/bin/dsh` symlink in place.
4. `gitleaks` installed (`brew install gitleaks`) — the committed pre-commit
   hook **fails loudly without it**.

## Provision (on a new machine with the same Aweave checkout path)

```bash
git clone git@github.com:vjcspy/dsh-profile-config.git /Users/P823468/work/aweave/workspaces/k/dsh/dsh-profile-config
cd /Users/P823468/work/aweave/workspaces/k/dsh/dsh-profile-config
git config core.hooksPath .githooks
source bin/dsh-env.sh                        # exports + echoes DSH_HOME
cp settings.example.yaml settings.yaml       # then fill in secrets
cp cordis.patch.example.yml cordis.patch.yml
cp <your-secret-store>/.credentials.yaml .credentials.yaml
(cd profiles/web && pnpm install) && (cd profiles/headless && pnpm install)
dsh web --no-open                            # boots with the backed-up config
```

Notes:

- **`patches/` alone is not the full pnpm-patch unit.** The lockfile is
  gitignored (machine/depth-relative, host-rewritten); provisioning replays
  the patch state through `pnpm install` reading
  `pnpm-workspace.yaml`'s `patchedDependencies`. Verify the patch re-applies
  after install.
- `.credentials.yaml` is provider-managed and refreshed by the host; if it is
  missing at first boot, re-authenticate instead of restoring an old copy.
- `AGENTS.md` was NOT migrated — it does not exist in the source home
  (`~/.dsh/AGENTS.md` absent at migration time, 2026-09-22).
- `.agent-presets/` was NOT migrated — the source directory contained only
  `.DS_Store` (macOS metadata, no presets).

## 🚧 Switchover Runbook (Human-executed)

> **Status: NOT YET EXECUTED.** Everything below moves the *live* runtime from
> `~/.dsh` to this repo. It is deliberately left to the Human because the
> orchestrating agent session itself runs ON the live DSH web host — stopping
> or restarting the host from inside that session would kill the session.
>
> The repo side is ready: config migrated, ignore rules verified
> (bidirectional `git check-ignore` gate), secret scan clean, hooks wired.

```bash
# 1. Stop the running DSH hosts (they hold ~/.dsh open and rewrite
#    settings.yaml live — a running host would keep writing to the OLD home):
#    stop the `dsh web` / `dsh headless` processes (Ctrl-C or process manager).

# 2. Activate the new home (in a fresh shell):
cd /Users/P823468/work/aweave/workspaces/k/dsh/dsh-profile-config
source bin/dsh-env.sh          # must echo: DSH_HOME=.../dsh-profile-config

# 3. Materialize plugins at the new path (regenerates the gitignored
#    pnpm-lock.yaml files — depth-relative, machine-specific):
(cd profiles/web && pnpm install)
(cd profiles/headless && pnpm install)

# 4. Four-layer verification (per the plugin-management SSOT) PLUS a
#    credentials check:
#    a. manifest inventory:      pnpm list --depth 0 --prod   (per profile)
#    b. default config dump:     pnpm dsh --profile web --dump-default-config
#    c. boot to authenticated readiness:  dsh web --no-open
#       (MCP servers authenticate — proves .credentials.yaml was found)
#    d. runtime Plugin-list inspection (via the DSH UI)
#    e. explicit credentials check:  test -f "$DSH_HOME/.credentials.yaml"

# 5. One REAL plugin mutation + ignore re-check (the mutation writes
#    *.before-* / *.bak-* trails and rewrites manifests — all must stay
#    ignored):
dsh plugin --profile web list
git status --porcelain --ignored        # must show a clean working tree

# 6. History scan before pushing anything new:
gitleaks git --redact -c .gitleaks.toml # full history (belt: .githooks/pre-push)

# 7. Confirm the tracked config took the switchover cleanly:
git status && git diff                  # review, then commit any host-written
                                        # legitimate changes (e.g. rewritten
                                        # package.json manifests)
```

### Rollback (keep `~/.dsh` untouched until stability is confirmed)

```bash
# Unset the home override in the shell you boot DSH from, then start DSH:
unset DSH_HOME
dsh web --no-open                # boots the old ~/.dsh home exactly as before
```

Rollback restores **config, not credentials** — `.credentials.yaml` is
provider-refreshed, so re-authenticate after rolling back. Delete `~/.dsh`
only after the Human confirms the repo home is stable.

## Daily use

- Change settings in DSH → the gitignored live files change in the working
  tree → run `./bin/refresh-templates.sh` and **commit the template diff** so
  key-structure drift becomes a visible diff (the pre-commit gitleaks hook is
  the safety net on the script's output).
- Plugin install/update/remove rewrites `profiles/*/package.json` (tracked) →
  commit the manifest diff. Regenerated `pnpm-lock.yaml`, `cordis.yml`,
  `*.before-*` / `*.bak-*` trails are gitignored.
- `bin/dsh-env.sh` is sourced-only and never calls `exit`; it prints the
  resolved `DSH_HOME` on every source so a wrong home is visible immediately.

## Secret handling (contract)

| File | Status |
| --- | --- |
| `.credentials.yaml` | gitignored, copied untracked into the home; provider-managed |
| `.env` | gitignored (insurance; did not exist at migration time) |
| `settings.yaml` | gitignored; tracked `settings.example.yaml` template |
| `cordis.patch.yml` (home level) | gitignored; tracked `cordis.patch.example.yml` template |
| `profiles/*/cordis.patch.yml` | **tracked** (safe content; `debugFile` path normalized to this repo) |

Defense-in-depth for this public repo: `.gitignore` rules (primary), a
committed `.githooks/pre-commit` gitleaks gate via
`git config core.hooksPath .githooks`, and a `.githooks/pre-push` full-history
gate. Filename-only checks are insufficient — the real exposure is a key
*value* inside a legitimately-named tracked file, which is what gitleaks
catches.

## Plan & provenance

Implemented from
`resources/workspaces/k/dsh/_plans/260922-dsh-profile-config-git.md`
(debate-approved v4). Pre-mutation capture:
harness checkout HEAD `887d316e2f659bb9fec5a0a55e6ecbb15d6b6a80` (branch
`develop`), node v22.22.2, pnpm 11.18.0.
