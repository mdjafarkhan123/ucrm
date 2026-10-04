-- Client onboarding B3b: the approved starter content's stage 1, "Your business"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish. Nothing a client sees changes until he publishes it.
--
-- Every question already asked keeps its key and answer type, so the answers clients gave are kept and show
-- again. New yes/no questions decide when a follow-up is asked — the legal name only when it differs, the
-- final approver only when the main contact is not the one — and the setup page suggests their answer from
-- what a client already gave, for the client to confirm.

-- 1. Loading one stage of starter content into the draft ------------------------------------------------

-- B3b–B12 each load one stage this way. It starts a draft from the published version if there is none, then
-- replaces that stage's headings and questions with `new_items`, in order. A stage the draft does not have
-- yet is added at the end. A built-in question's answer rules live in code (ADR 0006), so its row carries only
-- wording, flags and its "show only if" rule.
create or replace function private.setup_load_starter_stage(
	target_stage_key text,
	stage_title text,
	stage_description text,
	stage_service_key text,
	new_items jsonb
)
returns void
language plpgsql
set search_path = ''
as $$
declare
	draft_id uuid;
	refused_label text;
	problem text;
begin
	perform public.owner_start_setup_draft('migration');
	select v.id into draft_id from public.setup_versions v where v.status = 'draft';

	-- An answered question keeps its answer type: its answers would no longer fit.
	select n.label into refused_label
	from jsonb_to_recordset(new_items) as n(fact_key text, label text, kind text, built_in boolean)
	join public.setup_items i on i.fact_key = n.fact_key
	join public.setup_versions p on p.id = i.version_id and p.status = 'published'
	where (i.built_in is distinct from coalesce(n.built_in, false) or i.kind is distinct from n.kind)
		and exists (select 1 from public.organization_setup_answers a where a.fact_key = n.fact_key)
	limit 1;
	if refused_label is not null then
		raise exception 'Clients have answered "%", so its answer type cannot change.', refused_label
			using errcode = 'check_violation';
	end if;

	if exists (select 1 from public.setup_stages s where s.version_id = draft_id and s.stage_key = target_stage_key) then
		update public.setup_stages set title = stage_title, description = stage_description,
			service_key = stage_service_key
		where version_id = draft_id and stage_key = target_stage_key;
	else
		insert into public.setup_stages (version_id, stage_key, title, description, service_key, position)
		values (
			draft_id, target_stage_key, stage_title, stage_description, stage_service_key,
			(select coalesce(max(s.position), 0) + 1 from public.setup_stages s where s.version_id = draft_id)
		);
	end if;

	delete from public.setup_items i where i.version_id = draft_id and i.stage_key = target_stage_key;

	insert into public.setup_items (
		version_id, stage_key, position, item_type, fact_key, label, hint, built_in, required, can_defer, kind,
		options, allow_other, max_choices, file_kinds, max_files, list_fields, max_rows, pick_from, min_choices,
		ordered, reuse_from, max_length, show_if
	)
	select draft_id, target_stage_key, n.ordinality::integer, n.item ->> 'type', n.item ->> 'fact_key',
		n.item ->> 'label', n.item ->> 'hint', coalesce((n.item ->> 'built_in')::boolean, false),
		coalesce((n.item ->> 'required')::boolean, false), coalesce((n.item ->> 'can_defer')::boolean, false),
		n.item ->> 'kind', n.item -> 'options', coalesce((n.item ->> 'allow_other')::boolean, false),
		(n.item ->> 'max_choices')::smallint,
		case when n.item ? 'file_kinds' then array(select jsonb_array_elements_text(n.item -> 'file_kinds')) end,
		(n.item ->> 'max_files')::smallint, n.item -> 'list_fields', (n.item ->> 'max_rows')::smallint,
		n.item ->> 'pick_from', (n.item ->> 'min_choices')::smallint,
		coalesce((n.item ->> 'ordered')::boolean, false), n.item ->> 'reuse_from',
		(n.item ->> 'max_length')::integer, n.item -> 'show_if'
	from jsonb_array_elements(new_items) with ordinality as n(item, ordinality);

	-- The same check a save in the editor makes: every rule, pick and reuse points somewhere real.
	problem := private.setup_version_rule_problem(draft_id);
	if problem is not null then
		raise exception '%', problem using errcode = 'check_violation';
	end if;

	-- An editor already open on this draft is told to reload rather than save over it.
	update public.setup_versions set revision = revision + 1, updated_by_email = 'migration' where id = draft_id;
end;
$$;

revoke all on function private.setup_load_starter_stage(text, text, text, text, jsonb)
	from public, anon, authenticated;

-- 2. Stage 1 — Your business -------------------------------------------------------------------------

select private.setup_load_starter_stage(
	'business',
	'Your business',
	'The name, people and contact details Uplift builds everything else around.',
	null,
	$items$[
		{"type": "heading", "label": "Business identity",
			"hint": "How your business is known. Plain facts are enough — Uplift writes the polished wording."},
		{"type": "question", "fact_key": "business.public_name", "built_in": true, "required": true,
			"label": "What business name do customers know you by?",
			"hint": "Use the name on your van, signs or invoices."},
		{"type": "question", "fact_key": "business.legal_name_differs", "built_in": true, "required": true,
			"label": "Is your legal business name different?",
			"hint": "The name you are registered under, if it is not the one above."},
		{"type": "question", "fact_key": "business.legal_name", "built_in": true, "required": true,
			"label": "What is the legal business name?",
			"show_if": [{"fact_key": "business.legal_name_differs", "values": ["yes"]}]},
		{"type": "question", "fact_key": "business.trade", "built_in": true, "required": true,
			"label": "What trade best describes the business?"},
		{"type": "question", "fact_key": "business.type", "built_in": true, "required": true,
			"label": "What kind of business is it?"},
		{"type": "question", "fact_key": "business.started_on", "kind": "date",
			"label": "When did the business start operating?",
			"hint": "Only know the month and year? Pick the 1st of that month."},

		{"type": "heading", "label": "People Uplift works with",
			"hint": "The person we contact during setup, and who gives the final go-ahead before launch."},
		{"type": "question", "fact_key": "business.contact_name", "built_in": true, "required": true,
			"label": "Who is our main contact during setup?"},
		{"type": "question", "fact_key": "business.contact_role", "kind": "text", "max_length": 80,
			"required": true, "label": "Their role in the business", "hint": "For example: Owner, Office manager."},
		{"type": "question", "fact_key": "business.contact_email", "built_in": true, "required": true,
			"label": "Main contact email"},
		{"type": "question", "fact_key": "business.contact_phone", "built_in": true, "required": true,
			"label": "Main contact phone"},
		{"type": "question", "fact_key": "business.contact_is_approver", "built_in": true, "required": true,
			"label": "Will this person approve the finished system?",
			"hint": "Before launch, someone confirms everything is right. It can be the same person."},
		{"type": "question", "fact_key": "business.approver_name", "built_in": true, "required": true,
			"label": "Who gives final approval?",
			"show_if": [{"fact_key": "business.contact_is_approver", "values": ["no"]}]},
		{"type": "question", "fact_key": "business.approver_email", "built_in": true, "required": true,
			"label": "Their email",
			"show_if": [{"fact_key": "business.contact_is_approver", "values": ["no"]}]},
		{"type": "question", "fact_key": "business.approver_phone", "kind": "phone", "label": "Their phone",
			"show_if": [{"fact_key": "business.contact_is_approver", "values": ["no"]}]},
		{"type": "question", "fact_key": "business.update_recipients", "kind": "list", "max_rows": 5,
			"label": "Who else should receive setup updates?",
			"hint": "Optional. This does not give them access to your CRM.",
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "email", "label": "Email", "kind": "email", "required": true},
				{"key": "role", "label": "Role", "kind": "text", "required": false}
			]},

		{"type": "heading", "label": "How customers reach you",
			"hint": "The phone and email shown to customers. No business number yet? Say so and Uplift will help."},
		{"type": "question", "fact_key": "business.public_phone", "built_in": true, "required": true,
			"can_defer": true, "label": "What phone number should customers use today?",
			"hint": "Your website and Google profile use this too."},
		{"type": "question", "fact_key": "business.public_email", "built_in": true, "required": true,
			"can_defer": true, "label": "What email address should customers use?",
			"hint": "Your website and Google profile use this too."},
		{"type": "heading", "label": "Where you’re based",
			"hint": "Where you run the business from — your home is fine. It stays private unless you say otherwise."},
		{"type": "question", "fact_key": "business.country", "built_in": true, "required": true,
			"label": "Which country is the business registered in?",
			"hint": "Decides which local rules and providers apply to you."},
		{"type": "question", "fact_key": "business.address_line1", "built_in": true, "required": true,
			"can_defer": true, "label": "Street address"},
		{"type": "question", "fact_key": "business.address_line2", "built_in": true,
			"label": "Flat, unit or suite, if any"},
		{"type": "question", "fact_key": "business.address_city", "built_in": true, "required": true,
			"can_defer": true, "label": "Town or city"},
		{"type": "question", "fact_key": "business.address_region", "built_in": true,
			"label": "State, province or county"},
		{"type": "question", "fact_key": "business.address_postal_code", "built_in": true, "required": true,
			"can_defer": true, "label": "Postcode or ZIP code"},
		{"type": "question", "fact_key": "business.address_customers_visit", "built_in": true, "required": true,
			"label": "Do customers visit this address?",
			"hint": "A showroom, shop or office counts. A home used only as a base does not."},
		{"type": "question", "fact_key": "business.address_public", "built_in": true, "required": true,
			"label": "May this address be shown publicly?",
			"hint": "If not, customers only see your town and the areas you cover.",
			"show_if": [{"fact_key": "business.address_customers_visit", "values": ["yes"]}]},

		{"type": "heading", "label": "Language, time and money",
			"hint": "How words, times and prices appear across your system. None becomes your default until you confirm it here."},
		{"type": "question", "fact_key": "business.language", "built_in": true, "required": true,
			"label": "Which language do most customers use?",
			"hint": "Uplift delivers your website and campaigns in English. Another language is arranged separately."},
		{"type": "question", "fact_key": "business.timezone", "built_in": true, "required": true,
			"label": "Which time zone should schedules and reminders use?"},
		{"type": "question", "fact_key": "business.currency", "built_in": true, "required": true,
			"label": "Which currency do you charge in?", "hint": "Used on every quote, invoice and payment."},

		{"type": "heading", "label": "Availability",
			"hint": "When customers can reach you. Uplift uses this on your website, your Google profile and your reminders."},
		{"type": "question", "fact_key": "business.availability", "built_in": true, "required": true,
			"label": "When can customers normally reach you?"},
		{"type": "question", "fact_key": "business.hours", "built_in": true, "required": true,
			"label": "What are your normal customer-facing hours?",
			"show_if": [{"fact_key": "business.availability", "values": ["set_hours"]}]},
		{"type": "question", "fact_key": "business.after_hours", "kind": "yes_no", "required": true,
			"label": "Are emergency or after-hours calls accepted?",
			"show_if": [{"fact_key": "business.availability", "values": ["set_hours", "appointment_only"]}]},
		{"type": "question", "fact_key": "business.after_hours_details", "kind": "longtext", "max_length": 1000,
			"required": true, "can_defer": true, "label": "Describe the emergency or after-hours availability.",
			"hint": "For example: burst pipes and no heating only, any time, with a call-out charge.",
			"show_if": [{"fact_key": "business.after_hours", "values": ["yes"]}]},
		{"type": "question", "fact_key": "business.hours_seasonal_changes", "kind": "yes_no", "required": true,
			"label": "Do your hours change by season?"},
		{"type": "question", "fact_key": "business.hours_seasonal", "kind": "longtext", "max_length": 500,
			"required": true, "can_defer": true, "label": "What changes, and when?",
			"hint": "For example: closed in January, or longer hours from June to August.",
			"show_if": [{"fact_key": "business.hours_seasonal_changes", "values": ["yes"]}]},
		{"type": "question", "fact_key": "business.hours_exceptions", "built_in": true,
			"label": "Add known holidays or one-off closures.",
			"hint": "Days in the next year when you are closed or keep different hours. You can change these later in Settings."}
	]$items$::jsonb
);
