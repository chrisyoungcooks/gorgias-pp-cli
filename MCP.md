# `gorgias-pp-mcp` — MCP server protocol notes

`gorgias-pp-mcp` is the sibling MCP server to the `gorgias-pp-cli` binary.
This document covers the protocol-level behavior most readers don't need:
the code-orchestration gateway design, raw JSON-RPC examples, transport
selection, and host wiring patterns. The main [README](./README.md)
summarizes the same concepts in one paragraph.

## Code-orchestration gateway

Most Printing-Press-generated MCP servers expose one tool per endpoint
(28 for Linear, 197 for Twilio, 534 for Stripe). `gorgias-pp-mcp` runs in
**code-orchestration mode** and exposes a small fixed set of tools that
collectively reach all 108 Gorgias endpoints. The live tool count is
reported by the MCP `context` tool (`tool_count` in its response); there
is no hardcoded inventory.

The gateway pattern, end to end:

1. The agent calls `gorgias_search` with a natural-language query
   (e.g. "list tickets for customer X").
2. `gorgias_search` returns ranked endpoint IDs with their request
   schemas.
3. The agent calls `gorgias_execute` with the chosen `endpoint_id` and
   a params map.

This costs ~1K tokens of tool descriptions in the host's working set,
instead of ~25K for one-tool-per-endpoint. Local-mirror tools (`sync`,
`search`, `sql`, `analytics`, `orphans`, `stale`, `load`, `export`,
`tail`, `import`) are exposed as typed tools alongside the gateway —
they sit on a different surface (the local SQLite mirror) so they get
their own tool entries rather than routing through `gorgias_execute`.

## Raw JSON-RPC

Agent invocation, two-call shape:

```jsonc
// 1. Find the right endpoint.
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"gorgias_search",
  "arguments":{"query":"list tickets for customer"}
}}

// 2. Call it.
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
  "name":"gorgias_execute",
  "arguments":{"endpoint_id":"tickets.list","params":{"customer_id":"123","limit":"5"}}
}}
```

Three runtime-discovery tools complete the surface:

- `context` — full CLI/auth/schema descriptor in one call; load once
  per session.
- `gorgias-pp-cli agent-context --json` (from the CLI, not the MCP) —
  machine-readable command index, equivalent for agents driving the CLI
  directly.
- `which "<capability>"` — fuzzy capability → best-matching command.

## Transport: stdio (default) or streamable HTTP

The server defaults to stdio — the standard transport for local Claude
Desktop / Cursor / Claude Code installs. For hosted agents that run in a
container, a remote sandbox, or any setting where a process supervisor
can't pipe stdio, run it as a streamable HTTP server instead:

```bash
gorgias-pp-mcp --transport http --addr :7777
```

The HTTP server speaks the Model Context Protocol over `POST /mcp`
(JSON-RPC 2.0). The transport can also be selected via the
`PP_MCP_TRANSPORT` environment variable (`stdio` or `http`), which
matches how container-hosted agents typically pass configuration
without a flag.

## Claude Desktop config

Install the MCP binary (see [Install](./README.md#install)) and add it
to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "gorgias": {
      "command": "gorgias-pp-mcp",
      "env": {
        "GORGIAS_USERNAME": "<your-email>",
        "GORGIAS_API_KEY": "<your-api-key>",
        "GORGIAS_BASE_URL": "https://<tenant>.gorgias.com/api"
      }
    }
  }
}
```

For 1Password-managed credentials (or any other secret store), wrap the
binary in a script that resolves the secrets and exec's the MCP server.
That keeps API keys out of the config file.
