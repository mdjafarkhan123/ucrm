import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import {
	requireSetupEditor,
	requireSetupReader,
	setupWriteError,
	setupWriteLimited
} from '$lib/server/setup/access';
import { readOrganizationSetupCatalogue } from '$lib/server/setup/catalogue';
import { readSetupState } from '$lib/server/setup/read';
import { setupSectionDoneSchema } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { countryCurrency } from '$lib/settings/countries';
import { followUpSuggestions } from '$lib/setup/follow-ups';
import { setupHoursFromBusinessHours } from '$lib/setup/hours';
import {
	catalogueSection,
	earlierAnswersFor,
	missingRequiredFacts,
	sectionFacts,
	sectionStatus,
	setupAnswerShortfall,
	setupValueError,
	shownCatalogueFacts,
	type SetupAnswers
} from '$lib/setup/catalogue';

// One section's questions as published now and its saved answers, plus what the CRM already knows that could answer a question nobody has
// answered yet. A suggestion is only shown in the field; it becomes an answer when the administrator
// keeps it.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const [catalogue, state, settingsResult, hoursResult, profileResult] = await Promise.all([
		readOrganizationSetupCatalogue(event.locals.supabase, organizationId),
		readSetupState(event.locals.supabase, organizationId),
		event.locals.supabase
			.from('organization_settings')
			.select(
				'trade, phone, address_line1, address_line2, city, region, postal_code, country_code, timezone, timezone_confirmed_at, currency_code, currency_confirmed_at, hours_mode'
			)
			.eq('organization_id', organizationId)
			.maybeSingle(),
		event.locals.supabase
			.from('organization_business_hours')
			.select('weekday, period_index, is_open, is_open_24h, opens_at, closes_at')
			.eq('organization_id', organizationId),
		event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', check.auth.user.id)
			.maybeSingle()
	]);
	if (!catalogue || !state || settingsResult.error || hoursResult.error) return databaseError();
	const section = catalogueSection(catalogue, event.params.section);
	if (!section) return notFound('That setup section could not be found.');

	const settings = settingsResult.data;
	const country = state.answers['business.country']?.value ?? settings?.country_code;
	const hours = setupHoursFromBusinessHours(settings?.hours_mode, hoursResult.data ?? []);

	// A time zone or currency nobody confirmed in Settings is only the account's starting default, so it
	// is not offered as something the business said. The currency then falls back to the country's.
	const known: Record<string, string | null | undefined> = {
		'business.public_name': check.auth.organization.name,
		'business.trade': settings?.trade,
		'business.public_phone': settings?.phone,
		'business.contact_name': profileResult.data?.full_name,
		'business.contact_email': check.auth.user.email,
		'business.country': settings?.country_code,
		'business.address_line1': settings?.address_line1,
		'business.address_line2': settings?.address_line2,
		'business.address_city': settings?.city,
		'business.address_region': settings?.region,
		'business.address_postal_code': settings?.postal_code,
		'business.timezone': settings?.timezone_confirmed_at ? settings.timezone : null,
		'business.currency': settings?.currency_confirmed_at
			? settings.currency_code
			: countryCurrency(country),
		'business.hours': hours ? JSON.stringify(hours) : null,
		// Work is usually booked in during the hours customers can reach the business, so those start it.
		'crm.work_hours':
			(state.answers['business.hours']?.availability === 'have'
				? state.answers['business.hours'].value
				: null) ?? (hours ? JSON.stringify(hours) : null),
		...followUpSuggestions(state.answers, settings?.hours_mode)
	};

	const answers: SetupAnswers = {};
	const suggestions: Record<string, string> = {};
	for (const fact of sectionFacts(section)) {
		const answer = state.answers[fact.key];
		if (answer) {
			answers[fact.key] = answer;
			continue;
		}
		// Only something that would pass as an answer is worth suggesting.
		const value = known[fact.key]?.trim();
		if (value && !setupValueError(fact, value)) suggestions[fact.key] = value;
	}

	const markedDone = state.doneSections.has(section.key);
	return json(
		{
			key: section.key,
			section,
			answers,
			// Earlier sections' answers this section's "show only if" rules read, for questions asked now.
			earlier_answers: earlierAnswersFor(section, catalogue, state.answers),
			suggestions,
			// For amount answers (A5d): money is given in the business's currency, and the country suggests
			// miles or kilometres.
			country: country ?? null,
			currency:
				state.answers['business.currency']?.value ??
				known['business.currency'] ??
				settings?.currency_code ??
				null,
			status: sectionStatus(
				section,
				state.answers,
				markedDone,
				shownCatalogueFacts(catalogue, state.answers)
			)
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Marks the section done, or reopens it. Done is refused while a required question has no answer at all,
// and says which — "I don't have this yet" and "I need Uplift's help" both count as answers.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const catalogue = await readOrganizationSetupCatalogue(event.locals.supabase, organizationId);
	if (!catalogue) return databaseError();
	const section = catalogueSection(catalogue, event.params.section);
	if (!section) return notFound('That setup section could not be found.');

	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setupSectionDoneSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	if (parsed.data.done) {
		const state = await readSetupState(event.locals.supabase, organizationId);
		if (!state) return databaseError();

		const shown = shownCatalogueFacts(catalogue, state.answers);
		const problems: Record<string, string> = {};
		for (const fact of missingRequiredFacts(section, state.answers, shown))
			problems[fact.key] = 'This one still needs an answer.';
		// A5f: a pick with too few picks.
		for (const fact of sectionFacts(section)) {
			const shortfall = shown.has(fact.key) ? setupAnswerShortfall(fact, state.answers) : null;
			if (shortfall) problems[fact.key] = shortfall;
		}
		if (Object.keys(problems).length > 0) return validationError(problems);
	}

	const { data, error } = await event.locals.supabase.rpc('set_organization_setup_section_done', {
		target_organization_id: organizationId,
		target_section_key: section.key,
		is_done: parsed.data.done
	});
	if (error) return setupWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
