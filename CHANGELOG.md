# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/) with one section
per released tag. Each entry summarizes what a user would notice on
upgrade.

## v0.1.3 — 2026-05-15

### Fixed

- README claimed `gorgias-pp-mcp` shipped as a Claude Desktop MCPB
  bundle; no `.mcpb` files were attached to any release. Dropped the
  claim and routed Claude Desktop users to a documented manual config
  in [MCP.md](./MCP.md).
- "Also indexed in the Printing Press library" link was a 404 — the
  library PR hasn't been filed. Removed the broken reference.
- `tool_count` was inconsistent across docs: README implied 11–12,
  `.printing-press.json` said `mcp_tool_count: 108` (actually the
  endpoint count), and the live MCP server reports `15`. Reconciled
  every doc to reference the live count from the `context` tool, and
  renamed the `.printing-press.json` field to `mcp_endpoint_count` so
  the 108 number doesn't pretend to be tools.
- `view-id 626049` was hardcoded in the README, profile.go, tickets_list.go,
  and client_test.go as an example. Scrubbed to `<view-id>` placeholders
  (or `123456789` in test fixtures) so the docs don't read like they
  leak a real tenant view.
- `mcp-descriptions.json` carried `{"id":"244902410"}` as a documentation
  example. Scrubbed to the standard `123456789` placeholder.

### Added

- Release notes are now auto-generated from conventional-commit
  subjects (feat / fix / docs) via goreleaser's git-changelog group.
  Empty release bodies are gone.
- Repo metadata: GitHub topics (`gorgias`, `customer-support`, `mcp`,
  `agent-tools`, `cli`, `printing-press`, `golang`), homepage set to
  the Gorgias product page, wiki disabled.
- This `CHANGELOG.md`.

### Removed

- `manifest.json` + `scripts/sync-manifest-version.sh`. The manifest
  was an MCPB bundle descriptor; with the MCPB build dropped it served
  no purpose, and the sync hook was rewriting it on every release.

## v0.1.2 — 2026-05-15

### Fixed

- `brew install chrisyoungcooks/tap/gorgias-pp-cli` only linked
  `gorgias-pp-cli` into `/opt/homebrew/bin` and left `gorgias-pp-mcp`
  stranded in the Caskroom. The cask now declares both binaries.
- The brew-installed binaries exited 137 (SIGKILL) with no error on
  first run because macOS Gatekeeper quarantined them. The cask now
  runs `xattr -dr com.apple.quarantine` on both binaries in a
  `postflight` block.

## v0.1.1 — 2026-05-15

### Fixed

- `go install github.com/chrisyoungcooks/gorgias-pp-cli/cmd/...@v0.1.0`
  reported version `0.0.0-dev` because the source-built path didn't see
  goreleaser's ldflag. Version resolution now falls back to
  `runtime/debug.ReadBuildInfo()` and reports the module version
  recorded by `go install ...@vX.Y.Z`. Goreleaser-built release
  binaries are unaffected.

## v0.1.0 — 2026-05-15

### Added

- Initial release. Token-efficient Go CLI + sibling MCP server for the
  Gorgias REST API. 108 endpoints reachable from one binary or a
  code-orchestration MCP gateway. Local SQLite mirror with FTS5 search,
  `sql` escape hatch, `stale`/`orphans`/`load` queue analytics, `doctor`
  health check, single-emission JSON error envelopes, XDG-compliant
  config/state/data paths. Built across seven adversarial-review
  iterations on the patterns top-10% Printing Press CLIs share.
