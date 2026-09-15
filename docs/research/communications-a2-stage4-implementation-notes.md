# SMS Conversations — implementation observations

Status: Unapproved technical observations retained from the earlier mixed draft.
Read only when implementation planning begins, after product behavior is settled.
These notes neither define feature scope nor authorize code changes; recheck current code before use.
Product proposal: `docs/research/communications-a2-stage4-conversations-plan.md`.

## Exact screen and reuse boundary

Extend `src/routes/(app)/communications/+page.svelte`: existing inbox scope/list, mixed history and client
context remain. SMS joins the channel chooser and timeline; do not create a separate SMS inbox or redesign
unrelated email, website chat, assignment, followers, archive or internal comments.

- Keep the existing email `ConversationComposer.svelte` and `WebsiteChatComposer.svelte`. Add a narrow SMS
  composer; share controls and send-result contracts, not email-only subject/attachment/retry assumptions.
- Reuse `SnippetPickerButton.svelte`, `ConversationAssignField.svelte`, shared Button/Textarea/Select/Tabs,
  Badge, Dialog and toast components. Extend `MessageDetailsDialog.svelte` with channel-specific detail rather
  than exposing fake email fields. Media reuse depends on the decision below.
- Use Bits UI-backed tabs/selects/dialogs, Svelte 5, component SCSS/BEM, Tabler icons and current semantic tokens.
  Keyboard focus and disabled explanations remain available. No token changes or high-fidelity redesign here.
- Existing right-panel client/contact-method editing is the reuse target; no new contact editor or role system.
  Sender assignment/access requirements belong in Stage 6 settings and must be available before selector proof.

## Data and performance design

The current page groups the latest 50 message rows into contacts and offers no older-history loading. SMS cannot
reuse that as the complete inbox: one busy contact can displace every other conversation. This is a required
read-path change, not a general cache rewrite.

Use a permission-filtered, cursor-paged conversation-summary list and a separately cursor-paged selected-contact
history. Reuse current organization/contact authorization. Keep selection keyed by contact when sort position
changes; loading older messages preserves the scroll anchor. Return narrow summaries rather than all bodies.
Stable sort keys need an ID tie-breaker; overlapping page updates dedupe by durable message identity. No full-history
browser grouping, unbounded RPC result or per-row history fetch.

TanStack Query owns list/history/context/eligibility. Include organization, permission scope, filters and contact
where applicable in cache identity. Retain the SSR shell and CSR page; loading data never blocks navigation.
Reuse the existing private organization broadcast and permission-filtered rereads. Coalesce bursts, remember
invalidation during in-flight sends, and refresh on reconnect; do not drop events merely because a local send is
pending. Clean up subscriptions. Invalidate client Communication history and applicable eligibility/balance queries
as well as the inbox after changes. No message bodies or financial data in broadcasts; no new polling transport.

Performance verdict: the design shape is required by growing conversations/history and bounded by page size;
exact query plans, retained-history distribution, active viewers and callback rate remain unmeasured. Build proof
must measure rows scanned, payload bytes, requests per event, database latency, rendered rows, scroll behavior
and p95/p99 read latency with 200 test tenants, a hot contact, concurrent email/SMS and realistic history. Choose
indexes from actual predicates/order after schema review. Capacity is not established. Media adds a separate
bytes/storage/scan/download growth path only if approved below.

