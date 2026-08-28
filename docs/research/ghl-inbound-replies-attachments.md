# HighLevel inbound replies and attachments — Part 4 evidence

Research date: 2026-08-25  
Scope: Net-new first-party HighLevel evidence needed for Communications Part 4. This note supplements, rather than repeats, `ghl-email-gap-review.md` and `ghl-unified-inbox-reference.md`.  
Evidence labels: **Fact** is stated in a cited HighLevel source; **UCRM contract** is already approved locally; **Undocumented** means the reviewed first-party sources do not establish the behavior.

## Conclusion

Part 4 can copy HighLevel's visible reply model: a reply to a UCRM-originated email returns to the contact's conversation, preserves email-thread context, exposes attachments in Conversations, and can trigger reply-specific automation. UCRM's existing contract already supplies the security and tenant-isolation guarantees that HighLevel's public product documentation does not describe. No new product enhancement is justified by this research.

## 1. Behavior to copy directly from HighLevel

1. **Replies remain in Conversations.** HighLevel says a lead's response appears in Conversations. A configured forwarding address sends an additional copy to an external inbox; it does not replace the copy in Conversations. By contrast, configuring a separate Reply Address intentionally routes replies away from Conversations, and external replies then do not sync back. UCRM should copy the Conversations-first behavior, not the redirect-away option. [HighLevel reply and forward settings](https://help.gohighlevel.com/support/solutions/articles/48001155000-email-services-configuration-forward-settings)

2. **The reply-routing address is correlation-only.** With reply tracking enabled, HighLevel places a receiving-subdomain address in `Reply-To` so the response can be captured and routed into Conversations. Copying that address into a brand-new email does not work; the sender must reply to the original HighLevel message. This directly supports an opaque, non-general-purpose UCRM reply alias. [HighLevel reply and forward settings](https://help.gohighlevel.com/support/solutions/articles/48001155000-email-services-configuration-forward-settings)

3. **Email retains thread context underneath the unified contact workspace.** HighLevel distinguishes a reply in an existing email thread from a new inbound email conversation. Its email record exposes a `threadId`, subject, sender, To/CC/BCC, attachment URLs, and (for a reply) the email message ID being replied to. The inbound-message API likewise supports passing the email message ID to which an inbound email should be threaded. [HighLevel Inbound Email trigger](https://help.gohighlevel.com/support/solutions/articles/155000007650-workflow-trigger-inbound-email), [Get email by ID](https://marketplace.gohighlevel.com/docs/ghl/conversations/get-email-by-id/), [Add inbound message](https://marketplace.gohighlevel.com/docs/2023-02-21/ghl/conversations/add-an-inbound-message/)

4. **Reply automation is separate from cold-inbound automation.** `Customer Replied` reacts when a contact answers a prior message and can filter for Email. The newer `Inbound Email` trigger can include cold email from unknown senders, distinguish new threads from replies, filter by sender/recipient/subject/body/attachments, and can overlap with `Customer Replied` if configured carelessly. UCRM launch should use the reply event only; broad unknown-sender/new-lead ingestion remains deferred. [HighLevel Customer Replied trigger](https://help.gohighlevel.com/support/solutions/articles/155000002677), [HighLevel Inbound Email trigger](https://help.gohighlevel.com/support/solutions/articles/155000007650-workflow-trigger-inbound-email)

5. **Show inbound attachments on the message inside Conversations.** HighLevel represents inbound events with an attachment array and email records with attachment URLs. Its reply-forwarding documentation explicitly tells users to open Conversations to access an attachment because forwarded reply copies omit attachments. Therefore, a UCRM forwarded copy must never be treated as the authoritative attachment surface. [InboundMessage webhook](https://marketplace.gohighlevel.com/docs/webhook/InboundMessage/), [Get email by ID](https://marketplace.gohighlevel.com/docs/ghl/conversations/get-email-by-id/), [HighLevel reply and forward settings](https://help.gohighlevel.com/support/solutions/articles/48001155000-email-services-configuration-forward-settings)

6. **Preserve stable provider and conversation correlation fields.** HighLevel's inbound webhook includes `locationId`, `contactId`, `conversationId`, `messageId`, `conversationProviderId`, direction, sender, recipient, content type, body, attachments, status, and timestamp. This is evidence for retaining provider IDs and resolving the tenant/contact/conversation before showing or automating the message. [InboundMessage webhook](https://marketplace.gohighlevel.com/docs/webhook/InboundMessage/)

7. **Stop follow-up automation after a real reply.** HighLevel exposes `Stop on Response` for workflows and `Stop on Reply` for email sequences so later automated follow-ups do not continue after the recipient responds. UCRM's domain-specific outcome rules remain authoritative, but this is the behavior to copy for reply-sensitive follow-ups. [HighLevel workflow settings](https://help.gohighlevel.com/support/solutions/articles/48001239875-workflow-settings-overview), [HighLevel email sequences](https://help.gohighlevel.com/support/solutions/articles/155000007772-email-sequences-in-highlevel)

### Part 4 UI evidence to copy

- An inbound email appears in the selected contact's chronological **Message History** rather than in a separate email-only product. The same panel can be filtered to Email, and replying happens inline beneath the active message so its context stays visible. Opening an unread conversation moves the user to the first unread message. [HighLevel Conversations](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab)
- Attachments belong to the message in that conversation history. HighLevel's public email schema exposes attachment URLs on the email record, and its automatic-forwarding settings direct a user back to the HighLevel conversation when the inbound reply contains a file. [Get email by ID](https://marketplace.gohighlevel.com/docs/ghl/conversations/get-email-by-id/), [HighLevel reply and forward settings](https://help.gohighlevel.com/support/solutions/articles/48001155000-email-services-configuration-forward-settings)
- The per-message overflow menu is the entry point for actions such as manually forwarding one inbound email. That opens a forward composer with recipients, an editable `Fwd:` subject/body, and an attachment review before sending; the resulting forward is then shown as an outbound event in the same timeline. [HighLevel manual forwarding](https://help.gohighlevel.com/support/solutions/articles/155000007241-forward-emails-from-conversations-in-highlevel)
- Message Details is a secondary inspection surface. HighLevel documents it as showing source-app/provider information when applicable, useful for understanding an unexpected integration-originated message. The public UI docs do not establish a complete inbound-email header/details layout. [HighLevel Conversations](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab)

This is the Part 4 UI boundary only: render and inspect the inbound reply and its files in the existing GHL-style conversation timeline. Full inbox navigation, composer design, filters, and surrounding panel behavior remain Part 5.

## 2. Behavior already settled in UCRM contracts

These are not open product decisions for Part 4:

- Launch accepts only replies to UCRM-sent operational email; unrelated inbound email and general mailbox synchronization are deferred.
- Each reply uses an opaque alias on the organization's receiving subdomain. It exposes no organization, contact, staff, or work-record identifier.
- The contact's eligible assigned user owns the conversation; missing/inactive ownership falls back to Unassigned; the reply remains visible in shared Conversations.
- To/CC recipients and addresses already connected to the customer may join the guarded thread; unknown senders require review.
- Reply aliases remain active through the approved active/90-day window; expired-alias replies enter guarded organization review.
- Inbound attachments use private organization-scoped storage, authorized downloads, malware scanning, dangerous-type blocking, and a configurable 20 MB total-message limit. Blocked or oversized files remain visibly represented.
- Auto-response headers, delivery notices, and repeated-message patterns do not trigger ordinary customer automations or assignment alerts; detected loops pause the thread and alert an administrator.
- Ingestion resolves the organization, authenticates the provider event, is idempotent, tolerates out-of-order callbacks, and retains provider identifiers.

Sources of authority: `docs/contractor-email-contract.md` and `docs/unified-inbox-behavior-contract.md`.

## 3. Only necessary UCRM deviations

These deviations are required by the approved provider boundary, tenant isolation, or security contract; they are not proposed enhancements.

| HighLevel evidence | Necessary UCRM position |
|---|---|
| HighLevel offers broad cold-inbound capture on some dedicated-domain setups and can automatically create a contact. | Do not enable this at launch. UCRM only accepts correlated replies; unknown or ambiguous senders go to guarded review rather than silently creating or joining a customer. |
| HighLevel can configure a Reply Address that diverts responses away from Conversations. | Do not copy this option. Conversations remains the source of truth; optional staff forwarding is secondary. |
| HighLevel's configured automatic forwarding of reply copies omits attachments. Its separate manual per-message Forward action can include supported attachments after review. | Keep automatic staff-forward copies attachment-free. If manual forwarding is implemented, make attachments explicit in the review surface and keep authenticated UCRM Conversations as the authoritative source. |
| HighLevel's public email record and inbound webhook expose attachment URLs. | UCRM must not rely on indefinitely usable provider URLs. It imports into private tenant-scoped storage and authorizes every download. |
| HighLevel warns that reusing one dedicated domain across sub-accounts can route mail unpredictably. | Preserve one organization-owned receiving subdomain/routing boundary and resolve the organization before any contact or thread association. [HighLevel Inbound Email trigger](https://help.gohighlevel.com/support/solutions/articles/155000007650-workflow-trigger-inbound-email) |

## Explicitly undocumented in reviewed HighLevel sources

- Exact inbound-email matching precedence when multiple contacts share an email address.
- Whether an unknown sender replying to a valid tracked thread is automatically attached, rejected, or quarantined in every HighLevel provider configuration.
- HighLevel's inbound attachment size limit, aggregate-versus-per-file calculation, malware scanning, quarantine behavior, blocked extensions, retention, and download authorization. The documented 20 MB rule describes composer uploads/outbound handling, not inbound-email security. [HighLevel attachments in Conversations](https://help.gohighlevel.com/support/solutions/articles/155000001323-attachments-made-easy-in-conversations)
- Whether reply-forwarded attachment omission is a deliberate security control or only a product limitation.
- Inbound webhook retry schedule, ordering guarantee, signature scheme on this specific event, and duplicate-delivery guarantee. The payload provides identifiers suitable for idempotency, but the event page does not promise exactly-once delivery.
- Automatic suppression of out-of-office replies, DSNs, or mailing-list loops. HighLevel documents how users diagnose mail loops and recommends removing circular forwarding and auto-responder conflicts, but that is not evidence of platform-level automatic loop prevention. [HighLevel mail-loop troubleshooting](https://help.gohighlevel.com/support/solutions/articles/155000006922-mail-loop-detected-resolve-email-routing-conflicts)

These gaps should be implemented from the existing UCRM security/reliability contract and the actual inbound provider's guarantees. They do not require new product behavior or another competitor-derived feature.
