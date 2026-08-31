-- SPF is a UCRM diagnostic for Brevo's shared-IP setup. Sending eligibility is
-- provider verification/authentication plus ownership and DKIM, not SPF.
-- Keep every other sender/domain safeguard unchanged.
do $migration$
declare
  function_name regprocedure;
  source text;
  spf_predicate text;
begin
  foreach function_name in array array[
    'public.begin_communication_email_sender_create(uuid,uuid,text,text,uuid,boolean,boolean,boolean,uuid,text)'::regprocedure,
    'public.begin_communication_email_sender_update(uuid,uuid,text,uuid,boolean,boolean,boolean,boolean,uuid,text)'::regprocedure,
    'private.validate_communication_email_sender()'::regprocedure,
    'public.claim_communication_outbox_event()'::regprocedure
  ] loop
    source := pg_get_functiondef(function_name);
    spf_predicate := case function_name::text
      when 'begin_communication_email_sender_create(uuid,uuid,text,text,uuid,boolean,boolean,boolean,uuid,text)'
        then E'\n    or selected_domain.spf_status <> ''passing'''
      when 'begin_communication_email_sender_update(uuid,uuid,text,uuid,boolean,boolean,boolean,boolean,uuid,text)'
        then E' or selected_domain.spf_status <> ''passing'''
      when 'private.validate_communication_email_sender()'
        then E'\n    or sender_domain.spf_status <> ''passing'''
      when 'claim_communication_outbox_event()'
        then E'\n          or sender_domain.spf_status <> ''passing'''
    end;

    if position(spf_predicate in source) = 0 then
      raise exception 'Expected SPF predicate was not found in %.', function_name;
    end if;

    source := replace(source, spf_predicate, '');
    execute source;

    if position('spf_status <> ''passing''' in pg_get_functiondef(function_name)) > 0 then
      raise exception 'SPF predicate remained in % after replacement.', function_name;
    end if;
  end loop;
end
$migration$;
