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
import { readSetupState } from '$lib/server/setup/read';
import { setupSectionDoneSchema } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	missingRequiredFacts,
	sectionFacts,
	sectionStatus,
	setupSection,
	setupValueError,
	type SetupAnswers
} from '$lib/setup/catalogue';

// One section's saved answers, plus what the CRM already knows that could answer a question nobody has
// answered yet. A suggestion is only shown in the field; it becomes an answer when the administrator
// keeps it.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const section = setupSection(event.params.section);
	if (!section) return notFound('That setup section could not be found.');

	const organizationId = check.auth.organization.id;
	const [state, settingsResult, profileResult] = await Promise.all([
		readSetupState(event.locals.supabase, organizationId),
		event.locals.supabase
			.from('organization_settings')
			.select('trade, phone')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', check.auth.user.id)
			.maybeSingle()
	]);
	if (!state || settingsResult.error) return databaseError();

	const known: Record<string, string | null | undefined> = {
		'business.public_name': check.auth.organization.name,
		'business.trade': settingsResult.data?.trade,
		'business.public_phone': settingsResult.data?.phone,
		'business.contact_name': profileResult.data?.full_name,
		'business.contact_email': check.auth.user.email
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
			answers,
			suggestions,
			status: sectionStatus(section, state.answers, markedDone)
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Marks the section done, or reopens it. Done is refused while a required question has no answer at all,
// and says which — "I don't have this yet" and "I need Uplift's help" both count as answers.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;

	const section = setupSection(event.params.section);
	if (!section) return notFound('That setup section could not be found.');

	const organizationId = check.auth.organization.id;
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

		const missing = missingRequiredFacts(section, state.answers);
		if (missing.length > 0)
			return validationError(
				Object.fromEntries(missing.map((fact) => [fact.key, 'This one still needs an answer.']))
			);
	}

	const { data, error } = await event.locals.supabase.rpc('set_organization_setup_section_done', {
		target_organization_id: organizationId,
		target_section_key: section.key,
		is_done: parsed.data.done
	});
	if (error) return setupWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
