-- Communications A1-D (managed email-domain activation): persist the receiving domain's inbound webhook id.
--
-- A1-D reconciles a contractor's sending domain (mail.<root>) and receiving domain (reply.<root>) through
-- Cloudflare DNS and Brevo, then registers ONE Brevo inbound-parse webhook per receiving domain so replies
-- route back to the shared, secured endpoint. The contract's suspension/closure cleanup requires retryable
-- teardown of that webhook, which means UCRM must remember the opaque provider-issued webhook id per
-- receiving domain -- the only piece of A1-D state the existing schema does not already model.
--
-- docs/contractor-email-contract.md -- § Suspension and closure (retryable provider cleanup keeps the id)
-- Memory/campaigns/communications-activation/parts/A1-domain-activation.md
--
-- Additive and metadata-only: one nullable column, no default, plus a CHECK that fails closed if a webhook id
-- is ever attached to anything but a receiving domain. All existing rows are NULL and satisfy the CHECK, so
-- there is no table rewrite and no validation scan of real data.

alter table public.communication_email_domains
  add column provider_inbound_webhook_id text;

alter table public.communication_email_domains
  add constraint communication_email_domains_inbound_webhook_purpose_check check (
    provider_inbound_webhook_id is null or purpose = 'receiving'
  );

comment on column public.communication_email_domains.provider_inbound_webhook_id is
  'Opaque Brevo inbound-parse webhook id for a receiving domain. NULL for sending domains and for receiving '
  'domains before their webhook is registered. Retained after suspension so cleanup can be retried.';
