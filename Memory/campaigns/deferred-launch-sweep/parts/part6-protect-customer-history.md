# Part 6 — Protect customer history

**Campaign:** deferred-launch-sweep · **Plan:** `docs/client-property-behavior-contract.md`
**Code:** `main`
**Done when:** each of the four deferred notes is fixed and browser-verified, or closed with evidence that it
no longer applies.

## Steps

- [x] 6A — closed the two obsolete notes; finance invoice permissions applied (`95680990`), browser-verified
      on Raad LTD, plus the write-button gating bug it exposed (`d2fea540`)
- [ ] 6B — client archive + restore
- [ ] 6C — property cascade delete (destructive; read Notes first)
- [x] Add client merge as roadmap Part 10

## Next

**6B, recommended next.** `clients.archived_at` and the `customers.archive` permission already exist (admin and
office hold it). Three affordances in `src/routes/(app)/clients/+page.svelte` are disabled behind `bulkReason`
"Not ready yet — this arrives once clients carry work": the row menu's "Archive" item, and the bulk Archive and
bulk Delete buttons. Needs an API endpoint, a way to see and restore archived clients (the list hard-filters
`archived_at is null`; the status filter offers only lead/customer), and a decision from Jafar on whether a
client with unpaid invoices can be archived. Jobber gates archiving behind an `isArchivable` flag whose rule is
not documented.

No code is half-done. The permissions migration is applied, verified live, and committed.

## Notes

**Jafar's decisions, 2026-09-28.** Split the part; client merge becomes its own part. Property delete: copy
Jobber exactly (warn, then delete). Property transfer between clients: leave out, Jobber has no such feature.
Permissions: finance full invoices, office view-only.

**Why the two notes closed with no code.** `EntityType` in `src/lib/collaboration/api.ts` now covers client,
property, request, quote, job_expense, job, visit; `tag_assignments_entity_type_check` the same minus
job_expense; `file_links_entity_type_check` those plus invoice, branding and marketing. And `quote_versions`
already snapshots the service address while `invoices` has `billing_address_snapshot`, so customer paperwork
cannot rewrite itself. Jobs, requests and visits read the address live, which is correct — a crew needs today's
address.

**6C design.** Jobber's behavior is recorded permanently in `.claude/skills/jobber/jobber-01-clients-properties.md`
§ 2.2a, including which of our foreign keys make a literal copy impossible — read that first. Beyond it: the
delete must become a hard delete (Jobber's is unrecoverable), notes, tags, files and activity events point at a
property polymorphically with no foreign key so they orphan and must be cleared explicitly, and `delete_property`
is currently not `SECURITY DEFINER` and leans on RLS — `delete_quote` in the same baseline file is the pattern to
copy for an in-function permission check. Decided on least-privilege grounds, not Jafar's call: the caller must
also hold `quotes.edit` when quotes exist and `jobs.edit` when jobs exist, so nobody destroys work they could not
delete directly. Keep the existing promotion of a replacement primary — a deferred check requires a client with
properties to have exactly one primary.

**Traps.** Browser testing needs the tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`;
hard-reload if the page blanks after a dev-server restart. The Chrome extension reported "not connected" this
session. Pre-existing unrelated failure: `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts`.
