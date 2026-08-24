-- Part 3 follow-up: the sender readiness query starts with the member's narrow sender index, then
-- joins only healthy sending domains. Keep that join index-only as organizations add retired domains.
create index communication_email_domains_manual_sender_ready_idx
  on public.communication_email_domains (organization_id, id)
  where purpose = 'sending'
    and lifecycle_state = 'verified'
    and provider_verified
    and provider_authenticated
    and ownership_status = 'passing'
    and dkim_status = 'passing';
