# Gorgias CLI

**Drive your Gorgias support inbox from the terminal — ticket triage, agent replies, customer lookup, and bulk operations across all 108 endpoints, plus a local SQLite mirror for instant search and analytics.**

Gorgias is the helpdesk for e-commerce support teams. This CLI gives you (or an AI agent) full control over a Gorgias tenant from a single binary: list, create, update, and reply to tickets via `tickets list / get / update / messages-create`; sweep stuck work with `stale` and `orphans`; query locally with `sync` + `sql` for SQL-grade analytics the live API doesn't expose; full-text search across synced data with `search`; and a sibling `gorgias-pp-mcp` server that lets Claude Desktop, Cursor, or Claude Code drive the surface natively. The MCP runs in code-orchestration mode so its full-API description costs ~1K tokens (not ~25K for one-tool-per-endpoint).

Learn more at [Gorgias](https://www.gorgias.com).

**Status:** Pre-release. All read endpoints are live-verified against a real Gorgias tenant (see `shipcheck-results.json`). 25 of 37 write endpoints are also live-verified (see `writes-live-shipcheck.json`, `writes-verify-once.json`); the remaining 12 are dry-run-only because they require a sandbox tenant (destructive deletes, invitation emails, async bulk jobs, the rule-DSL gate). See "Known gaps" below.

## Install

Pre-1.0, until releases are published, install from source:

```bash
go install github.com/chrisyoungcooks/gorgias-pp-cli/cmd/gorgias-pp-cli@latest
go install github.com/chrisyoungcooks/gorgias-pp-cli/cmd/gorgias-pp-mcp@latest
```

Or clone and build:

```bash
git clone https://github.com/chrisyoungcooks/gorgias-pp-cli
cd gorgias-pp-cli
go build ./...
```

Pre-built binaries will be attached to GitHub Releases once the first tag ships (see `.goreleaser.yaml`). On macOS, clear the Gatekeeper quarantine on a downloaded binary with `xattr -d com.apple.quarantine <binary>`; on Unix, `chmod +x <binary>`.

## Authentication

Gorgias uses HTTP Basic auth: your account email is the username, an API key is the password.

1. In Gorgias: **Settings → Account → REST API → Create API key.** Copy the key once — Gorgias won't show it again.
2. Set the three environment variables, however your workflow likes (shell profile, secrets manager, CI store — the CLI doesn't care which):
   ```bash
   export GORGIAS_USERNAME="you@example.com"
   export GORGIAS_API_KEY="<your-api-key>"
   export GORGIAS_BASE_URL="https://<tenant>.gorgias.com/api"
   ```
3. Verify with `gorgias-pp-cli doctor` — `Credentials: valid` means the values authenticate against `/account`.

Prefer persistent on-disk storage? `gorgias-pp-cli auth set-token <email> <api-key>` writes to `~/.config/gorgias-pp-cli/config.toml`.

## Quick Start

```bash
# 1. Confirm credentials authenticate against the live tenant.
gorgias-pp-cli doctor --json

# 2. Sync the last 7 days into the local SQLite mirror.
gorgias-pp-cli sync --resources tickets,customers,tags --since 7d --agent

# 3. Today's queue — open tickets, oldest first, with their channel + customer.
gorgias-pp-cli sql "SELECT json_extract(data, '\$.id'), json_extract(data, '\$.subject'), json_extract(data, '\$.channel'), json_extract(data, '\$.customer.email') FROM resources WHERE resource_type='tickets' AND json_extract(data, '\$.status')='open' ORDER BY json_extract(data, '\$.created_datetime') LIMIT 20" --agent

# 4. Find any open ticket matching a word (FTS5).
gorgias-pp-cli search refund --agent

# 5. Pull the message thread on a specific ticket.
gorgias-pp-cli tickets messages-list <ticket-id> --agent

# 6. Stale-ticket sweep — open tickets with no activity for 7+ days.
gorgias-pp-cli stale --days 7 --agent

# 7. Workload distribution across the team.
gorgias-pp-cli load --agent
```

## Cookbook

Common one-liners. All assume `--agent` (JSON, compact list output, no prompts). Replace any `<bracketed-placeholder>` with real values from your tenant before running — they're not magic, they're stand-ins.

```bash
# How many tickets opened today (PT)?
gorgias-pp-cli sql "SELECT COUNT(*) FROM resources WHERE resource_type='tickets' AND json_extract(data, '\$.created_datetime') >= date('now','localtime','start of day') || 'T00:00:00'" --agent

# How many tickets closed today (PT)?
gorgias-pp-cli sql "SELECT COUNT(*) FROM resources WHERE resource_type='tickets' AND substr(json_extract(data, '\$.closed_datetime'),1,10) = date('now','localtime')" --agent

# Tickets carrying a specific tag (use tag name).
gorgias-pp-cli sql "SELECT json_extract(data,'\$.id'), json_extract(data,'\$.subject') FROM resources, json_each(json_extract(data,'\$.tags')) tg WHERE resource_type='tickets' AND json_extract(tg.value,'\$.name')='cancel/refund' ORDER BY json_extract(data,'\$.created_datetime') DESC LIMIT 50" --agent

# Distribution of open tickets by assigned team.
gorgias-pp-cli sql "SELECT json_extract(data,'\$.assignee_team.name') AS team, COUNT(*) AS n FROM resources WHERE resource_type='tickets' AND json_extract(data,'\$.status')='open' GROUP BY team ORDER BY n DESC" --agent

# Unassigned open tickets.
gorgias-pp-cli orphans --agent

# Customer record by email.
gorgias-pp-cli customers list --channel-type email --channel-address you@example.com --agent

# Apply a tag to a ticket. First grab the tag id from `tags list`, then:
gorgias-pp-cli tickets update 12345 --tags '[{"id": 67890}]' --agent

# Reply to a ticket as a specific support agent. The from-address MUST match
# the dispatching integration's meta.address or the email won't actually send.
gorgias-pp-cli tickets messages-create 12345 --stdin --agent <<'JSON'
{"channel":"email","via":"email","from_agent":true,"public":true,
 "sender":{"id":111111111},
 "receiver":{"email":"customer@example.com"},
 "source":{"from":{"address":"support@your-tenant.com"},
           "to":[{"address":"customer@example.com"}]},
 "body_html":"<p>Hi …</p><p>Best,<br>Agent Name</p>",
 "integration_id":22222}
JSON

# Export the local mirror to JSONL for downstream tooling.
gorgias-pp-cli export tickets --format jsonl --output tickets.jsonl

# Stream live ticket changes (polling every 30s).
gorgias-pp-cli tail --agent

# Auto-refresh: every read syncs first if the local mirror is older than 15m.
GORGIAS_AUTO_REFRESH_TTL=15m gorgias-pp-cli tickets list --agent

# Save a named profile of global defaults, then opt in per-call with --profile.
gorgias-pp-cli profile save agent-defaults --agent --compact
gorgias-pp-cli --profile agent-defaults tickets list

# Route output to a file (atomic write) or webhook.
gorgias-pp-cli tickets list --deliver file:./tickets.json --agent
gorgias-pp-cli tickets list --deliver webhook:https://example.com/tickets --agent
```

## MCP design — code-orchestration gateway

Most PP-generated MCP servers expose one tool per endpoint (28 for Linear, 197 for Twilio, 534 for Stripe). `gorgias-pp-mcp` runs in **code-orchestration mode** and exposes a small fixed set of tools that collectively reach all 108 Gorgias endpoints. The live tool count is reported by the MCP `context` tool (`tool_count` in its response) — no hardcoded inventory. The gateway pattern:

1. The agent calls `gorgias_search` with a natural-language query (e.g. "list tickets for customer X").
2. `gorgias_search` returns ranked endpoint IDs with their request schemas.
3. The agent calls `gorgias_execute` with the chosen `endpoint_id` and a params map.

This costs ~1K tokens of tool descriptions instead of ~25K for 108 typed tools. Local-mirror tools (`sync`, `search`, `sql`, `analytics`, `orphans`, `stale`, `load`, `export`, `tail`, `import`) are exposed as typed tools alongside the gateway.

Agent invocation:

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

Three runtime-discovery tools also help: `context` (full CLI/auth/schema descriptor), `agent-context --json` (machine-readable command index), and `which "<capability>"` (fuzzy capability → best matching command).

### Transport: stdio (default) or streamable HTTP

The server defaults to stdio — the standard transport for local Claude Desktop / Cursor / Claude Code installs. For hosted agents that run in a container, a remote sandbox, or any setting where a process-supervisor can't pipe stdio, run it as a streamable HTTP server instead:

```bash
gorgias-pp-mcp --transport http --addr :7777
```

The HTTP server speaks the Model Context Protocol over `POST /mcp` (JSON-RPC 2.0). The transport can also be selected via the `PP_MCP_TRANSPORT` environment variable (`stdio` or `http`), which matches how container-hosted agents typically pass configuration without a flag.

## Known gaps

- **Writes partially live-verified.** All 37 write endpoints (POST/PUT/DELETE) have URL routing + HTTP method verified via `scripts/writes-shipcheck.sh` (`--dry-run` matrix, see `writes-shipcheck.json`). Live coverage breakdown:
  - **18 endpoints** — `tags`, `macros`, `teams`, `views`, `widgets`, `integrations` create/update/delete — fully roundtripped (auto-cleanup) by `scripts/writes-live-shipcheck.sh` (`writes-live-shipcheck.json`).
  - **3 endpoints** — `tickets` create/update/delete — verified once in manual testing, not in recurring CI (avoids customer-facing email risk).
  - **4 endpoints** — `customers` and `custom-fields` create/update — verified once by `scripts/writes-verify-once.sh` (`writes-verify-once.json`). Leaves admin-UI debris rows that need manual retiring; not in recurring CI.
  - **12 endpoints** stay dry-run-only with no live-verification possible against production: `customers delete` (loses ticket history), `users create/update/delete` (invitation emails / seat consumption / lockouts), `satisfaction-surveys create/update` (attaches a CSAT score to a real ticket), `gorgias-jobs create/update/delete` (async bulk operations), `rules create/update/delete` (DSL gate plus auto-fire risk on real tickets). A sandbox tenant would close this gap; until then they're documented internal-only.
- **No phone/voice integration coverage.** Tenants without a voice integration have no calls in these endpoints, so `phone calls-list`, `phone call-events-list`, and `phone call-recordings-list` haven't been verified live.
- **`messages list`** in the global form (`/messages`) supports only `ticket_id` filter — no datetime range, no channel filter. Use `tickets messages-list <ticket_id>` for per-ticket views.
- **Live `search`** uses Gorgias's POST `/search` which indexes customers/agents/tags — **not tickets or messages**. For ticket/message text search, sync to local first and use `gorgias-pp-cli search <query>` against the FTS5 mirror.
- **Customer-list filter incompatibilities.** `--language` and `--timezone` are mutually exclusive with `--cursor`/`--limit`/`--order-by` on `/customers` (server-side, undocumented in OpenAPI). Pick one approach per call.
- **No `--wait` for async jobs.** `gorgias-pp-cli gorgias-jobs create` returns the new job's id but doesn't poll for completion or persist it in a local ledger. If you need synchronous behavior, call `gorgias-jobs get <id>` in a loop yourself. Adding `--wait` is on the roadmap.

## Gorgias API gotchas

A few non-obvious behaviors of the Gorgias API itself you'll hit if you exercise these endpoints directly:

- **`POST /views` requires `slug`, which is also marked DEPRECATED.** The deprecation label means the field is on its way out, not that it's optional today — omit it and you get `400 "Missing data for required field"`. Pass any URL-safe string.
- **`POST /views` filter DSL only accepts a fixed whitelist of `ticket.*` paths**, not arbitrary `ticket.<anything>`. Supported: `assignee_team.id`, `assignee_user.id`, `customer.id`, `messages.integration_id`, `channel`, `language`, `status`, `priority`, `store_id`, `custom_fields`, `customer.custom_fields`. Anything else returns 400 with the full list in the error.
- **`POST /integrations` with `type: "http"` requires `http.url`, `http.method`, `http.request_content_type`, and `http.response_content_type`.** The docs treat `http` as an opaque object; these requirements are visible only in an example body, not the field reference.
- **`POST /rules` rejects the `code` field unless it matches Gorgias's internal AST grammar.** Plain JavaScript is rejected even when syntactically complete. The grammar isn't fully documented; if you need to programmatically create rules, pass `code_ast` (a pre-parsed AST) and confirm the shape with Gorgias support.
- **`POST /tickets` requires `messages[0].source.from`** even when `from_agent: true`. Omitting it returns `400 "From field is missing or empty"`. Pass the agent's outbound address.
- **`DELETE /custom-fields/{id}` returns HTTP 405 Method Not Allowed.** The Gorgias API has no path to delete custom fields. Archive them via the admin UI; programmatic cleanup isn't possible. Plan create-once-and-keep accordingly.
- **`POST /tickets` outbound dispatch fails silently if `source.from.address` doesn't match the integration's `meta.address`.** The create returns 201 and the message is processed, but `sent_datetime` stays null and `last_sending_error` records `"No integration was found to send this email."` Always pair `integration_id` with a `source.from.address` that matches `GET /integrations/{id}.meta.address`. Watch out: a 201 does not mean the email was delivered.

## Unique Features

These capabilities aren't available in any other tool for this API.
- **`gorgias-pp-cli doctor --json`** — Probes /account with the configured credentials and reports `credentials: valid` only when an authenticated call succeeds.

  _Saves the first-five-minutes credential-debug cycle when wiring up an agent._

  ```bash
  gorgias-pp-cli doctor --json
  ```
- **`gorgias-pp-cli sync --resources tickets --since 7d && gorgias-pp-cli search 'refund' --agent`** — Syncs API data to a local SQLite DB so subsequent searches, analytics, and joins run without hitting the API.

  _Makes repeated agent-driven lookups (e.g. searching for similar past tickets) practical at scale._

  ```bash
  gorgias-pp-cli sync --resources tickets --since 30d --json
  ```

## Usage

Run `gorgias-pp-cli --help` for the full command reference and flag list.

## Commands

### account

Operations on account

- **`gorgias-pp-cli account get`** - Retrieve the current Gorgias account's metadata: subdomain, plan, billing state, and account-level flags. Use this to confirm credentials are wired up, detect the tenant/subdomain in a multi-tenant agent, or branch logic on plan tier.
- **`gorgias-pp-cli account settings-create`** - Create a new account-level settings record for the current Gorgias tenant. Use when bootstrapping a fresh tenant or when an integration needs to seed default settings flags (locale, business hours, branding) that don't exist yet.
- **`gorgias-pp-cli account settings-list`** - List the global settings on the current Gorgias account (business hours, language, default channels, notification preferences, etc.). Reach for this when an agent needs to honor tenant-wide configuration before composing a reply or routing a ticket.
- **`gorgias-pp-cli account settings-update`** - Update an account settings record by `id`. Use this to flip a tenant-wide flag, change business hours, or adjust a default channel — but only when the agent has authority to mutate account-level config (admin-grade operation).

### custom-fields

Operations on custom-fields

- **`gorgias-pp-cli custom-fields create`** - Define a new custom field on tickets or customers (the only supported `object_type` values). Required body: `object_type`, `label`, `definition` (the type-specific settings, e.g. boolean/number/text and any picklist values live inside `definition`). Optional: `description`, `priority`, `required`, `external_id`. Use to extend the schema, not to set a value on an existing record.
- **`gorgias-pp-cli custom-fields get`** - Fetch a single custom field definition by `id`, returning its data type, label, target object, and option list. Use to introspect schema before writing a value, especially to discover the legal enum options for picklist fields.
- **`gorgias-pp-cli custom-fields list`** - List custom field definitions for a single `object_type` (`Ticket` or `Customer` — REQUIRED query param). Optional: `search`, `archived`, `order_by`, `cursor`, `limit`. Call once per object type to discover what extensible schema exists before reading or writing values.
- **`gorgias-pp-cli custom-fields update`** - Update one custom field definition by `id` — relabel it, change its options, or toggle visibility. Note: this mutates the schema for every record that carries the field, so use sparingly and prefer per-record updates for one-off changes.
- **`gorgias-pp-cli custom-fields update-all`** - Bulk-update multiple custom field definitions in one call (no path id). Useful when reordering picklist options or applying the same label change across several fields; avoid unless the agent really needs a batched schema edit.

### customers

Operations on customers

- **`gorgias-pp-cli customers create`** - Create a new customer record. Pass `name`, `email`, optional `channels` (email/phone/social handles), and `data` for arbitrary key-value attributes. Use when an inbound message references a person who doesn't yet exist in Gorgias.
- **`gorgias-pp-cli customers custom-fields-list`** - List every custom field value attached to a single customer (`id`). Use to read CRM-style attributes (lifetime value, segment, loyalty tier) before deciding how to respond to or route a customer's ticket.
- **`gorgias-pp-cli customers custom-fields-set`** - Set a single custom field value on a customer: first `{id}` is the customer, second `{id}` is the custom field. Use for one-off mutations like flagging a VIP or recording a churn-risk score.
- **`gorgias-pp-cli customers custom-fields-set-all`** - Bulk-set custom field values on a single customer (`id`) — pass an array of field/value pairs. Preferred over the singular form when an agent needs to write several attributes at once after enriching a profile.
- **`gorgias-pp-cli customers custom-fields-unset`** - Clear a custom field value on a customer: first `{id}` is the customer ID, second `{id}` is the custom field ID. Use to unset (not delete) a per-customer attribute — the field definition itself remains.
- **`gorgias-pp-cli customers data-update`** - Set a customer's `data` blob (`id` in path). Body: `data` (required) plus optional `version` for last-write-wins (requests with an older version are ignored). Use when an integration pushes CRM context that should be displayed alongside the customer.
- **`gorgias-pp-cli customers delete`** - Delete one customer by `id`. Hard-deletes the record and may cascade to associated tickets/messages depending on account settings — reach for this only when handling GDPR-style erasure requests or scrubbing test data.
- **`gorgias-pp-cli customers delete-all`** - Bulk-delete customers. Required body: `ids` (array of customer IDs to delete). Does NOT accept query-style filters — you must enumerate the IDs explicitly. Reserve for cleanup jobs or compliance erasure; destructive and irreversible.
- **`gorgias-pp-cli customers get`** - Fetch a single customer by `id`, including their channels (email, phone, social handles), `data` blob, and account-level attributes. Use after identifying a customer (e.g. via search) to load full profile context.
- **`gorgias-pp-cli customers list`** - List customers with pagination and optional filter params (`email`, `external_id`, `name`, `language`, `channel_type`, `channel_address`, `view_id`). All params are optional. The agent's primary way to look up a customer by email or external system ID before reading tickets or sending a reply.
- **`gorgias-pp-cli customers merge`** - Merge one customer into another. Required query params: `source_id` (the duplicate, will be merged in and deleted) and `target_id` (the surviving customer). Body fields (channels, email, name, language, timezone, external_id) overwrite the target. Use when a duplicate is detected by email/phone; merges happen one pair at a time.
- **`gorgias-pp-cli customers update`** - Update a customer (`id`) — change name, add/remove channels, edit external IDs, or overwrite top-level fields. Use after merging records, fixing a typo, or syncing data from an external CRM.

### events

Operations on events

- **`gorgias-pp-cli events get`** - Retrieve a single audit event by `id` — captures who/what/when on ticket, customer, or settings mutations. Use to audit a specific change an agent or rule made, or to diagnose why a record looks the way it does.
- **`gorgias-pp-cli events list`** - List audit events. Documented filters: `object_type` (e.g. Ticket/Customer/User), `object_id`, `user_ids` (actor), `types` (event-type allowlist), `created_datetime` (with comparators), plus `cursor`/`limit`/`order_by`. Use to reconstruct a ticket's history or detect rule-driven changes.

### gorgias-jobs

Operations on jobs

- **`gorgias-pp-cli gorgias-jobs create`** - Kick off an asynchronous Gorgias job. Required body: `type` (enum: applyMacro, deleteTicket, exportTicket, importMacro, exportMacro, updateTicket, exportTicketDrilldown, exportConvertCampaignSalesDrilldown) and `params` (job-specific). Optional: `scheduled_datetime` (max 60 min in the future), `meta`. Poll with `gorgias-jobs_get` until the status leaves pending/running.
- **`gorgias-pp-cli gorgias-jobs delete`** - Delete a job record by `id`. Useful for cleaning up completed or failed entries from listings; does not cancel an in-flight job's side effects (the work it triggered may already be done).
- **`gorgias-pp-cli gorgias-jobs get`** - Fetch a single async job (`id`) with its status, progress, params, and result/error fields. The polling endpoint after `gorgias-jobs_create` — loop on this until the job is no longer in `pending`/`running`. Required: id.
- **`gorgias-pp-cli gorgias-jobs list`** - List async jobs with filters by type, status, and datetime. Use to find a recent export job by an agent or to surface stuck/failed jobs for retry.
- **`gorgias-pp-cli gorgias-jobs update`** - Update an async job (`id`) — typically to cancel it or adjust metadata. Reach for this only when you need to abort a long-running import/export rather than wait for it to complete.

### integrations

Operations on integrations

- **`gorgias-pp-cli integrations create`** - Install a new third-party integration on the Gorgias account (Shopify, Instagram, SMS provider, etc.). Pass `type` and provider-specific credentials. Use when an agent is asked to connect a new channel or external system, not to send data to one.
- **`gorgias-pp-cli integrations delete`** - Uninstall an integration by `id`. Destructive — disconnects the channel and may stop syncing orders/messages from that source. Use only when the user explicitly wants to remove the connection.
- **`gorgias-pp-cli integrations get`** - Fetch a single integration (`id`) including its type, status, last-sync time, and provider-specific config. Use to verify an integration is healthy before relying on its data (e.g. orders, social DMs).
- **`gorgias-pp-cli integrations list`** - List all installed integrations on the account — Shopify, Magento, Facebook, voice, etc. Use to discover what external systems an agent can pull context from before composing a reply.
- **`gorgias-pp-cli integrations update`** - Update an integration's config (`id`) — refresh credentials, toggle sync features, or rename. Reach for this when an integration is failing auth or needs a feature flag flipped.

### macros

Operations on macros

- **`gorgias-pp-cli macros archive`** - Archive one or more macros (soft delete) — pass macro IDs in the body. Use this rather than `macros_delete` to preserve history and make the macro reversible via `macros_unarchive`.
- **`gorgias-pp-cli macros create`** - Create a new macro: a reusable reply/action template. Required body: `name`. Optional: `intent`, `language`, `external_id`, and `actions` (array of action objects — this is where reply text, tag adds, status changes, etc. live, including any `{{variable}}` placeholders). Use to codify a common response so humans (and other agents) can apply it later.
- **`gorgias-pp-cli macros delete`** - Delete a macro by `id`. Hard-deletes it from the macro library. Prefer `macros_archive` for soft removal so historical references remain meaningful. Required: id. Destructive.
- **`gorgias-pp-cli macros get`** - Fetch a single macro by `id`, returning its body, actions, and variable definitions. Use before applying a macro so the agent can preview the rendered text and required variable values.
- **`gorgias-pp-cli macros list`** - List all macros, with optional filters (archived, name). The agent's discovery endpoint for available canned replies and bulk actions — useful before composing a reply from scratch.
- **`gorgias-pp-cli macros unarchive`** - Unarchive one or more macros, restoring them to the active library. Pass macro IDs in the body. The companion to `macros_archive`.
- **`gorgias-pp-cli macros update`** - Update a macro (`id`) — edit its body, variables, tags-to-add, or action list. Use when an agent is refining a canned reply or adjusting the side-effects it triggers.

### messages

Operations on messages

- **`gorgias-pp-cli messages list`** - List messages account-wide, paginated. Supported filters are `ticket_id` only (plus `cursor`, `limit`, `order_by`); no channel/sender/datetime filtering at this endpoint. Prefer `tickets_messages-list` when you already know the ticket id.

### phone

Operations on voice-calls

- **`gorgias-pp-cli phone call-events-get`** - Fetch a single voice-call event by `id` — events capture call lifecycle (ringing, answered, hung-up, transferred). Use to drill into why a specific call ended a certain way.
- **`gorgias-pp-cli phone call-events-list`** - List voice-call lifecycle events. Documented filter is `call_id` only (plus `cursor`, `limit`). Use to inspect the event timeline for a specific call when debugging routing or hand-off behavior.
- **`gorgias-pp-cli phone call-recordings-delete`** - Delete a stored voice-call recording by `id`. Use to honor a customer privacy/erasure request or to scrub a test recording; the call metadata typically remains, only the audio blob is removed.
- **`gorgias-pp-cli phone call-recordings-get`** - Fetch metadata for a single call recording (`id`) — duration, URL, related call/ticket. Pair with `download_get_download` to retrieve the actual audio bytes.
- **`gorgias-pp-cli phone call-recordings-list`** - List voice-call recordings. Documented filter is `call_id` only (plus `cursor`, `limit`). Use to find the recording(s) attached to a specific call before reviewing or transcribing.
- **`gorgias-pp-cli phone calls-get`** - Fetch a single voice call (`id`) with direction, status, duration, participants, and the linked ticket. Use when an agent needs context on a specific phone interaction.
- **`gorgias-pp-cli phone calls-list`** - List voice calls, paginated. Documented filter is `ticket_id` only (plus `cursor`, `limit`, `order_by`). Use to surface calls linked to a specific ticket; richer filtering (direction/status/agent) is not exposed here.

### pickups

Operations on pickups

- **`gorgias-pp-cli pickups delete`** - Delete a pickup record by `id`. Counterpart to `pickups_create_pickups`; use to cancel or remove a stale logistics pickup entry.

### reporting

Operations on stats

- **`gorgias-pp-cli reporting stats`** - Run a Gorgias analytics query: POST a JSON body with `metric`, `dimensions`, `filters`, and a `period`. The single endpoint for dashboards and report-style questions like 'tickets resolved by team last week' or 'first-response time by channel'.

### rules

Operations on rules

- **`gorgias-pp-cli rules create`** - Create a new automation rule. Required body: `name` and `code` (the rule logic written as JavaScript). Optional: `event_types` (e.g. ticket-created, ticket-updated), `priority`, `description`, `code_ast` (ESTree AST). Use to codify a workflow that the helpdesk evaluates on events; the conditions and actions are both expressed inside the JavaScript `code` string, not as a structured tree.
- **`gorgias-pp-cli rules delete`** - Delete an automation rule by `id`. Stops the rule from firing on future tickets but does not undo past actions. Use when retiring obsolete workflow logic.
- **`gorgias-pp-cli rules get`** - Fetch a single automation rule (`id`) with its full conditions/actions tree and enabled state. Use to inspect why a ticket was auto-modified or before tweaking rule logic.
- **`gorgias-pp-cli rules list`** - List all automation rules with their order, enabled state, and summary. The agent's map of what automations are currently shaping tickets, useful before adding new logic or diagnosing unexpected behavior.
- **`gorgias-pp-cli rules set-priorities`** - Set the execution priorities of automation rules. Required body: `priorities` — an array of objects mapping rule ids to their new priority value. Use after adding/reordering rules so they short-circuit in the intended order.
- **`gorgias-pp-cli rules update`** - Update an automation rule (`id`) — edit conditions, actions, or enabled flag. Use to tune an existing workflow rather than deleting and recreating it.

### satisfaction-surveys

Operations on satisfaction-surveys

- **`gorgias-pp-cli satisfaction-surveys create`** - Create a satisfaction-survey instance attached to one ticket and customer. Required body: `customer_id`, `ticket_id`. Optional: `score` (1–5), `body_text` (customer comment), `should_send_datetime` (set to `null` to skip sending). Use to manually attach or backfill a CSAT result on a ticket — NOT to define a reusable survey template (Gorgias's CSAT templates are managed via integrations/settings, not this endpoint).
- **`gorgias-pp-cli satisfaction-surveys get`** - Fetch a single satisfaction-survey instance by `id` — the linked ticket/customer, score, customer comment, and send/score timestamps. Use to read the CSAT result for a specific ticket. Required: id.
- **`gorgias-pp-cli satisfaction-surveys list`** - List satisfaction-survey instances (each one tied to a single ticket). Filter with `ticket_id` to fetch the survey for one ticket, or paginate via `cursor`/`limit`. Use for CSAT reporting and to surface scores per ticket.
- **`gorgias-pp-cli satisfaction-surveys update`** - Update a satisfaction-survey instance (`id`) — typically to record/correct the customer's `score` (1–5), `body_text`, or to schedule/cancel its send via `should_send_datetime`. There is no template wording or trigger logic at this endpoint. Required: id.

### tags

Operations on tags

- **`gorgias-pp-cli tags create`** - Create a new tag in the account's tag library. Body: `name` (required, max 256 chars, case-sensitive), `description` (optional, max 1024), `decoration` (optional, styling object). Use when the agent needs a new label that doesn't exist yet — prefer reusing an existing tag where possible.
- **`gorgias-pp-cli tags delete`** - Delete a tag by `id`. Removes it from the library and unassociates it from every ticket/customer that carries it. Destructive — prefer merging into another tag if you want to preserve history.
- **`gorgias-pp-cli tags delete-all`** - Bulk-delete tags. Required body: `ids` (array of tag IDs, min 1). Tags currently referenced by macros or rules cannot be deleted, and views using them will be deactivated. Reserve for housekeeping; destructive.
- **`gorgias-pp-cli tags get`** - Fetch a single tag (`id`) with its name, decoration, and metadata. Use to verify a tag exists before applying it, or to read its display style.
- **`gorgias-pp-cli tags list`** - List all tags in the account, optionally filtered by name. The agent's lookup endpoint for finding the right existing tag (and avoiding duplicates) before tagging a ticket or customer.
- **`gorgias-pp-cli tags merge`** - Merge other tags INTO this tag — path `{id}` is the destination (surviving) tag, and the body field `source_tags_ids` (array of integer IDs) lists the source tags to be merged and deleted. Use to consolidate duplicate or near-duplicate labels. Required: id.
- **`gorgias-pp-cli tags update`** - Update a tag (`id`) — rename it or change its color/decoration. Affects every record currently carrying the tag, so use carefully on widely-applied labels.

### teams

Operations on teams

- **`gorgias-pp-cli teams create`** - Create a new team (group of agents) in the account. Pass `name` and optionally members. Use when organizing routing or stats by squad — e.g. 'Tier-1 Support', 'Billing'.
- **`gorgias-pp-cli teams delete`** - Delete a team by `id`. Removes it from routing rules and views; members remain but lose the team grouping. Use when retiring a squad structure.
- **`gorgias-pp-cli teams get`** - Fetch a single team (`id`) with its members and metadata. Use when an agent needs to know who's on a team before assigning or escalating a ticket.
- **`gorgias-pp-cli teams list`** - List all teams in the account. The agent's lookup for valid team IDs/names when assigning a ticket, routing via a rule, or filtering reports.
- **`gorgias-pp-cli teams update`** - Update a team (`id`) — rename it or change its membership. Use to reorganize agents or correct a misconfigured team.

### ticket-search

Search across tickets, customers, messages, etc.

- **`gorgias-pp-cli ticket-search query`** - Full-text search across Gorgias tickets, customers, and messages. POST a JSON body with `query`, `resource_type`, and optional `filters`. The agent-friendly path to find a prior conversation by topic or customer email when you only have natural-language search terms.

### tickets

Operations on tickets

- **`gorgias-pp-cli tickets create`** - Create a new ticket. Body specifies `channel`, `via`, `subject`, an initial `messages` array, the customer, and optional assignee/tags/status. Use when the agent is opening a fresh conversation rather than replying to an existing one.
- **`gorgias-pp-cli tickets custom-fields-list`** - List every custom field value on ticket (`id`). Use to read structured metadata an agent or integration attached (e.g. RMA number, refund reason) before composing context-aware replies.
- **`gorgias-pp-cli tickets custom-fields-set`** - Set a single custom field value on a ticket: first `{id}` is the ticket, second `{id}` is the custom field. Use to write a structured attribute (e.g. refund amount, order number) onto a specific ticket.
- **`gorgias-pp-cli tickets custom-fields-set-all`** - Bulk-set custom field values on ticket (`id`) — pass an array of field/value pairs. Preferred when an agent needs to write several structured attributes at once after triaging a ticket.
- **`gorgias-pp-cli tickets custom-fields-unset`** - Clear a custom field value on a ticket: first `{id}` is the ticket, second `{id}` is the custom field. Unsets (does not delete the schema) — use to revert an incorrectly auto-populated value.
- **`gorgias-pp-cli tickets delete`** - Delete a ticket by `id`. Hard-deletes the conversation and its messages — reserve for GDPR erasure, spam, or accidental tickets. Most workflows prefer setting status to `closed` instead.
- **`gorgias-pp-cli tickets get`** - Fetch a single ticket by `id` with status, channel, assignee, customer, tags, and summary fields. Use after identifying a ticket (via search/list) to load core context before reading messages or replying.
- **`gorgias-pp-cli tickets list`** - List tickets with filters (status, assignee, customer, channel, datetime, tag). The agent's primary endpoint for queue scans like 'open tickets assigned to me' or 'all tickets for customer X'; prefer search for natural-language queries.
- **`gorgias-pp-cli tickets messages-create`** - Post a new message on ticket (`id`) — used to reply to the customer or write an internal note. The body distinguishes public ('outgoing' to channel) from internal ('internal-note') via fields like `sender`, `channel`, `via`, and `body_html`/`body_text`. Reach for this when the agent decides to respond.
- **`gorgias-pp-cli tickets messages-delete`** - Delete a message from a ticket: first `{id}` is the ticket, second `{id}` is the message. Use sparingly — typically only to scrub a message containing sensitive data or an accidental send.
- **`gorgias-pp-cli tickets messages-get`** - Fetch a single message: first `{id}` is the ticket, second `{id}` is the message. Use to load full body and attachment details for a specific entry without pulling the whole thread.
- **`gorgias-pp-cli tickets messages-list`** - List all messages on ticket (`id`) in chronological order — both customer-sent and agent-sent, public and internal notes. The agent's primary read endpoint for understanding the full conversation context.
- **`gorgias-pp-cli tickets messages-update`** - Update a message: first `{id}` is the ticket, second `{id}` is the message. Typically used to edit an internal note's body or correct a draft; channel-delivered messages may be immutable depending on channel.
- **`gorgias-pp-cli tickets tags-add`** - Add one or more tags to ticket (`id`). The body shape (tag IDs vs names; whether unknown names auto-create) is not confirmed against the dev docs — verify before relying on auto-create behavior. Use to categorize a ticket once the agent identifies its topic. Required: id.
- **`gorgias-pp-cli tickets tags-list`** - List the tags currently attached to ticket (`id`). Use to read the ticket's categorization before deciding what additional tags to add or what rule branch to take.
- **`gorgias-pp-cli tickets tags-remove`** - Remove tags from ticket (`id`). Pass the tag IDs/names to detach. Use when re-categorizing a ticket or undoing an over-eager auto-tag.
- **`gorgias-pp-cli tickets tags-replace`** - Replace ticket (`id`)'s entire tag set with the supplied list. Use for full re-tagging; for additive/subtractive changes prefer the `create_tags` / `delete_tags` ticket endpoints.
- **`gorgias-pp-cli tickets update`** - Update a ticket (`id`) — change status (`open`/`closed`/`resolved`), assignee, priority, subject, or `via`. The workhorse for state transitions: closing after resolution, reassigning to a team, escalating priority.

### users

Operations on users

- **`gorgias-pp-cli users create`** - Create a new user (Gorgias agent/operator). Pass name, email, role, and optionally team memberships. Use when provisioning a new support agent — typically an admin-only operation.
- **`gorgias-pp-cli users delete`** - Delete a user (`id`) — deactivates the agent account and removes them from routing. Their historical ticket activity remains. Reach for this when an agent leaves the org.
- **`gorgias-pp-cli users get`** - Fetch a single user (`id`) — agent name, email, role, teams, status. Use to look up who an assignee is or to verify a user's role before assigning sensitive tickets.
- **`gorgias-pp-cli users list`** - List users (Gorgias agents/operators) on the account, with filters for role, status, and team. The agent's lookup endpoint for valid assignee IDs before reassigning or routing a ticket.
- **`gorgias-pp-cli users update`** - Update a user (`id`) — change role, name, team membership, or active state. Use for admin operations like promoting an agent to lead or moving someone between teams.

### views

Operations on items

- **`gorgias-pp-cli views create`** - Create a saved view — a filtered ticket list (e.g. 'My open tickets', 'Urgent + unassigned') defined by status/tag/assignee/channel criteria. Use when an agent is asked to materialize a recurring query as a reusable filter.
- **`gorgias-pp-cli views delete`** - Delete a saved view by `id`. Removes it from the sidebar for everyone who saw it. Use when retiring stale filters.
- **`gorgias-pp-cli views get`** - Fetch a single saved view (`id`) with its filter definition and metadata. Use to introspect what conditions a view encodes before relying on its results or editing it.
- **`gorgias-pp-cli views items-list`** - Return the ticket items currently matching saved view (`id`). Required: `id` (path). Optional: `cursor`, `direction` (prev/next), `limit` (1-100, default 30), `order_by`, `ignored_item`. Use to read 'what's in this view right now' rather than re-deriving the filter manually.
- **`gorgias-pp-cli views items-update`** - Update the materialized items of a view (`id`) — used to reorder, bulk-mutate, or refresh the cached set depending on view type. Niche; most agents read items rather than mutating them.
- **`gorgias-pp-cli views list`** - List all saved views on the account, including ownership and visibility. The agent's catalogue of pre-built ticket filters available for navigation or reporting.
- **`gorgias-pp-cli views update`** - Update a saved view (`id`) — change its filter criteria, name, or sharing. Use to evolve a view's definition as triage workflows change.

### widgets

Operations on widgets

- **`gorgias-pp-cli widgets create`** - Create a new agent-facing sidebar widget shown inside the Gorgias helpdesk (on ticket, customer, or user views — set by `context`). Required: `template` (defines the data source, e.g. Shopify, Stripe, HTTP). Optional: `order`, `integration_id` (required for HTTP), `app_id`, `deactivated_datetime`. This is NOT a customer-facing chat widget — those are managed via the Gorgias Chat integration.
- **`gorgias-pp-cli widgets delete`** - Delete a sidebar widget config by `id`. After deletion the widget stops rendering in the helpdesk UI on the configured `context` (ticket/customer/user). Coordinate with the team relying on the data surface. Required: id. Destructive.
- **`gorgias-pp-cli widgets get`** - Fetch a single sidebar widget (`id`) with its `context` (ticket/customer/user), `template` (data source), order, and integration linkage. Use to introspect a helpdesk sidebar widget before editing it. Required: id.
- **`gorgias-pp-cli widgets list`** - List all agent-facing sidebar widgets on the account, optionally filtered by `integration_id` or `app_id`. Use to discover which Shopify/Stripe/HTTP-backed sidebar surfaces exist on ticket/customer/user views before editing one. NOT a chat-widget listing.
- **`gorgias-pp-cli widgets update`** - Update a sidebar widget (`id`) — typically to change its `template` (data source), `order` (display position), `context`, or to deactivate it via `deactivated_datetime`. Affects what agents see in the helpdesk sidebar. NOT a customer-facing chat widget. Required: id.


## Output Formats

```bash
# Human-readable table (default in terminal, JSON when piped)
gorgias-pp-cli account get

# JSON for scripting and agents
gorgias-pp-cli account get --json

# Filter to specific fields
gorgias-pp-cli account get --json --select id,name,status

# Dry run — show the request without sending
gorgias-pp-cli account get --dry-run

# Agent mode — JSON + compact + no prompts in one flag
gorgias-pp-cli account get --agent
```

## Agent Usage

This CLI is designed for AI agent consumption:

- **Non-interactive** - never prompts, every input is a flag
- **Pipeable** - `--json` output to stdout, errors to stderr
- **Filterable** - `--select id,name` returns only fields you need
- **Previewable** - `--dry-run` shows the request without sending
- **Explicit retries** - add `--idempotent` to create retries and `--ignore-missing` to delete retries when a no-op success is acceptable
- **Confirmable** - `--yes` for explicit confirmation of destructive actions
- **Piped input** - write commands can accept structured input when their help lists `--stdin`
- **Offline-friendly** - sync/search commands can use the local SQLite store when available
- **Agent-safe by default** - no colors or formatting unless `--human-friendly` is set

Exit codes: `0` success, `2` usage error, `3` not found, `4` auth error, `5` API error, `7` rate limited, `10` config error.

## Use with Claude Code

Install both binaries (see [Install](#install)), then register the MCP server with Claude Code:

```bash
claude mcp add gorgias gorgias-pp-mcp \
  -e GORGIAS_USERNAME=<your-email> \
  -e GORGIAS_API_KEY=<your-api-key> \
  -e GORGIAS_BASE_URL=https://<tenant>.gorgias.com/api
```

Claude Code can also drive the CLI directly via its bash tool — call `gorgias-pp-cli agent-context --json` first so the agent knows the surface.

## Use with Claude Desktop

This CLI ships an [MCPB](https://github.com/modelcontextprotocol/mcpb) bundle — Claude Desktop's standard format for one-click MCP extension installs (no JSON config required).

To install:

1. Download the `.mcpb` for your platform from the latest GitHub Release of [chrisyoungcooks/gorgias-pp-cli](https://github.com/chrisyoungcooks/gorgias-pp-cli/releases).
2. Double-click the `.mcpb` file. Claude Desktop opens and walks you through the install.
3. Fill in `GORGIAS_USERNAME` when Claude Desktop prompts you.

Requires Claude Desktop 1.0.0 or later. Pre-built bundles ship for macOS Apple Silicon (`darwin-arm64`) and Windows (`amd64`, `arm64`); for other platforms, use the manual config below.

<details>
<summary>Manual JSON config (advanced)</summary>

If you can't use the MCPB bundle (older Claude Desktop, unsupported platform), install the MCP binary and configure it manually.


Install the MCP binary (see [Install](#install) — `go install ...gorgias-pp-mcp@latest` or the pre-built release attachment).

Add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

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

</details>

## Health Check

```bash
gorgias-pp-cli doctor
```

Verifies configuration, credentials, and connectivity to the API.

## Configuration

Config file: `~/.config/gorgias-pp-cli/config.toml`

Static request headers can be configured under `headers`; per-command header overrides take precedence.

Environment variables:

| Name | Kind | Required | Description |
| --- | --- | --- | --- |
| `GORGIAS_USERNAME` | per_call | Yes |  |
| `GORGIAS_API_KEY` | per_call | Yes | Set to your API credential. |

## Troubleshooting
**Authentication errors (exit code 4)**
- Run `gorgias-pp-cli doctor` to check credentials
- Verify the environment variable is set: `echo $GORGIAS_USERNAME`
**Not found errors (exit code 3)**
- Check the resource ID is correct
- Run the `list` command to see available items

### API-specific

- **doctor reports `api: reachable (HTTP 404 at /)` but `credentials: valid`** — Expected — the Gorgias root path doesn't route. The auth probe runs against `/account` (verify_path) and that's what 'credentials: valid' confirms.
- **All commands return `404 Not Found` at `your-company.gorgias.com`** — Your `GORGIAS_BASE_URL` isn't being picked up. Verify with `printenv GORGIAS_BASE_URL` or run `gorgias-pp-cli doctor`.
- **MCP server starts but agent only sees `gorgias_search`/`gorgias_execute`/`context` tools** — That's the code-orchestration MCP surface — by design. The full 108-endpoint surface is reachable through `gorgias_execute` (and discoverable via `gorgias_search`) without burning context on tool descriptions. See the "MCP design" section.
- **`gorgias-pp-cli search refund` returns nothing** — Gorgias's POST `/search` indexes customers/agents/tags/teams/integrations — NOT tickets or messages. For ticket text search, sync first and pass `--data-source local`:

  ```bash
  gorgias-pp-cli sync --resources tickets --since 30d
  gorgias-pp-cli search refund --data-source local
  ```

- **HTTP 400 "Must be at most 100" on a list** — Gorgias caps `--limit` at 100. The CLI passes it through; paginate via `--cursor <meta.next_cursor>` for more rows.
- **HTTP 400 on `customers list --language en`** — Gorgias rejects `language`/`timezone` filters when combined with `cursor`/`limit`/`order-by`. Drop the pagination flags or use `--name`/`--email` instead.
- **HTTP 400 on `events list --object-type Ticket`** — Gorgias requires `--object-id` alongside `--object-type`. Provide both.
- **Rate limited (exit 7)** — Gorgias enforces per-account rate limits. Slow down (`--rate-limit 2`) or fetch from the local mirror after `sync`.
- **`workflow archive` returns empty results** — Run `gorgias-pp-cli sync --resources <resource>` first. Compound workflows query the live API by default, but a follow-up `analytics`/`search` on the local mirror needs a populated DB.
- **Local data feels stale** — Set `GORGIAS_AUTO_REFRESH_TTL=15m` to have read commands sync before serving when the mirror is older than the TTL, or run `gorgias-pp-cli sync --full` to wipe + rebuild.

### Agent runtime discovery

Three commands let an agent introspect the CLI without parsing `--help`:

```bash
# Full machine-readable descriptor (commands, flags, auth, novel features).
gorgias-pp-cli agent-context --json

# Resolve a capability to the best matching command.
gorgias-pp-cli which "search messages for a customer"
gorgias-pp-cli which "list cancellations from yesterday"

# Browse all API endpoints by resource.
gorgias-pp-cli api
```

The MCP server exposes the same three via the `context` / `which` / `api` tools.

---

Generated by [CLI Printing Press](https://github.com/mvanhorn/cli-printing-press)
