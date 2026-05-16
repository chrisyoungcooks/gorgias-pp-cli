---
name: Bug report
about: Something the CLI or MCP server does that doesn't match the docs
title: ''
labels: bug
assignees: ''

---

**What command did you run?**
The exact `gorgias-pp-cli ...` invocation (or MCP tool call). Redact any
real customer IDs, tickets, or emails before pasting.

**What did you expect?**
The shape from `--help`, `agent-context --json`, the README, or your own
prior experience.

**What happened instead?**
Paste the output. For JSON output, prefer `--json` so the failure shape
is unambiguous. For `--agent` (JSON + compact + no prompts), `2>&1 | jq`
is your friend.

**Environment**

- `gorgias-pp-cli version --json`:
- `gorgias-pp-cli doctor --json | jq '{cli:.config,base_url:.base_url,tenant:.tenant,version:.version,cache:.cache.status}'`:
- OS + arch (`uname -m`):
- Install method (`go install` / Homebrew / pre-built binary):

**Anything else?**
Spec gotchas (`tickets` enum quirks, `customers list` filter combos,
`--via` slug mismatches) live in the README's "Gorgias API gotchas"
section — check that first.
