alter table public.communication_email_domains
  add column dns_zone text;

alter table public.communication_email_domains
  add constraint communication_email_domains_dns_zone_check check (
    dns_zone is null
    or (
      dns_zone = lower(btrim(dns_zone))
      and char_length(dns_zone) between 4 and 253
      and dns_zone ~ '^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'
    )
  );

comment on column public.communication_email_domains.dns_zone is
  'Parent DNS zone explicitly supplied by the platform owner for provider-specific DNS setup guidance. Null means historical domain zone is unknown and must not be guessed.';
