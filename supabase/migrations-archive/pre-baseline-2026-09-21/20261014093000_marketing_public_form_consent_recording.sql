-- Marketing (M1, slice 1b): record the public form's marketing-email opt-in into the consent ledger.
--
-- Before: the public form showed an email marketing opt-in box but the answer was thrown away. Now, mirroring the
-- proven web-form service-SMS path (private.record_form_submission_sms_consent, 20261005150000):
--   * the submit route puts {given, disclosure} under contact.email_marketing_consent, building the exact
--     disclosure server-side from the business name the page showed (the browser sends only yes/no);
--   * this after-processed trigger records one 'public_form' opt-in for the exact email on the resolved client.
-- The ledger holds only opt-ins; an unticked box is evidence of nothing and never overrides an earlier opt-in.
-- Nothing is recorded when the email does not resolve to a contact method on the submission's client.

create function private.record_form_submission_marketing_consent()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  consent jsonb := new.contact -> 'email_marketing_consent';
  submitted_email text;
  target_client_id uuid;
  method_id uuid;
begin
  if consent is null or jsonb_typeof(consent) <> 'object' or (consent ->> 'given') is distinct from 'true'
    or coalesce(btrim(consent ->> 'disclosure'), '') = '' then
    return null;
  end if;

  submitted_email := lower(nullif(btrim(new.contact ->> 'email'), ''));
  target_client_id := nullif(new.result ->> 'client_id', '')::uuid;
  if submitted_email is null or target_client_id is null then
    return null;
  end if;

  -- Only the exact email the visitor typed, and only if it belongs to the client this submission became.
  -- client_contact_methods.normalized_value for email is lower(trim(value)), matched here exactly.
  select method.id into method_id
  from public.client_contact_methods as method
  where method.organization_id = new.organization_id and method.client_id = target_client_id
    and method.kind = 'email' and method.normalized_value = submitted_email;
  if method_id is null then
    return null;
  end if;

  insert into public.client_marketing_consent_events (
    organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
    disclosure, evidence, occurred_at
  ) values (
    new.organization_id, target_client_id, method_id, 'opt_in', 'public_form', 'form_submission:' || new.id,
    left(consent ->> 'disclosure', 2000),
    jsonb_build_object(
      'channel', 'form',
      'form_id', new.form_id,
      'form_version_id', new.form_version_id,
      'form_submission_id', new.id
    ),
    new.created_at
  )
  on conflict (organization_id, source, source_event_key) do nothing;

  return null;
end;
$$;

revoke all on function private.record_form_submission_marketing_consent() from public, anon, authenticated;

create trigger form_submissions_record_marketing_consent
  after update of status on private.form_submissions
  for each row
  when (new.status = 'processed' and old.status is distinct from 'processed')
  execute function private.record_form_submission_marketing_consent();
