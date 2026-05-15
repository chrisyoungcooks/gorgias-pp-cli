# Known gaps

Honest documentation of where this CLI's coverage is incomplete. The
[main README](./README.md) keeps things tight; this file is the long form.

## Write-endpoint coverage

All 37 write endpoints (POST/PUT/DELETE) have URL routing + HTTP method
verified via `scripts/writes-shipcheck.sh` (a `--dry-run` matrix). Live
coverage on top of that breaks down as follows.

- **18 endpoints fully roundtripped in CI.** `tags`, `macros`, `teams`,
  `views`, `widgets`, and `integrations` — each of create/update/delete
  — are exercised by `scripts/writes-live-shipcheck.sh`. Every successful
  create is paired with a delete on the same path; a failed run may leave
  one row behind, all rows are named with a unique marker prefix so manual
  cleanup is trivial.
- **3 endpoints verified once manually.** `tickets` create/update/delete.
  Not in recurring CI because creating real tickets risks customer-facing
  email if a test environment isn't isolated.
- **4 endpoints verified once.** `customers` and `custom-fields`
  create/update via `scripts/writes-verify-once.sh`. Leaves admin-UI
  debris rows that need manual retiring; not safe for CI.
- **12 endpoints stay dry-run-only.** Live verification isn't possible
  against production without unacceptable risk:
  - `customers delete` — cascades through ticket history
  - `users create/update/delete` — invitation emails / seat consumption / lockouts
  - `satisfaction-surveys create/update` — attaches a CSAT score to a real ticket
  - `gorgias-jobs create/update/delete` — async bulk operations
  - `rules create/update/delete` — DSL gate plus auto-fire risk on real tickets
  A sandbox tenant would close this gap; until then they're documented and
  exercised in dry-run form only.

## Other coverage gaps

- **Phone/voice integration.** Tenants without a voice integration have
  no calls in these endpoints, so `phone calls-list`,
  `phone call-events-list`, and `phone call-recordings-list` haven't been
  verified live. The wire-shape is generated from the same spec as
  everything else; failure modes are likely small but unconfirmed.
- **Global `/messages` endpoint** supports only the `ticket_id` filter —
  no datetime range, no channel filter. Use
  `tickets messages-list <ticket-id>` for per-ticket views.
- **Live `search`** uses Gorgias's `POST /search`, which indexes
  customers, agents, tags, teams, and integrations — **not tickets or
  messages**. For ticket/message text search, sync to local first and
  use `gorgias-pp-cli search <query>` against the FTS5 mirror.
- **Customer-list filter incompatibilities.** `--language` and
  `--timezone` are mutually exclusive with `--cursor`/`--limit`/
  `--order-by` on `/customers` (server-side; undocumented in OpenAPI).
  Pick one approach per call.
- **No `--wait` for async jobs.** `gorgias-pp-cli gorgias-jobs create`
  returns the new job's id but doesn't poll for completion or persist it
  in a local ledger. If you need synchronous behavior, call
  `gorgias-jobs get <id>` in a loop yourself. Adding `--wait` is on the
  roadmap.
