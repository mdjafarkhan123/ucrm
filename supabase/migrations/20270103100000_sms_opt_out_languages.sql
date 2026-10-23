-- Stage 10 Part 5d (docs/global-sms-behavior-contract.md § Part 5): opt-out words per language.
--
-- Twilio stops texts only for the words it is told, and translates nothing; English works on its own. Before a
-- business texts a country whose language is not English, an Uplift admin adds that language's words to the
-- business's messaging service in Twilio's Advanced Opt-Out (dashboard only) and records it here. Which
-- languages a country needs, and their words, live in src/lib/communications/sms-opt-out-words.ts; the
-- Texting setup page asks for a language until its row exists, and a country is not marked turned on before.

create table public.communication_sms_opt_out_languages (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  language text not null,
  added_at timestamptz not null default now(),
  -- The Control Room person's name; no Supabase user signs in there.
  added_by_name text,
  primary key (organization_id, language),
  constraint communication_sms_opt_out_languages_language_check check (language ~ '^[a-z]{2,3}$')
);

comment on table public.communication_sms_opt_out_languages is
  'Stage 10 Part 5d: the languages beyond English whose opt-out words Uplift added to a business''s Twilio messaging service (Advanced Opt-Out), and who did it.';

alter table public.communication_sms_opt_out_languages enable row level security;
revoke all on public.communication_sms_opt_out_languages from public, anon, authenticated;
grant select, insert on public.communication_sms_opt_out_languages to service_role;

-- Records a language as added. A second press, or a teammate's, finds it already there and gets null.
create or replace function public.communication_sms_add_opt_out_language(
  p_organization_id uuid, p_language text, p_actor_name text default null
)
returns public.communication_sms_opt_out_languages
language sql
security definer
set search_path = pg_catalog, public
as $$
  insert into public.communication_sms_opt_out_languages (organization_id, language, added_by_name)
  values (p_organization_id, p_language, nullif(trim(p_actor_name), ''))
  on conflict (organization_id, language) do nothing
  returning *;
$$;

revoke all on function public.communication_sms_add_opt_out_language(uuid, text, text) from public, anon, authenticated;
grant execute on function public.communication_sms_add_opt_out_language(uuid, text, text) to service_role;

-- A business's Texting view lists the languages added.
CREATE OR REPLACE FUNCTION public.communication_sms_organization_destinations(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  select jsonb_build_object(
    'account_sid', (
      select a.subaccount_sid
      from public.communication_twilio_accounts a
      where a.organization_id = p_organization_id and a.lifecycle_state <> 'closed'
      order by a.created_at desc
      limit 1
    ),
    -- Stage 10 Part 5d: the languages Uplift added to the business's Twilio opt-out words, beyond English.
    'opt_out_languages', coalesce((
      select jsonb_agg(jsonb_build_object('language', l.language, 'at', l.added_at, 'who', l.added_by_name)
        order by l.added_at)
      from public.communication_sms_opt_out_languages l
      where l.organization_id = p_organization_id
    ), '[]'::jsonb),
    'destinations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'country', d.country_code,
        'status', d.status,
        'is_home', d.is_home,
        'requested_at', d.requested_at,
        'ready_at', d.ready_at,
        'off_at', d.off_at,
        'off_reason', d.off_reason,
        'price', private.communication_sms_country_price(d.country_code),
        'history', private.communication_sms_destination_history(d.id)
      ) order by d.is_home desc, d.requested_at, d.id)
      from public.communication_sms_destinations d
      where d.organization_id = p_organization_id
    ), '[]'::jsonb)
  );
$function$
;
