-- Brevo sender-domain IDs are opaque strings (currently 24-character hexadecimal values), not integers.
-- Keep the existing unique constraint; PostgreSQL rebuilds its backing index for the new representation.
alter table public.communication_email_domains
  alter column provider_domain_id type text
  using provider_domain_id::text;

comment on column public.communication_email_domains.provider_domain_id is
  'Opaque Brevo sender-domain identifier. Never parse or expose it to contractor clients.';
