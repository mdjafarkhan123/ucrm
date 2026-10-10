import { json, type RequestEvent } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import {
	requireSetupEditor,
	requireSetupReader,
	setupWriteError,
	setupWriteLimited
} from '$lib/server/setup/access';
import { readOrganizationSetupVersion, readSetupServiceKeys } from '$lib/server/setup/catalogue';
import { readSetupHelpAnswers } from '$lib/server/setup/help';
import { readSetupState, setupAnswerFromRow } from '$lib/server/setup/read';
import { setupSendSchema } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { catalogueFacts, catalogueForServices, type SetupAnswers } from '$lib/setup/catalogue';
import { applicableHelpAnswers } from '$lib/setup/help';
import {
	SETUP_CONFIRMATIONS_VERSION,
	buildSetupCheck,
	setupConfirmations,
	setupSnapshotFactKeys
} from '$lib/setup/check';

// Client onboarding B13: Check and send to Uplift (plan §3.10). GET reads every task back; POST sends setup to
// Uplift, which keeps a frozen copy (ADR 0005). Owners and administrators only.

/** Everything the check reads: this client's questions, answers, and the newest send with its answers. */
async function readCheck(event: RequestEvent, organizationId: string) {
	const supabase = event.locals.supabase;
	const [catalogue, serviceKeys, state] = await Promise.all([
		readOrganizationSetupVersion(supabase, organizationId),
		readSetupServiceKeys(supabase, organizationId),
		readSetupState(supabase, organizationId)
	]);
	if (!catalogue || !serviceKeys || !state) return null;

	let sent: SetupAnswers | null = null;
	if (state.sent) {
		const { data, error } = await supabase
			.from('organization_setup_submissions')
			.select('answers')
			.eq('organization_id', organizationId)
			.eq('submission_number', state.sent.number)
			.single();
		if (error) return null;
		sent = {};
		for (const [key, row] of Object.entries(data.answers as Record<string, never>))
			sent[key] = setupAnswerFromRow(row);
	}

	const client = catalogueForServices(catalogue, serviceKeys);
	return {
		catalogue: client,
		serviceKeys,
		state,
		check: buildSetupCheck(client, state.answers, state.doneSections, sent),
		confirmations: setupConfirmations(serviceKeys)
	};
}

export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const read = await readCheck(event, organizationId);
	if (!read) return databaseError();

	// C3c: what Uplift filled in for the questions the client still has as "I need Uplift's help".
	let helpAnswers;
	try {
		helpAnswers = applicableHelpAnswers(
			await readSetupHelpAnswers(
				event.locals.supabase,
				organizationId,
				catalogueFacts(read.catalogue)
			),
			read.state.answers
		);
	} catch (error) {
		console.error('Could not read Uplift’s answers to setup help requests.', error);
		return databaseError();
	}

	return json(
		{
			...read.check,
			confirmations: read.confirmations,
			sent: read.state.sent,
			help_answers: helpAnswers
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Send to Uplift, or send changes after an earlier send. Refused while a task is unfinished, until every
// confirmation is ticked, and when nothing has changed since the last send.
export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupSendSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const read = await readCheck(event, organizationId);
	if (!read) return databaseError();

	const previous = read.state.sent?.number ?? 0;
	if (parsed.data.previous_number !== previous) return alreadySent();

	const unfinished = read.check.sections.filter((section) => section.status === 'unfinished');
	if (unfinished.length > 0)
		return validationError({
			form: `Finish ${unfinished.map((section) => section.title).join(', ')} first.`
		});
	if (read.state.sent && read.check.changed_count === 0)
		return validationError({ form: 'Nothing has changed since you last sent your setup.' });

	const ticked = new Set(parsed.data.confirmed);
	const problems: Record<string, string> = {};
	for (const confirmation of read.confirmations)
		if (!ticked.has(confirmation.key)) problems[confirmation.key] = 'Tick this to send.';
	if (Object.keys(problems).length > 0) return validationError(problems);

	const { data, error } = await event.locals.supabase.rpc('submit_organization_setup', {
		target_organization_id: organizationId,
		previous_number: previous,
		target_version_id: read.catalogue.versionId,
		package_service_keys: [...read.serviceKeys].sort(),
		fact_keys: setupSnapshotFactKeys(read.catalogue, read.state.answers),
		new_confirmations: read.confirmations,
		new_confirmations_version: SETUP_CONFIRMATIONS_VERSION
	});
	if (error) return setupWriteError(error);
	if ((data as { status?: string } | null)?.status === 'stale') return alreadySent();

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};

// The page was showing an older state: a double press, or someone sent from another device first.
function alreadySent() {
	return json(
		{
			error: 'Your setup was just sent from somewhere else. The page now shows the latest.',
			reason: 'stale'
		},
		{ status: 409 }
	);
}
