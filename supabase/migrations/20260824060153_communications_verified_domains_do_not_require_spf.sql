-- Brevo's shared-IP domain authentication does not require an SPF record.
-- SPF remains stored as a diagnostic, but it must not prevent a fully
-- provider-verified and DKIM-authenticated sending domain from becoming ready.
alter table public.communication_email_domains
  drop constraint communication_email_domains_verified_state_check;

alter table public.communication_email_domains
  add constraint communication_email_domains_verified_state_check check (
    lifecycle_state <> 'verified'
    or (
      provider_verified
      and ownership_status = 'passing'
      and (
        (purpose = 'sending' and provider_authenticated and dkim_status = 'passing')
        or (purpose = 'receiving' and inbound_mx_status = 'passing')
      )
    )
  );
