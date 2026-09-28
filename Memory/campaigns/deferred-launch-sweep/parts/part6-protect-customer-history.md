# Part 6 — Protect customer history

**Campaign:** deferred-launch-sweep · **Plan:** `docs/client-property-behavior-contract.md`
**Code:** `main`
**Done when:** each of the four deferred notes is either fixed and browser-verified, or closed with the
evidence that it no longer applies.

## Steps

- [x] Check all four notes against the real code — two are largely obsolete (see Notes)
- [x] Research Jobber's real property-delete and property-transfer behavior (help centre; extension was offline)
- [x] Get Jafar's decisions (see Notes)
- [ ] Close `entitytype-covers-only-clients-and-properties` — already done, no code change
- [ ] Close `historical-address-safety-and-property-transfer-between-clients` — snapshots exist, transfer dropped
- [ ] Build the property-delete behavior (guard + cascade, see Notes for the agreed shape)
- [ ] Switch on client Archive + Restore (list page button is present but disabled)
- [ ] Give finance full invoice permissions and office view-only
- [ ] `npm run check`, then browser-verify on Raad LTD
- [ ] Add client merge as its own roadmap part (Jafar approved splitting it out)

## Next

Close the two obsolete notes first (delete the note file and its `Memory/deferred/INDEX.md` row), then write
the property-delete migration. Nothing is half-done; no code has been changed yet.

## Notes

**Jafar's decisions, 2026-09-28.** Split the part: property safety now, client merge becomes its own part.
Property delete: "copy Jobber exactly" — warn, then delete. Property transfer between clients: leave it out,
because Jobber deliberately has no such feature. Permissions: finance gets full invoices, office view-only.

**Two notes are obsolete and need no code.**
`entitytype-covers-only-clients-and-properties`: `EntityType` in `src/lib/collaboration/api.ts` now covers
client, property, request, quote, job_expense, job, visit; `tag_assignments_entity_type_check` covers the same
minus job_expense, and `file_links_entity_type_check` covers those plus invoice, branding and marketing.
`historical-address-safety-and-property-transfer-between-clients`: `quote_versions` already snapshots
`service_address_line1/2`, `service_city`, `service_state_region`, `service_postal_code`, and `invoices` has
`billing_address_snapshot`. Jobs, requests and visits read the address live, which is correct — a crew needs
today's address. The transfer half is dropped per Jafar.

**Jobber's real property-delete behavior** (https://help.getjobber.com/en/articles/properties/): deletion is
NOT blocked. "Deleting a property will delete associated quotes, jobs, and their associated estimate and price
figures", warned with "This data also won't be included in your reports", and unrecoverable. Jobber has no
property transfer; a request's property can only be changed to another property of the same client, and the
cross-client answer is to merge the clients.

**Why a literal Jobber cascade is impossible here, and what to build instead.** Three foreign keys are
deliberate `ON DELETE RESTRICT` money/history guards: `invoice_sources_job_fk` (an invoiced job),
`payment_stripe_checkouts_quote_fk` (a quote that took a deposit), and
`communication_delivery_intents_quote_fk` (a quote emailed to the customer). Copying Jobber exactly would mean
destroying Stripe checkout rows and the record that a customer was sent a quote. So: cascade what is safe —
unsent quotes and uninvoiced jobs with all their `CASCADE` children — and refuse when a sent quote, a paid
deposit, or an invoiced job is in the way, with a message naming what blocks it. `delete_property` today is a
soft delete (`deleted_at`) with no check at all, so those RESTRICT keys never fire and the property just hides
while its work still points at it. Invoices do not reference properties (they hang off the client, same as
Jobber), so invoices survive either way. **Report this limitation to Jafar in plain English.**

**Traps.** Browser testing needs the tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`;
hard-reload (Ctrl+Shift+R) if the page goes blank after a dev-server restart. The Chrome extension reported
"not connected" this session. Pre-existing unrelated failure:
`src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts`. Permission matrix lives in
`supabase/migrations/20260101000200_baseline_reference_data.sql`.
