# Readout client — working rules

This repository is the public client for a readout server: the `readout` CLI, the `readout`
agent skill, and the installer. It is open source (MIT).

## What lives here

- `bin/readout` — the CLI. Bash, `curl` and `jq` only. No other runtime.
- `skills/readout/SKILL.md` — one skill for every coding agent. Use shell commands only; no
  agent-specific tool names.
- `install.sh` — symlinks the CLI and skill into the user's home. Idempotent. Never overwrites
  anything it does not own.
- `docs/api.md` — the v1 HTTP contract. It is the source of truth for the API. Any CLI change
  that needs a new endpoint or field changes this file first.
- `test/` — plain-bash tests. `READOUT_DRY_RUN=1` and `READOUT_CURL=<fake>` keep them offline.

## Rules

- **Public by default.** Never add personal paths, private hostnames other than the default
  `READOUT_URL`, private repository names, secrets, or notes about anyone's infrastructure.
- **Stable contract.** The API is versioned under `/api/v1`. Breaking changes need `/api/v2`.
  Additive fields are fine.
- **Portable bash.** Must run on Linux and macOS (bash 3.2 compatible where practical; no GNU-only
  flags without a fallback). Run `shellcheck` on scripts when available.
- **Verify** with `bash test/cli_test.sh && bash test/install_test.sh` before calling work done.
- **No AI attribution** in commits, comments or docs.
- Never commit or push without explicit authorization.

## Commits

[Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/):
`type(scope): summary`, optionally followed by an issue reference `(#123)`.

- **Types:** `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`.
- **Scopes:** `cli`, `skill`, `install`, `api` (the contract in `docs/api.md`). Omit the scope
  when a change spans the repo.
- **Summary:** lowercase, no trailing period, at most 72 characters. Describe the effect a user
  sees, not the mechanism: `fix(cli): keep error bodies visible when the server returns 4xx`.
- **Breaking changes:** `!` after the type or scope (`feat(api)!: …`) plus a
  `BREAKING CHANGE:` footer.
- No AI co-author trailers, attribution footers or session links.
