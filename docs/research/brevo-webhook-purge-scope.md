# Brevo webhook purge scope

Research date: 2026-08-28

## Question

In UCRM's single shared Brevo account, are transactional and inbound email webhooks owned by a CRM organization, and should organization purge slice 8.4 add per-organization webhook cleanup?

## Current Brevo model

- Brevo's webhook collection is scoped to the authenticated Brevo account. `GET /v3/webhooks` says it retrieves all webhooks from the account and offers only `type` and sort filters; there is no organization, customer, tag, sender, or sender-domain filter. [Get all webhooks](https://developers.brevo.com/reference/get-webhooks)
- A webhook is created with a URL, events, type, and optional delivery/security settings. The API exposes no application-tenant or customer ownership field. Transactional webhooks also have no sender-domain scope. [Create a webhook](https://developers.brevo.com/reference/create-webhook)
- Brevo deletes a webhook solely by its numeric webhook ID. Deleting a shared transactional webhook would stop notifications for the whole Brevo account, including other UCRM organizations. [Delete a webhook](https://developers.brevo.com/reference/delete-webhook)
- Inbound parsing is the important exception to the word *shared*: an inbound-type webhook must specify one receiving `domain`. Brevo still has no concept of the UCRM organization, but an application can make that webhook organization-owned by provisioning it for the organization's receiving domain and persisting the returned webhook ID. Multiple such webhook objects may point to the same UCRM endpoint URL. [Inbound parse webhooks](https://developers.brevo.com/docs/inbound-parse-webhooks), [get webhook details](https://developers.brevo.com/reference/get-webhook)
- True provider-side tenant boundaries are available through Brevo Enterprise sub-accounts, which Brevo describes as independent and gives separate API keys. UCRM currently uses one platform account instead. [Brevo sub-account model](https://help.brevo.com/hc/en-us/articles/9003097317138-Classic-Admin-account-What-is-sub-accounts-management)

## UCRM evidence

UCRM currently exposes one fixed transactional callback route and one fixed inbound callback route, protected by platform environment tokens (`src/routes/api/webhooks/brevo/transactional/+server.ts:13-14`, `src/routes/api/webhooks/brevo/inbound/+server.ts:95-96`, `.env.example:29-30`). Transactional sends attach an internal intent tag so the shared callback can resolve the application record (`src/lib/server/communications/brevo.ts:244`).

The organization-scoped provider authority stores `provider_domain_id` and `provider_sender_id` on the domain and sender tables (`supabase/migrations/20260824005223_communications_domain_sender_authority.sql:10-57,100-135`). The Brevo adapter creates and deletes domains and senders, but contains no webhook create, list, or delete operation (`src/lib/server/communications/brevo.ts:96-163`). A repository-wide check found no provider webhook ID column, webhook ownership table, or per-organization webhook provisioning path.

## Recommendation for slice 8.4

Choose **option 1** and purge only provider resources UCRM currently provisions and can prove belong to the organization: domains and senders. Mark webhook cleanup `not_applicable`; do not list-and-guess or delete either shared platform webhook. This is the mature ownership rule: delete only resources with a durable, deterministic tenant ownership record.

Keep the clarification narrow: the contract's webhook requirement is a no-op for the current architecture, not a claim that Brevo can never have organization-associated inbound hooks. If UCRM later provisions one inbound webhook per organization receiving domain or adopts Brevo sub-accounts, store that webhook's opaque ID at provisioning time and include it in the same retryable provider-cleanup mechanism. Do not build that lifecycle in slice 8.4.
