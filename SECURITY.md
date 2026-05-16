# Security policy

## Reporting a vulnerability

Report security issues privately by emailing the maintainer
(`chris` at `combustion.inc`) or by opening a
[GitHub security advisory](https://github.com/chrisyoungcooks/gorgias-pp-cli/security/advisories/new).
Please **do not** open a public issue for credential, auth, or
exfiltration concerns.

A response and triage decision usually lands within a week.

## What's in scope

- The CLI binary's handling of Gorgias API credentials
  (`GORGIAS_USERNAME`, `GORGIAS_API_KEY`, the `Authorization: Basic ...`
  header).
- The MCP server's tool surface, including the `sql` tool's read-only
  gate (see [`internal/cliutil/sqlgate.go`](./internal/cliutil/sqlgate.go)
  — the gate intentionally rejects PRAGMA/ATTACH/VACUUM and comment-
  prefix bypass shapes).
- The local SQLite mirror at `$XDG_DATA_HOME/gorgias-pp-cli/data.db` and
  the on-disk auth config at `$XDG_CONFIG_HOME/gorgias-pp-cli/config.toml`
  (both written with `0o600` / `0o700` perms).

## What's out of scope

- Vulnerabilities in upstream dependencies that don't expose the CLI's
  attack surface — report those to the upstream maintainers.
- Issues that require the attacker to already control the machine the
  CLI is running on. The CLI is a single-user local tool; it trusts the
  user's filesystem.
- The Gorgias API itself. Report API issues to
  [Gorgias support](https://docs.gorgias.com).

## Credentials hygiene

The CLI reads credentials from `GORGIAS_USERNAME` + `GORGIAS_API_KEY`
env vars or from `~/.config/gorgias-pp-cli/config.toml` (mode `0o600`).
The `--dry-run` flag masks the `Authorization` header in its preview
output. The User-Agent header carries the CLI version but no
tenant-identifying information.

For 1Password-managed credentials, use `op run --env-file` to inject
the resolved values at invocation time rather than copying secrets into
shell profiles. See [MCP.md](./MCP.md) for the wrapper-script pattern.
