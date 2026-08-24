-- Preserve the approved rule from communications_sender_eligibility_ignores_spf_diagnostic:
-- SPF remains a health diagnostic, but it does not temporarily block a verified DKIM sender.
do $$
declare
  function_definition text;
begin
  select pg_get_functiondef('public.claim_communication_outbox_event()'::regprocedure)
  into function_definition;

  if position('sender_domain.spf_status <> ''passing''' in function_definition) > 0 then
    function_definition := replace(
      function_definition,
      ' or sender_domain.spf_status <> ''passing''',
      ''
    );
    execute function_definition;
  end if;
end;
$$;
