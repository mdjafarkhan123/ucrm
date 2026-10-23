-- Stage 10 Part 5 (docs/global-sms-behavior-contract.md § Part 5): sending rules per country.
--
-- A business texts the countries it has asked for and Uplift has switched on, nowhere else. Twilio decides
-- which countries an account may text (SMS Geo Permissions), and its API cannot change them, so an Uplift
-- admin switches a country on in the Twilio dashboard and records it here. A country is never ready because
-- the app was told so by the business.
--
-- 1. Phone number countries. Which country a customer's number belongs to, by its longest matching leading
--    digits (+1 204 is Canada, +44 7781 is Guernsey). Rows come from scripts/generate-phone-country-prefixes.mjs.
-- 2. Texting countries. One row per business and country: setting_up (asked; waiting on Uplift), ready
--    (Uplift switched it on in Twilio), off (Uplift could not, or turned it off). The business's own country
--    starts as asked when it gets its first number.
-- 3. Their history, never edited.
-- 4. The route check every send runs at estimate, enqueue and dispatch: the country is ready, the number can
--    text that country, and a US customer texted from a +1 local number has the approved US registration.
-- 5. Enqueue and dispatch use it. The price is the customer's country's price (Twilio bills by destination),
--    and a picture goes as a real picture only when the number and the customer are both in the US or Canada.

-- 1. Phone number countries ------------------------------------------------------------------------------------

create table private.sms_phone_country_prefixes (
  prefix text primary key,
  country_code text not null,
  constraint sms_phone_country_prefixes_prefix_check check (prefix ~ '^[1-9][0-9]{0,7}$'),
  constraint sms_phone_country_prefixes_country_check check (country_code ~ '^[A-Z]{2}$')
);

comment on table private.sms_phone_country_prefixes is
  'Stage 10 Part 5: the country of a phone number by its leading digits (calling code, plus area codes where several countries share one). Generated from libphonenumber-js.';

insert into private.sms_phone_country_prefixes (prefix, country_code) values
('1', 'US'),
('1204', 'CA'),
('1226', 'CA'),
('1236', 'CA'),
('1242', 'BS'),
('1246', 'BB'),
('1249', 'CA'),
('1250', 'CA'),
('1257', 'CA'),
('1263', 'CA'),
('1264', 'AI'),
('1268', 'AG'),
('1284', 'VG'),
('1289', 'CA'),
('1306', 'CA'),
('13100', 'CA'),
('13101', 'CA'),
('1340', 'VI'),
('1343', 'CA'),
('1345', 'KY'),
('1354', 'CA'),
('1365', 'CA'),
('1367', 'CA'),
('1368', 'CA'),
('1382', 'CA'),
('1403', 'CA'),
('1416', 'CA'),
('1418', 'CA'),
('1428', 'CA'),
('1431', 'CA'),
('1437', 'CA'),
('1438', 'CA'),
('1441', 'BM'),
('1450', 'CA'),
('1468', 'CA'),
('1473', 'GD'),
('1474', 'CA'),
('1506', 'CA'),
('1514', 'CA'),
('1519', 'CA'),
('1548', 'CA'),
('1579', 'CA'),
('1581', 'CA'),
('1584', 'CA'),
('1587', 'CA'),
('1600', 'CA'),
('1604', 'CA'),
('1613', 'CA'),
('1622', 'CA'),
('1633', 'CA'),
('1639', 'CA'),
('1647', 'CA'),
('1649', 'TC'),
('1658', 'JM'),
('1664', 'MS'),
('1670', 'MP'),
('1671', 'GU'),
('1672', 'CA'),
('1683', 'CA'),
('1684', 'AS'),
('1705', 'CA'),
('1709', 'CA'),
('1721', 'SX'),
('1742', 'CA'),
('1753', 'CA'),
('1767', 'DM'),
('1778', 'CA'),
('1780', 'CA'),
('1782', 'CA'),
('1784', 'VC'),
('1787', 'PR'),
('18001', 'DO'),
('1807', 'CA'),
('1809', 'DO'),
('1819', 'CA'),
('1825', 'CA'),
('1829', 'DO'),
('1849', 'DO'),
('1867', 'CA'),
('1868', 'TT'),
('1869', 'KN'),
('1873', 'CA'),
('1876', 'JM'),
('1879', 'CA'),
('1902', 'CA'),
('1905', 'CA'),
('1939', 'PR'),
('1942', 'CA'),
('20', 'EG'),
('211', 'SS'),
('212', 'MA'),
('213', 'DZ'),
('216', 'TN'),
('218', 'LY'),
('220', 'GM'),
('221', 'SN'),
('222', 'MR'),
('223', 'ML'),
('224', 'GN'),
('225', 'CI'),
('226', 'BF'),
('227', 'NE'),
('228', 'TG'),
('229', 'BJ'),
('230', 'MU'),
('231', 'LR'),
('232', 'SL'),
('233', 'GH'),
('234', 'NG'),
('235', 'TD'),
('236', 'CF'),
('237', 'CM'),
('238', 'CV'),
('239', 'ST'),
('240', 'GQ'),
('241', 'GA'),
('242', 'CG'),
('243', 'CD'),
('244', 'AO'),
('245', 'GW'),
('246', 'IO'),
('247', 'AC'),
('248', 'SC'),
('249', 'SD'),
('250', 'RW'),
('251', 'ET'),
('252', 'SO'),
('253', 'DJ'),
('254', 'KE'),
('255', 'TZ'),
('256', 'UG'),
('257', 'BI'),
('258', 'MZ'),
('260', 'ZM'),
('261', 'MG'),
('262', 'RE'),
('2622689', 'YT'),
('262269', 'YT'),
('262639', 'YT'),
('2627093', 'YT'),
('2629478', 'YT'),
('2629769', 'YT'),
('263', 'ZW'),
('264', 'NA'),
('265', 'MW'),
('266', 'LS'),
('267', 'BW'),
('268', 'SZ'),
('269', 'KM'),
('27', 'ZA'),
('290', 'SH'),
('290800', 'TA'),
('290801', 'TA'),
('290802', 'TA'),
('290803', 'TA'),
('290804', 'TA'),
('290805', 'TA'),
('290806', 'TA'),
('290807', 'TA'),
('290808', 'TA'),
('290809', 'TA'),
('290810', 'TA'),
('290811', 'TA'),
('290812', 'TA'),
('290813', 'TA'),
('290814', 'TA'),
('290815', 'TA'),
('290816', 'TA'),
('290817', 'TA'),
('290818', 'TA'),
('290819', 'TA'),
('290820', 'TA'),
('290821', 'TA'),
('290822', 'TA'),
('290823', 'TA'),
('290824', 'TA'),
('290825', 'TA'),
('290826', 'TA'),
('290827', 'TA'),
('290828', 'TA'),
('290829', 'TA'),
('290830', 'TA'),
('290831', 'TA'),
('290832', 'TA'),
('290833', 'TA'),
('290834', 'TA'),
('290835', 'TA'),
('290836', 'TA'),
('290837', 'TA'),
('290838', 'TA'),
('290839', 'TA'),
('290840', 'TA'),
('290841', 'TA'),
('290842', 'TA'),
('290843', 'TA'),
('290844', 'TA'),
('290845', 'TA'),
('290846', 'TA'),
('290847', 'TA'),
('290848', 'TA'),
('290849', 'TA'),
('290850', 'TA'),
('290851', 'TA'),
('290852', 'TA'),
('290853', 'TA'),
('290854', 'TA'),
('290855', 'TA'),
('290856', 'TA'),
('290857', 'TA'),
('290858', 'TA'),
('290859', 'TA'),
('290860', 'TA'),
('290861', 'TA'),
('290862', 'TA'),
('290863', 'TA'),
('290864', 'TA'),
('290865', 'TA'),
('290866', 'TA'),
('290867', 'TA'),
('290868', 'TA'),
('290869', 'TA'),
('290870', 'TA'),
('290871', 'TA'),
('290872', 'TA'),
('290873', 'TA'),
('290874', 'TA'),
('290875', 'TA'),
('290876', 'TA'),
('290877', 'TA'),
('290878', 'TA'),
('290879', 'TA'),
('290880', 'TA'),
('290881', 'TA'),
('290882', 'TA'),
('290883', 'TA'),
('290884', 'TA'),
('290885', 'TA'),
('290886', 'TA'),
('290887', 'TA'),
('290888', 'TA'),
('290889', 'TA'),
('290890', 'TA'),
('290891', 'TA'),
('290892', 'TA'),
('290893', 'TA'),
('290894', 'TA'),
('290895', 'TA'),
('290896', 'TA'),
('290897', 'TA'),
('290898', 'TA'),
('290899', 'TA'),
('291', 'ER'),
('297', 'AW'),
('298', 'FO'),
('299', 'GL'),
('30', 'GR'),
('31', 'NL'),
('32', 'BE'),
('33', 'FR'),
('34', 'ES'),
('350', 'GI'),
('351', 'PT'),
('352', 'LU'),
('353', 'IE'),
('354', 'IS'),
('355', 'AL'),
('356', 'MT'),
('357', 'CY'),
('358', 'FI'),
('358018', 'AX'),
('358181', 'AX'),
('358182', 'AX'),
('358183', 'AX'),
('358184', 'AX'),
('358185', 'AX'),
('358186', 'AX'),
('358187', 'AX'),
('358188', 'AX'),
('359', 'BG'),
('36', 'HU'),
('370', 'LT'),
('371', 'LV'),
('372', 'EE'),
('373', 'MD'),
('374', 'AM'),
('375', 'BY'),
('376', 'AD'),
('377', 'MC'),
('378', 'SM'),
('380', 'UA'),
('381', 'RS'),
('382', 'ME'),
('383', 'XK'),
('385', 'HR'),
('386', 'SI'),
('387', 'BA'),
('389', 'MK'),
('39', 'IT'),
('3906698', 'VA'),
('40', 'RO'),
('41', 'CH'),
('420', 'CZ'),
('421', 'SK'),
('423', 'LI'),
('43', 'AT'),
('44', 'GB'),
('441481', 'GG'),
('441534', 'JE'),
('441624', 'IM'),
('447509', 'JE'),
('447524', 'IM'),
('447624', 'IM'),
('447781', 'GG'),
('447797', 'JE'),
('447829', 'JE'),
('447839', 'GG'),
('4479111', 'GG'),
('4479117', 'GG'),
('447937', 'JE'),
('44980', 'GG'),
('44981', 'GG'),
('45', 'DK'),
('46', 'SE'),
('47', 'NO'),
('47790', 'SJ'),
('47791', 'SJ'),
('47792', 'SJ'),
('47793', 'SJ'),
('47794', 'SJ'),
('47795', 'SJ'),
('47796', 'SJ'),
('47797', 'SJ'),
('47798', 'SJ'),
('47799', 'SJ'),
('48', 'PL'),
('49', 'DE'),
('500', 'FK'),
('501', 'BZ'),
('502', 'GT'),
('503', 'SV'),
('504', 'HN'),
('505', 'NI'),
('506', 'CR'),
('507', 'PA'),
('508', 'PM'),
('509', 'HT'),
('51', 'PE'),
('52', 'MX'),
('53', 'CU'),
('54', 'AR'),
('55', 'BR'),
('56', 'CL'),
('57', 'CO'),
('58', 'VE'),
('590', 'GP'),
('59059000', 'MF'),
('59059007', 'MF'),
('59059009', 'MF'),
('59059013', 'MF'),
('59059027', 'BL'),
('59059029', 'BL'),
('59059043', 'MF'),
('59059050', 'MF'),
('59059051', 'BL'),
('59059052', 'BL'),
('59059056', 'MF'),
('59059058', 'MF'),
('59059077', 'MF'),
('59059079', 'MF'),
('59059087', 'BL'),
('591', 'BO'),
('592', 'GY'),
('593', 'EC'),
('594', 'GF'),
('595', 'PY'),
('596', 'MQ'),
('597', 'SR'),
('598', 'UY'),
('599', 'CW'),
('599318', 'BQ'),
('599319', 'BQ'),
('599416', 'BQ'),
('599417', 'BQ'),
('599700', 'BQ'),
('599701', 'BQ'),
('599715', 'BQ'),
('599717', 'BQ'),
('599718', 'BQ'),
('599720', 'BQ'),
('599725', 'BQ'),
('599750', 'BQ'),
('599770', 'BQ'),
('599777', 'BQ'),
('599780', 'BQ'),
('599781', 'BQ'),
('599782', 'BQ'),
('599783', 'BQ'),
('599784', 'BQ'),
('599785', 'BQ'),
('599786', 'BQ'),
('599787', 'BQ'),
('599788', 'BQ'),
('599789', 'BQ'),
('599790', 'BQ'),
('599795', 'BQ'),
('599796', 'BQ'),
('60', 'MY'),
('61', 'AU'),
('6189162', 'CC'),
('6189164', 'CX'),
('62', 'ID'),
('63', 'PH'),
('64', 'NZ'),
('65', 'SG'),
('66', 'TH'),
('670', 'TL'),
('672', 'NF'),
('673', 'BN'),
('674', 'NR'),
('675', 'PG'),
('676', 'TO'),
('677', 'SB'),
('678', 'VU'),
('679', 'FJ'),
('680', 'PW'),
('681', 'WF'),
('682', 'CK'),
('683', 'NU'),
('685', 'WS'),
('686', 'KI'),
('687', 'NC'),
('688', 'TV'),
('689', 'PF'),
('690', 'TK'),
('691', 'FM'),
('692', 'MH'),
('7', 'RU'),
('7700', 'KZ'),
('7701', 'KZ'),
('7702', 'KZ'),
('7705', 'KZ'),
('7706', 'KZ'),
('7707', 'KZ'),
('7708', 'KZ'),
('7710', 'KZ'),
('7711', 'KZ'),
('7712', 'KZ'),
('7713', 'KZ'),
('7714', 'KZ'),
('7715', 'KZ'),
('7716', 'KZ'),
('7717', 'KZ'),
('7718', 'KZ'),
('7721', 'KZ'),
('7722', 'KZ'),
('7723', 'KZ'),
('7724', 'KZ'),
('7725', 'KZ'),
('7726', 'KZ'),
('7727', 'KZ'),
('7728', 'KZ'),
('7729', 'KZ'),
('7747', 'KZ'),
('7751', 'KZ'),
('7760', 'KZ'),
('7761', 'KZ'),
('7762', 'KZ'),
('7763', 'KZ'),
('7764', 'KZ'),
('7771', 'KZ'),
('7775', 'KZ'),
('7776', 'KZ'),
('7777', 'KZ'),
('7778', 'KZ'),
('7785', 'KZ'),
('81', 'JP'),
('82', 'KR'),
('84', 'VN'),
('850', 'KP'),
('852', 'HK'),
('853', 'MO'),
('855', 'KH'),
('856', 'LA'),
('86', 'CN'),
('880', 'BD'),
('886', 'TW'),
('90', 'TR'),
('91', 'IN'),
('92', 'PK'),
('93', 'AF'),
('94', 'LK'),
('95', 'MM'),
('960', 'MV'),
('961', 'LB'),
('962', 'JO'),
('963', 'SY'),
('964', 'IQ'),
('965', 'KW'),
('966', 'SA'),
('967', 'YE'),
('968', 'OM'),
('970', 'PS'),
('971', 'AE'),
('972', 'IL'),
('973', 'BH'),
('974', 'QA'),
('975', 'BT'),
('976', 'MN'),
('977', 'NP'),
('98', 'IR'),
('992', 'TJ'),
('993', 'TM'),
('994', 'AZ'),
('995', 'GE'),
('996', 'KG'),
('998', 'UZ')
;

create or replace function private.sms_phone_country(p_e164 text)
returns text
language sql
stable
set search_path = pg_catalog, private
as $$
  select p.country_code
  from private.sms_phone_country_prefixes p
  where p.prefix in (
    select left(ltrim(p_e164, '+'), n) from generate_series(1, 8) n
  )
  order by length(p.prefix) desc
  limit 1;
$$;

comment on function private.sms_phone_country(text) is
  'Stage 10 Part 5: the two-letter country of an E.164 phone number, or null when no calling code matches.';

revoke all on function private.sms_phone_country(text) from public, anon, authenticated;

-- 2. Texting countries -----------------------------------------------------------------------------------------

create table public.communication_sms_destinations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  country_code text not null,
  -- setting_up: asked for, waiting on Uplift. ready: switched on in Twilio. off: Uplift could not, or turned
  -- it off.
  status text not null default 'setting_up',
  -- The business's own country, asked for when it got its first number.
  is_home boolean not null default false,
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  ready_by uuid references auth.users(id) on delete set null,
  ready_at timestamptz,
  off_by uuid references auth.users(id) on delete set null,
  off_at timestamptz,
  -- Why it is off, for Uplift, and what the business is told.
  off_reason text,
  business_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_destinations_org_id_key unique (organization_id, id),
  constraint communication_sms_destinations_country_key unique (organization_id, country_code),
  constraint communication_sms_destinations_country_check check (country_code ~ '^[A-Z]{2}$'),
  constraint communication_sms_destinations_status_check check (status in ('setting_up', 'ready', 'off')),
  constraint communication_sms_destinations_ready_check check (status <> 'ready' or ready_at is not null),
  constraint communication_sms_destinations_off_check check (
    status <> 'off' or (off_at is not null and off_reason is not null)
  ),
  constraint communication_sms_destinations_text_check check (
    (off_reason is null or char_length(off_reason) between 1 and 500)
    and (business_message is null or char_length(business_message) between 1 and 2000)
  )
);

comment on table public.communication_sms_destinations is
  'Stage 10 Part 5: the countries a business may text. Ready only once an Uplift admin has switched the country on in Twilio. Server only.';

-- Uplift's to-do queue: every country still waiting, oldest first.
create index communication_sms_destinations_waiting_idx
  on public.communication_sms_destinations (requested_at)
  where status = 'setting_up';

alter table public.communication_sms_destinations enable row level security;
revoke all on table public.communication_sms_destinations from anon, authenticated;

-- 3. History ---------------------------------------------------------------------------------------------------

create table public.communication_sms_destination_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  destination_id uuid not null,
  -- requested, switched_on, closed (Uplift could not switch it on), turned_off.
  event_kind text not null,
  actor uuid references auth.users(id) on delete set null,
  note text,
  occurred_at timestamptz not null default now(),
  constraint communication_sms_destination_events_destination_fkey
    foreign key (organization_id, destination_id)
    references public.communication_sms_destinations (organization_id, id) on delete cascade,
  constraint communication_sms_destination_events_kind_check
    check (event_kind in ('requested', 'switched_on', 'closed', 'turned_off')),
  constraint communication_sms_destination_events_note_check check (note is null or char_length(note) <= 2000)
);

create index communication_sms_destination_events_destination_idx
  on public.communication_sms_destination_events (destination_id, occurred_at desc);

alter table public.communication_sms_destination_events enable row level security;
revoke all on table public.communication_sms_destination_events from anon, authenticated;

-- 4. Commands --------------------------------------------------------------------------------------------------

-- Ask for a country. Asking again for one that is off asks again; one already asked or ready is left alone.
create or replace function public.communication_sms_request_destination(
  p_organization_id uuid,
  p_country_code text,
  p_actor uuid default null,
  p_is_home boolean default false
) returns public.communication_sms_destinations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  destination public.communication_sms_destinations;
begin
  if p_country_code is null or p_country_code !~ '^[A-Z]{2}$' then
    raise exception 'Choose a country.' using errcode = 'check_violation';
  end if;

  insert into public.communication_sms_destinations (
    organization_id, country_code, is_home, requested_by
  ) values (
    p_organization_id, p_country_code, p_is_home, p_actor
  )
  on conflict (organization_id, country_code) do nothing
  returning * into destination;

  if destination.id is not null then
    insert into public.communication_sms_destination_events (organization_id, destination_id, event_kind, actor)
    values (p_organization_id, destination.id, 'requested', p_actor);
    return destination;
  end if;

  select d.* into destination
  from public.communication_sms_destinations d
  where d.organization_id = p_organization_id and d.country_code = p_country_code
  for update;

  if destination.status = 'off' then
    update public.communication_sms_destinations
    set status = 'setting_up', requested_by = p_actor, requested_at = now(),
      off_by = null, off_at = null, off_reason = null, business_message = null,
      is_home = is_home or p_is_home, updated_at = now()
    where id = destination.id
    returning * into destination;
    insert into public.communication_sms_destination_events (organization_id, destination_id, event_kind, actor)
    values (p_organization_id, destination.id, 'requested', p_actor);
  elsif p_is_home and not destination.is_home then
    update public.communication_sms_destinations
    set is_home = true, updated_at = now()
    where id = destination.id
    returning * into destination;
  end if;

  return destination;
end;
$$;

comment on function public.communication_sms_request_destination(uuid, text, uuid, boolean) is
  'Stage 10 Part 5: a business asks to text a country. Idempotent; an off country is asked for again.';

-- The business's own country and every country it owns a number in, asked for once it has a number.
create or replace function public.communication_sms_request_number_destinations(
  p_organization_id uuid,
  p_actor uuid default null
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  home text;
  country text;
  asked integer := 0;
begin
  if not exists (
    select 1 from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id and s.lifecycle_state <> 'released'
  ) then
    return 0;
  end if;

  select os.country_code into home
  from public.organization_settings os
  where os.organization_id = p_organization_id;

  for country in
    select distinct c from (
      select home as c where home ~ '^[A-Z]{2}$'
      union all
      select s.country_code
      from public.communication_sms_sender_identities s
      where s.organization_id = p_organization_id
        and s.lifecycle_state <> 'released'
        and s.country_code is not null
    ) countries
  loop
    if not exists (
      select 1 from public.communication_sms_destinations d
      where d.organization_id = p_organization_id and d.country_code = country
    ) then
      perform public.communication_sms_request_destination(p_organization_id, country, p_actor, country = home);
      asked := asked + 1;
    end if;
  end loop;

  return asked;
end;
$$;

comment on function public.communication_sms_request_number_destinations(uuid, uuid) is
  'Stage 10 Part 5: asks for the business''s own country and each of its numbers'' countries once it owns a number. Never re-asks a country it already has a row for (an off one stays off).';

-- Uplift switched the country on in Twilio. Returns null when it was not waiting (a teammate did it first).
create or replace function public.communication_sms_switch_on_destination(
  p_destination_id uuid,
  p_actor uuid
) returns public.communication_sms_destinations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  destination public.communication_sms_destinations;
begin
  update public.communication_sms_destinations
  set status = 'ready', ready_by = p_actor, ready_at = now(), updated_at = now()
  where id = p_destination_id and status = 'setting_up'
  returning * into destination;

  if destination.id is not null then
    insert into public.communication_sms_destination_events (organization_id, destination_id, event_kind, actor)
    values (destination.organization_id, destination.id, 'switched_on', p_actor);
  end if;
  return destination;
end;
$$;

comment on function public.communication_sms_switch_on_destination(uuid, uuid) is
  'Stage 10 Part 5: an Uplift admin records that the country is switched on in Twilio. Only a waiting country moves; null means it was not waiting.';

-- Uplift could not switch a waiting country on (p_closing) or turns a ready one off. Returns null when the
-- country was not in the expected state.
create or replace function public.communication_sms_turn_off_destination(
  p_destination_id uuid,
  p_actor uuid,
  p_reason text,
  p_business_message text,
  p_closing boolean
) returns public.communication_sms_destinations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  destination public.communication_sms_destinations;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'Give a reason.' using errcode = 'check_violation';
  end if;

  update public.communication_sms_destinations
  set status = 'off', off_by = p_actor, off_at = now(), off_reason = trim(p_reason),
    business_message = nullif(trim(coalesce(p_business_message, '')), ''), updated_at = now()
  where id = p_destination_id
    and status = case when p_closing then 'setting_up' else 'ready' end
  returning * into destination;

  if destination.id is not null then
    insert into public.communication_sms_destination_events (
      organization_id, destination_id, event_kind, actor, note
    ) values (
      destination.organization_id, destination.id,
      case when p_closing then 'closed' else 'turned_off' end, p_actor, trim(p_reason)
    );
  end if;
  return destination;
end;
$$;

comment on function public.communication_sms_turn_off_destination(uuid, uuid, text, text, boolean) is
  'Stage 10 Part 5: closes a waiting country Uplift could not switch on, or turns a ready one off, with a reason and what the business is told.';

-- 5. The route check -------------------------------------------------------------------------------------------

-- Whether this number may text this customer's country right now. ok, or a code and the words the business
-- sees. A +1 number (US or Canada) texts the US and Canada; any other number texts its own country.
create or replace function private.communication_sms_route_check(
  p_organization_id uuid,
  p_sender public.communication_sms_sender_identities,
  p_recipient_country text,
  out ok boolean,
  out code text,
  out message text,
  out mms_route boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  destination public.communication_sms_destinations;
  registration_status text;
begin
  ok := false;
  mms_route := false;

  if public.communication_sms_effective_mode(p_organization_id) = 'off' then
    code := 'not_included';
    message := 'Texting is not part of this business''s plan.';
    return;
  end if;

  if p_recipient_country is null then
    code := 'unknown_country';
    message := 'This phone number doesn''t belong to a country we can text.';
    return;
  end if;

  select d.* into destination
  from public.communication_sms_destinations d
  where d.organization_id = p_organization_id and d.country_code = p_recipient_country;

  if destination.id is null or destination.status = 'off' then
    code := 'destination_off';
    message := coalesce(destination.business_message, 'Texting this country isn''t switched on for your business.');
    return;
  elsif destination.status <> 'ready' then
    code := 'destination_setting_up';
    message := 'Uplift is still switching texting on for this country.';
    return;
  end if;

  if not (
    p_sender.country_code = p_recipient_country
    or (p_sender.country_code in ('US', 'CA') and p_recipient_country in ('US', 'CA'))
  ) then
    code := 'sender_wrong_country';
    message := 'This number can''t text this country. Use a number from the same country.';
    return;
  end if;

  -- A US customer texted from a +1 local number needs the business's approved US registration (A2P 10DLC).
  -- Toll-free numbers carry their own check, passed before the number went live.
  if p_recipient_country = 'US' and p_sender.sender_type = 'long_code' then
    select r.status into registration_status
    from public.communication_sms_registrations r
    where r.organization_id = p_organization_id and r.id = p_sender.registration_id;
    if registration_status is distinct from 'approved' then
      code := 'us_registration_needed';
      message := 'This number needs the business''s approved US registration to text US customers.';
      return;
    end if;
  end if;

  if exists (select 1 from public.communication_sms_active_outbound_hold(p_organization_id)) then
    code := 'outbound_paused';
    message := 'Outbound SMS is paused for this organization right now.';
    return;
  end if;

  ok := true;
  -- Twilio carries real picture messages only between US and Canadian numbers.
  mms_route := p_sender.capable_mms
    and p_sender.country_code in ('US', 'CA') and p_recipient_country in ('US', 'CA');
end;
$$;

comment on function private.communication_sms_route_check(uuid, public.communication_sms_sender_identities, text) is
  'Stage 10 Part 5: the one route rule shared by estimate, enqueue and dispatch: the customer''s country is ready for the business, the number can text it, and US registration where needed.';

revoke all on function private.communication_sms_route_check(uuid, public.communication_sms_sender_identities, text)
  from public, anon, authenticated;

-- The number a send goes from: the chosen one, else the default when it can text the customer's country,
-- else a ready number from that country (Twilio's Geo-match), else the default so the check explains why not.
create or replace function private.communication_sms_pick_sender(
  p_organization_id uuid,
  p_sender_id uuid,
  p_recipient_country text
) returns public.communication_sms_sender_identities
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select s.*
  from public.communication_sms_sender_identities s
  where s.organization_id = p_organization_id
    and s.lifecycle_state = 'ready'
    and s.capable_sms
    and (p_sender_id is null or s.id = p_sender_id)
  order by
    (s.country_code = p_recipient_country
      or (s.country_code in ('US', 'CA') and p_recipient_country in ('US', 'CA'))) desc,
    s.is_default_sender desc,
    (s.country_code = p_recipient_country) desc,
    s.created_at, s.id
  limit 1;
$$;

revoke all on function private.communication_sms_pick_sender(uuid, uuid, text) from public, anon, authenticated;

-- What the reply box shows before Send: the customer's country, the number it would go from, and whether the
-- route is open. Read-only.
create or replace function public.communication_sms_route_preview(
  p_organization_id uuid,
  p_client_contact_method_id uuid,
  p_sender_id uuid default null
) returns table (
  recipient_country text,
  sender_id uuid,
  sender_country text,
  sender_type text,
  ok boolean,
  code text,
  message text,
  mms_route boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  phone text;
  sender public.communication_sms_sender_identities;
  route record;
begin
  select '+' || m.normalized_value into phone
  from public.client_contact_methods m
  where m.organization_id = p_organization_id and m.id = p_client_contact_method_id and m.kind = 'phone';

  recipient_country := private.sms_phone_country(phone);
  sender := private.communication_sms_pick_sender(p_organization_id, p_sender_id, recipient_country);

  if sender.id is null then
    ok := false;
    code := 'no_sender';
    message := 'No ready SMS number is available to send from.';
    mms_route := false;
    return next;
    return;
  end if;

  sender_id := sender.id;
  sender_country := sender.country_code;
  sender_type := sender.sender_type;
  select * into route from private.communication_sms_route_check(p_organization_id, sender, recipient_country);
  ok := route.ok;
  code := route.code;
  message := route.message;
  mms_route := route.mms_route;
  return next;
end;
$$;

comment on function public.communication_sms_route_preview(uuid, uuid, uuid) is
  'Stage 10 Part 5: the customer''s country, the number a text would go from, and whether that route may text right now. Service role only.';

revoke all on function public.communication_sms_route_preview(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.communication_sms_route_preview(uuid, uuid, uuid) to service_role;

-- The phone an inbox reply texts: the number this customer last texted with, else their main phone. Shared by
-- the reply and its price preview so both name the same customer number.
create or replace function private.conversation_reply_sms_recipient(
  p_organization_id uuid,
  p_client_id uuid
) returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with latest as (
    select client_contact_method_id
    from (
      select client_contact_method_id, created_at
      from public.communication_delivery_intents
      where organization_id = p_organization_id and client_id = p_client_id and channel = 'sms'
      union all
      select client_contact_method_id, created_at
      from public.communication_inbound_messages
      where organization_id = p_organization_id and client_id = p_client_id and channel = 'sms'
    ) activity
    order by created_at desc
    limit 1
  )
  select method.id
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = p_organization_id
    and method.client_id = p_client_id
    and method.kind = 'phone'
    and client.deleted_at is null
    and (
      not exists (select 1 from latest)
      or method.id = (select client_contact_method_id from latest)
    )
  order by method.is_primary desc, method.created_at, method.id
  limit 1;
$$;

revoke all on function private.conversation_reply_sms_recipient(uuid, uuid) from public, anon, authenticated;

create or replace function public.enqueue_conversation_reply_sms(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_logical_send_key text,
  target_body text,
  target_attachments jsonb default '[]'::jsonb
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  recipient public.client_contact_methods;
begin
  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.id = private.conversation_reply_sms_recipient(target_organization_id, target_client_id)
    and client.deleted_at is null
  for share of method, client;

  if recipient.id is null then
    raise exception 'This customer has no active phone number to reply to.' using errcode = 'foreign_key_violation';
  end if;

  return public.communication_sms_enqueue_operational(
    target_organization_id, target_actor_user_id, target_client_id, recipient.id,
    null, 'service', target_body, 'manual', target_logical_send_key, target_attachments
  );
end;
$$;

-- The route an inbox reply to this customer would take, for the price shown before Send.
create or replace function public.communication_sms_reply_route_preview(
  p_organization_id uuid,
  p_client_id uuid
) returns table (
  recipient_country text,
  sender_id uuid,
  sender_country text,
  sender_type text,
  ok boolean,
  code text,
  message text,
  mms_route boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  method_id uuid := private.conversation_reply_sms_recipient(p_organization_id, p_client_id);
begin
  if method_id is null then
    ok := false;
    code := 'no_recipient';
    message := 'This customer has no active phone number to reply to.';
    mms_route := false;
    return next;
    return;
  end if;
  return query select * from public.communication_sms_route_preview(p_organization_id, method_id, null);
end;
$$;

revoke all on function public.communication_sms_reply_route_preview(uuid, uuid) from public, anon, authenticated;
grant execute on function public.communication_sms_reply_route_preview(uuid, uuid) to service_role;

revoke all on function public.communication_sms_request_destination(uuid, text, uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.communication_sms_request_number_destinations(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.communication_sms_switch_on_destination(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.communication_sms_turn_off_destination(uuid, uuid, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.communication_sms_request_destination(uuid, text, uuid, boolean) to service_role;
grant execute on function public.communication_sms_request_number_destinations(uuid, uuid) to service_role;
grant execute on function public.communication_sms_switch_on_destination(uuid, uuid) to service_role;
grant execute on function public.communication_sms_turn_off_destination(uuid, uuid, text, text, boolean)
  to service_role;

-- A finished number order asks for its countries.
CREATE OR REPLACE FUNCTION public.communication_sms_complete_number_order(p_order_id uuid)
 RETURNS communication_sms_number_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  o public.communication_sms_number_orders;
  v_sender_id uuid;
begin
  select * into o from public.communication_sms_number_orders where id = p_order_id for update;
  if not found then
    raise exception 'number_order_not_found' using errcode = 'P0001';
  end if;
  if o.state = 'completed' then
    return o;
  end if;
  if o.state <> 'purchased' then
    raise exception 'number_order_not_purchased' using errcode = 'P0001';
  end if;

  select s.id into v_sender_id
  from public.communication_sms_sender_identities s
  where s.organization_id = o.organization_id
    and s.phone_number = o.phone_number
    and s.lifecycle_state <> 'released';

  if v_sender_id is null then
    insert into public.communication_sms_sender_identities (
      organization_id, phone_number, country_code, sender_type, number_type, provider_phone_number_sid,
      capable_sms, capable_mms, capable_voice
    ) values (
      o.organization_id, o.phone_number, o.country_code,
      case when o.number_type = 'toll_free' then 'toll_free' else 'long_code' end,
      o.number_type, o.provider_phone_number_sid, o.capable_sms, o.capable_mms, o.capable_voice
    )
    returning id into v_sender_id;
  end if;

  update public.communication_sms_number_orders
  set state = 'completed', sender_identity_id = v_sender_id, completed_at = now(), updated_at = now()
  where id = p_order_id
  returning * into o;

  -- Stage 10 Part 5: the business's own country and this number's country are asked for, for Uplift to switch
  -- on in Twilio.
  perform public.communication_sms_request_number_destinations(o.organization_id, o.requested_by);

  return o;
end;
$function$;

-- Businesses that already own a number ask for their countries now.
select public.communication_sms_request_number_destinations(o.organization_id)
from (select distinct organization_id from public.communication_sms_sender_identities) o;

-- 6. Enqueue and dispatch ----------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.communication_sms_enqueue_operational_core(p_organization_id uuid, p_client_id uuid, p_client_contact_method_id uuid, p_sender_id uuid, p_subject text, p_body text, p_send_kind text, p_logical_send_key text, p_created_by uuid, p_attachments jsonb DEFAULT '[]'::jsonb)
 RETURNS communication_delivery_intents
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  recipient public.client_contact_methods;
  recipient_e164 text;
  sender public.communication_sms_sender_identities;
  recipient_country text;
  route record;
  consent text;
  v_encoding text;
  v_segment_count integer;
  rate public.communication_sms_retail_rates;
  cost_minor bigint;
  currency text := 'USD';
  settled bigint;
  reserved bigint;
  promo_balance bigint;
  promo_reserved bigint;
  promo_available bigint;
  purchased_available bigint;
  promo_used bigint;
  purchased_used bigint;
  available timestamptz;
  intent public.communication_delivery_intents;
  existing public.communication_delivery_intents;
  existing_raw_body text;
  source_key text;
  v_attachment jsonb;
  v_delivery_mode text;
  v_effective_body text;
  v_attachment_id uuid;
  v_attachment_bytes bigint;
begin
  -- 1. Shape.
  if p_subject is null or p_subject not in ('service', 'work_updates', 'billing_updates') then
    raise exception 'a send must name a valid operational subject' using errcode = 'P0001';
  end if;
  if p_body is null or char_length(trim(p_body)) = 0 then
    raise exception 'a send needs a message body' using errcode = 'P0001';
  end if;
  if p_send_kind is null or p_send_kind not in ('manual', 'automated') then
    raise exception 'a send must be manual or automated' using errcode = 'P0001';
  end if;
  if p_logical_send_key is null or char_length(trim(p_logical_send_key)) = 0 then
    raise exception 'a send must carry a logical send key' using errcode = 'P0001';
  end if;
  if jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) > 1 then
    raise exception 'Attach at most one file to a text message.' using errcode = 'check_violation';
  end if;

  -- 2. Resolve the recipient: an active phone on this customer in this organization, normalized to E.164.
  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = p_organization_id
    and method.id = p_client_contact_method_id
    and method.client_id = p_client_id
    and method.kind = 'phone'
    and client.deleted_at is null
  for share of method, client;

  if recipient.id is null then
    raise exception 'Choose an active phone number for this customer.' using errcode = 'foreign_key_violation';
  end if;
  recipient_e164 := '+' || recipient.normalized_value;
  if recipient_e164 !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'That customer phone number is not a valid mobile number.' using errcode = 'P0001';
  end if;
  recipient_country := private.sms_phone_country(recipient_e164);

  -- 3. Resolve the sending number (Stage 10 Part 5): the chosen one, else the default when it can text the
  --    customer's country, else a ready number from that country (Twilio's Geo-match). Must be live and
  --    SMS-capable; whether it may text this customer is the route check in step 5.
  sender := private.communication_sms_pick_sender(p_organization_id, p_sender_id, recipient_country);
  if sender.id is null then
    raise exception 'No ready SMS number is available to send from.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  perform 1 from public.communication_sms_sender_identities s where s.id = sender.id for share of s;
  if sender.country_code is null or sender.sender_type is null then
    raise exception 'This SMS number is not fully set up to send yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 4. Idempotency: a repeat of the same logical send returns the already-queued intent unchanged; the same
  --    key with a different frozen payload is a conflict. Compared against raw_body (what the user actually
  --    typed), never the wire body -- see this migration's header note on why the wire body can legitimately
  --    differ attempt to attempt for a secure-link send. Return the replay before re-running any live gate.
  select i.* into existing
  from public.communication_delivery_intents i
  where i.organization_id = p_organization_id and i.logical_send_key = trim(p_logical_send_key);

  if existing.id is not null then
    select snap.raw_body into existing_raw_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;

    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_raw_body = p_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end if;

  -- 5. The route (Stage 10 Part 5): plan, the customer's country switched on for the business, a number that
  --    can text that country, US registration where needed, and no outbound hold.
  select * into route from private.communication_sms_route_check(p_organization_id, sender, recipient_country);
  if not route.ok then
    raise exception '%', route.message using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 5.5. Delivery mode (Stage 6D-3, routed by Stage 10 Part 5): a picture goes as real MMS only when the number
  --      can send pictures and both it and the customer are in the US or Canada (Twilio's limit). Anything
  --      else with an attachment -- a non-image file, or an image the route cannot carry as MMS -- gets a
  --      secure link instead of a refusal, per the approved 6D contract.
  if jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) = 1 then
    v_attachment := p_attachments -> 0;
    if (v_attachment ->> 'mime_type') in ('image/jpeg', 'image/jpg', 'image/png', 'image/gif')
       and route.mms_route then
      v_delivery_mode := 'inline_media';
    else
      v_delivery_mode := 'secure_link';
    end if;
  end if;

  v_effective_body := case
    when v_delivery_mode = 'secure_link' then p_body || E'\n\n' || (v_attachment ->> 'link_url')
    else p_body
  end;

  -- 6. Consent for this exact number and this one subject. Unknown or opted-out refuses.
  consent := public.communication_sms_consent_status(
    p_organization_id, p_client_contact_method_id, p_subject
  );
  if consent = 'opted_out' then
    raise exception 'This customer has opted out of text messages.' using errcode = 'P0001';
  elsif consent <> 'opted_in' then
    raise exception 'There is no SMS consent on file for this customer and message type.'
      using errcode = 'P0001';
  end if;

  -- 7. Freeze the segment estimate against the wire body (with any secure link already appended), so the
  --     charge, the "too long to send" refusal and the frozen snapshot all agree on what is actually sent.
  select est.encoding, est.segment_count into v_encoding, v_segment_count
  from public.communication_sms_estimate_segments(v_effective_body) est;
  if v_segment_count > 10 then
    raise exception 'This message is too long to send as one text.' using errcode = 'P0001';
  end if;

  -- 8. Freeze the customer's country's retail rate (Twilio bills by destination) and the estimated cost (rounded up so the reservation never
  --    under-holds). A real MMS photo bills as one flat message_unit='mms' charge, matching how Twilio itself
  --    bills a picture text -- per segment only applies to plain text.
  if v_delivery_mode = 'inline_media' then
    select rr.* into rate
    from public.communication_sms_effective_retail_rate(
      recipient_country, sender.sender_type, 'mms', currency, now()
    ) rr;
    if rate.id is null then
      raise exception 'No picture-message price is published for this destination yet.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
    cost_minor := ceil(rate.retail_rate_major * 100)::bigint;
  else
    select rr.* into rate
    from public.communication_sms_effective_retail_rate(
      recipient_country, sender.sender_type, 'segment', currency, now()
    ) rr;
    if rate.id is null then
      raise exception 'No SMS price is published for this destination yet.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
    cost_minor := ceil(v_segment_count * rate.retail_rate_major * 100)::bigint;
  end if;

  -- 9. Serialize on the organization's credit account and check spendable balance.
  insert into public.communication_sms_credit_accounts (organization_id, currency_code)
  values (p_organization_id, currency)
  on conflict (organization_id) do nothing;

  select settled_balance_minor, reserved_balance_minor into settled, reserved
  from public.communication_sms_credit_accounts
  where organization_id = p_organization_id
  for update;

  promo_balance := public.communication_sms_promotional_balance(p_organization_id);
  select coalesce(sum(reserved_promotional_minor), 0) into promo_reserved
  from public.communication_sms_credit_reservations
  where organization_id = p_organization_id and state in ('reserved', 'submission_unknown', 'settled');
  promo_available := greatest(promo_balance - promo_reserved, 0);
  purchased_available := settled - reserved;

  if promo_available + purchased_available < cost_minor then
    raise exception 'There is not enough SMS balance to send this message.' using errcode = 'P0402';
  end if;

  promo_used := least(cost_minor, promo_available);
  purchased_used := cost_minor - promo_used;

  -- 10. Schedule for quiet hours (now unless inside the window).
  available := public.communication_sms_quiet_hours_available_at(now());

  -- 11. Create the durable send intent.
  begin
    insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, channel, logical_send_key,
      recipient_phone, sms_sender_identity_id, send_kind, allowance_class, created_by
    ) values (
      p_organization_id, p_client_id, p_client_contact_method_id, 'sms', trim(p_logical_send_key),
      recipient_e164, sender.id, p_send_kind, 'optional', p_created_by
    )
    returning * into intent;
  exception when unique_violation then
    select i.* into existing
    from public.communication_delivery_intents i
    where i.organization_id = p_organization_id and i.logical_send_key = trim(p_logical_send_key);
    select snap.raw_body into existing_raw_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;
    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_raw_body = p_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end;

  -- 12. Freeze the wire body (with any link already appended), the raw draft text, encoding and segment count.
  insert into public.communication_sms_message_snapshots (
    delivery_intent_id, organization_id, body, raw_body, encoding, segment_count
  ) values (
    intent.id, p_organization_id, v_effective_body, p_body, v_encoding, v_segment_count
  );

  -- 13. Reserve the estimated cost.
  source_key := 'send:' || trim(p_logical_send_key);
  update public.communication_sms_credit_accounts
  set reserved_balance_minor = reserved_balance_minor + purchased_used,
      updated_at = now()
  where organization_id = p_organization_id;

  insert into public.communication_sms_credit_reservations (
    organization_id, delivery_intent_id, source_key, amount_minor, segment_count,
    reserved_promotional_minor, reserved_purchased_minor
  ) values (
    p_organization_id, intent.id, source_key, cost_minor, v_segment_count,
    promo_used, purchased_used
  );

  -- 14. Persist the attachment (if any) and, for a secure-link delivery, the access link the body already
  --     names. Re-validates size and the caller's own object-key prefix server-side (advisory checks
  --     already ran in TS) -- a real MMS photo keeps 6D-2's own 5 MB/image-only ceiling; anything going out
  --     as a link gets the same 20 MB ceiling every other outbound attachment (email) already uses.
  if v_delivery_mode is not null then
    v_attachment_bytes := (v_attachment ->> 'byte_size')::bigint;
    if not private.outbound_attachment_key_allowed(
      p_organization_id, v_attachment ->> 'object_key', 'outbound-sms-attachments'
    ) then
      raise exception 'That file does not belong to this business.' using errcode = 'check_violation';
    end if;
    if v_delivery_mode = 'inline_media' and v_attachment_bytes > 5 * 1024 * 1024 then
      raise exception 'A picture must be 5 MB or smaller to send as a text message.'
        using errcode = 'check_violation';
    end if;
    if v_delivery_mode = 'secure_link' and v_attachment_bytes > 20 * 1024 * 1024 then
      raise exception 'A file must be 20 MB or smaller to send as a text message.'
        using errcode = 'check_violation';
    end if;

    insert into public.communication_outbound_attachments (
      organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key, delivery_mode
    ) values (
      p_organization_id, intent.id, v_attachment ->> 'file_name', v_attachment ->> 'mime_type',
      v_attachment_bytes, v_attachment ->> 'object_key', v_delivery_mode
    )
    on conflict (delivery_intent_id, object_key) do update set delivery_mode = excluded.delivery_mode
    returning id into v_attachment_id;

    if v_delivery_mode = 'secure_link' then
      insert into public.communication_sms_attachment_access_links (
        organization_id, delivery_intent_id, attachment_id, token_hash
      ) values (
        p_organization_id, intent.id, v_attachment_id,
        decode(v_attachment ->> 'access_token_hash', 'hex')
      )
      on conflict (token_hash) do nothing;
    end if;
  end if;

  -- 15. Hand the send to the outbox, scheduled for quiet hours.
  insert into public.communication_outbox_events (
    organization_id, delivery_intent_id, channel, available_at
  ) values (
    p_organization_id, intent.id, 'sms', available
  );

  return intent;
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_communication_sms_outbox_event()
 RETURNS TABLE(outbox_event_id uuid, delivery_intent_id uuid, organization_id uuid, twilio_account_id uuid, subaccount_sid text, messaging_service_sid text, claim_token uuid, attempt_number integer, recipient_phone text, sender_phone text, body text, encoding text, segment_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  candidate record;
  recipient public.client_contact_methods;
  sender public.communication_sms_sender_identities;
  route record;
  account public.communication_twilio_accounts;
  latest_consent text;
  snapshot public.communication_sms_message_snapshots;
  reservation_state text;
  available timestamptz;
  new_claim_token uuid;
  new_attempt integer;
  hold_message text;
begin
  for candidate in
    select event.id as event_id, event.delivery_intent_id, event.attempt_count,
      intent.organization_id, intent.client_id, intent.client_contact_method_id,
      intent.recipient_phone, intent.sms_sender_identity_id
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.channel = 'sms' and event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    -- 1. Recipient still an active phone on this customer, unchanged from the frozen E.164 number.
    recipient := null;
    select method.* into recipient
    from public.client_contact_methods method
    join public.clients client
      on client.organization_id = method.organization_id and client.id = method.client_id
    where method.organization_id = candidate.organization_id
      and method.id = candidate.client_contact_method_id
      and method.client_id = candidate.client_id
      and method.kind = 'phone'
      and client.deleted_at is null
    for share of method, client;

    if recipient.id is null or ('+' || recipient.normalized_value) <> candidate.recipient_phone then
      perform private.communication_sms_release_reservation(candidate.delivery_intent_id);
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'recipient_no_longer_eligible',
        failure_message = 'The queued phone number is no longer active for this customer.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The queued phone number is no longer active for this customer.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 2. A customer STOP after enqueue is a global opt-out: cancel rather than send. Consent is derived from the
    --    append-only events; the governing event for the number is the most recent opt-in/opt-out (HELP never
    --    changes eligibility). A global opt-out therefore beats any earlier subject opt-in, which is exactly the
    --    STOP-racing-a-claim case. Subject scope was fully enforced at enqueue and cannot tighten afterwards.
    latest_consent := (
      select case when governing.event_kind = 'opt_out' then 'opted_out' else 'opted_in' end
      from public.communication_sms_consent_events governing
      where governing.organization_id = candidate.organization_id
        and governing.client_contact_method_id = candidate.client_contact_method_id
        and governing.event_kind in ('opt_in', 'opt_out')
      order by governing.occurred_at desc, governing.received_at desc, governing.id desc
      limit 1
    );
    if latest_consent is distinct from 'opted_in' then
      perform private.communication_sms_release_reservation(candidate.delivery_intent_id);
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'recipient_opted_out',
        failure_message = 'This customer opted out of text messages before this one was sent.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This customer opted out of text messages before this one was sent.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 3. Sending number: must still exist and be live. A released number is gone for good (cancel); any other
    --    not-ready state is transient (defer and re-check).
    sender := null;
    select s.* into sender
    from public.communication_sms_sender_identities s
    where s.organization_id = candidate.organization_id and s.id = candidate.sms_sender_identity_id
    for share of s;

    if sender.id is null or sender.lifecycle_state = 'released' then
      perform private.communication_sms_release_reservation(candidate.delivery_intent_id);
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'sms_sender_unavailable',
        failure_message = 'The number this text would have sent from is no longer available.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The number this text would have sent from is no longer available.'
      where id = candidate.event_id;
      continue;
    end if;

    if sender.lifecycle_state <> 'ready' or not sender.capable_sms
      or sender.country_code is null or sender.sender_type is null then
      update public.communication_delivery_intents
      set failure_code = 'sms_sender_not_ready',
        failure_message = 'This SMS number is not ready to send right now. UCRM will try again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '15 minutes',
        last_error = 'This SMS number is not ready to send right now. UCRM will try again.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 4. The route (Stage 10 Part 5), the same check enqueue ran. A country Uplift turned off, or a number that
    --    cannot text it, cancels and returns the held balance; a missing plan, US registration or an outbound
    --    hold defers, never cancels -- inbound and STOP/START stay available, and a lifted pause re-runs it.
    select * into route
    from private.communication_sms_route_check(
      candidate.organization_id, sender, private.sms_phone_country(candidate.recipient_phone)
    );
    if not route.ok and route.code in ('destination_off', 'destination_setting_up', 'sender_wrong_country',
      'unknown_country') then
      perform private.communication_sms_release_reservation(candidate.delivery_intent_id);
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'sms_route_closed', failure_message = route.message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null, last_error = route.message
      where id = candidate.event_id;
      continue;
    elsif not route.ok then
      hold_message := case when route.code = 'outbound_paused'
        then 'Outbound texting is paused for this organization. UCRM will try again when it resumes.'
        else 'This organization is not ready to send SMS right now. UCRM will try again.' end;
      update public.communication_delivery_intents
      set failure_code = 'sms_outbound_not_ready', failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '5 minutes', last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    -- 5. The Twilio subaccount and Messaging Service the worker sends through must be present and live.
    account := null;
    select a.* into account
    from public.communication_twilio_accounts a
    where a.organization_id = candidate.organization_id
    for share of a;
    if account.id is null or account.messaging_service_sid is null
      or account.lifecycle_state not in ('ready', 'restricted') then
      update public.communication_delivery_intents
      set failure_code = 'sms_provider_account_not_ready',
        failure_message = 'This organization''s texting service is not ready. UCRM will try again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '15 minutes',
        last_error = 'This organization''s texting service is not ready. UCRM will try again.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 6. Quiet hours: if now falls inside the platform window, reschedule to the window end instead of sending.
    available := public.communication_sms_quiet_hours_available_at(now());
    if available > now() then
      update public.communication_delivery_intents
      set failure_code = 'sms_quiet_hours',
        failure_message = 'This text is waiting for quiet hours to end before it goes out.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = available,
        last_error = 'This text is waiting for quiet hours to end before it goes out.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 7. The credit reservation frozen at enqueue must still be holding funds; a released/settled reservation
    --    means this send has already been resolved and must not be sent again.
    -- Fixed 2026-09-23: qualified against the table alias -- was a bare `delivery_intent_id`, ambiguous with
    -- this function's own RETURNS TABLE column of the same name (see migration header).
    select r.state into reservation_state
    from public.communication_sms_credit_reservations r
    where r.delivery_intent_id = candidate.delivery_intent_id;
    if reservation_state is distinct from 'reserved' then
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'sms_reservation_not_held',
        failure_message = 'This text no longer has a held balance and was not sent.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This text no longer has a held balance and was not sent.'
      where id = candidate.event_id;
      continue;
    end if;

    -- Fixed 2026-09-23: same ambiguity as step 7, against communication_sms_message_snapshots.
    select snap.* into snapshot
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = candidate.delivery_intent_id;

    -- 8. Claim: mark the outbox processing under a fresh token, mark the intent claimed, and record the 'started'
    --    attempt so one attempt exists before the worker's provider call. The attempt number equals the new
    --    outbox attempt_count, so retries append distinct attempt rows.
    new_claim_token := gen_random_uuid();
    new_attempt := candidate.attempt_count + 1;

    update public.communication_outbox_events
    set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = new_attempt, last_error = null
    where id = candidate.event_id;
    update public.communication_delivery_intents
    set status = 'claimed', failure_code = null, failure_message = null
    where id = candidate.delivery_intent_id;
    insert into public.communication_sms_submission_attempts (
      organization_id, delivery_intent_id, attempt_number, claim_token, provider, outcome
    ) values (
      candidate.organization_id, candidate.delivery_intent_id, new_attempt, new_claim_token, 'twilio', 'started'
    );

    return query select candidate.event_id, candidate.delivery_intent_id, candidate.organization_id,
      account.id, account.subaccount_sid, account.messaging_service_sid, new_claim_token, new_attempt,
      candidate.recipient_phone, sender.phone_number, snapshot.body, snapshot.encoding, snapshot.segment_count;
    return;
  end loop;
end;
$function$;
