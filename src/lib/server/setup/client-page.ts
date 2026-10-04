// Client onboarding C2: Jafar's view of one client's setup (plan §8). Every read is the service role's, behind
// the owner session the route checks. A send is read back against the setup version it was taken with (ADR
// 0005), so a question Jafar later rewords or removes still reads as the client saw it.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueFacts,
	catalogueForServices,
	type SetupAnswers,
	type SetupCatalogueRow
} from '$lib/setup/catalogue';
import { buildSetupCheck, type SetupConfirmation } from '$lib/setup/check';
import type { ClientSetupSendView, ClientSetupView } from '$lib/setup/client-page';
import { setupFileIds } from '$lib/setup/files';
import { setupReuseSource } from '$lib/setup/reuse';
import { readSetupCatalogue, readSetupServiceKeys } from '$lib/server/setup/catalogue';
import { readSetupFiles } from '$lib/server/setup/files';
import { readSetupState, setupAnswerFromRow } from '$lib/server/setup/read';

type Client = SupabaseClient<Database>;

type SubmissionRow = {
	submission_number: number;
	setup_version_id: string;
	service_keys: string[];
	answers: unknown;
	confirmations: unknown;
	confirmations_version: string;
	submitted_by_name: string;
	submitted_by_email: string;
	submitted_at: string;
};

const SUBMISSION_COLUMNS =
	'submission_number, setup_version_id, service_keys, answers, confirmations, confirmations_version, submitted_by_name, submitted_by_email, submitted_at';

function snapshotAnswers(raw: unknown): SetupAnswers {
	const answers: SetupAnswers = {};
	for (const [key, row] of Object.entries((raw ?? {}) as Record<string, never>))
		answers[key] = setupAnswerFromRow(row);
	return answers;
}

async function readSubmission(supabase: Client, organizationId: string, number: number) {
	const { data, error } = await supabase
		.from('organization_setup_submissions')
		.select(SUBMISSION_COLUMNS)
		.eq('organization_id', organizationId)
		.eq('submission_number', number)
		.maybeSingle();
	if (error) throw error;
	return data as SubmissionRow | null;
}

/** One send read back by task, its "Changed" marks against the send before it. */
async function readSendView(
	supabase: Client,
	organizationId: string,
	row: SubmissionRow
): Promise<ClientSetupSendView> {
	const [catalogueResult, previous] = await Promise.all([
		supabase.rpc('owner_setup_version_catalogue', { target_version_id: row.setup_version_id }),
		row.submission_number > 1
			? readSubmission(supabase, organizationId, row.submission_number - 1)
			: Promise.resolve(null)
	]);
	if (catalogueResult.error || !catalogueResult.data)
		throw catalogueResult.error ?? new Error('The setup version of a send is missing.');

	const catalogue = catalogueForServices(
		buildSetupCatalogue(catalogueResult.data as unknown as SetupCatalogueRow),
		new Set(row.service_keys)
	);
	const answers = snapshotAnswers(row.answers);
	// Every task was done when it was sent, so each one reads as done.
	const check = buildSetupCheck(
		catalogue,
		answers,
		new Set(catalogue.sections.map((section) => section.key)),
		previous ? snapshotAnswers(previous.answers) : null
	);

	// The files of each photo or file answer; one read for all of them. A reused answer shows its source's.
	const facts = catalogueFacts(catalogue);
	const fileIds = new Map<string, string[]>();
	const protectedQuestions: string[] = [];
	for (const section of check.sections)
		for (const item of section.items) {
			if (item.state !== 'answered') continue;
			const source = setupReuseSource(answers[item.key]?.value);
			const fact = facts.get(source ?? item.key);
			if (fact?.kind === 'protected_file') protectedQuestions.push(item.key);
			if (fact?.kind !== 'file') continue;
			const ids = setupFileIds(answers[source ?? item.key]?.value);
			if (ids.length) fileIds.set(item.key, ids);
		}
	const allIds = [...new Set([...fileIds.values()].flat())];
	const found = new Map(
		(await readSetupFiles(organizationId, allIds)).map((file) => [file.id, file])
	);
	const files: ClientSetupSendView['files'] = {};
	for (const [key, ids] of fileIds) files[key] = ids.flatMap((id) => found.get(id) ?? []);

	return {
		number: row.submission_number,
		submitted_at: row.submitted_at,
		submitted_by_name: row.submitted_by_name,
		submitted_by_email: row.submitted_by_email,
		confirmations: row.confirmations as SetupConfirmation[],
		confirmations_version: row.confirmations_version,
		sections: check.sections,
		compared_with: previous ? previous.submission_number : null,
		changed_count: check.changed_count,
		files,
		protected_questions: protectedQuestions
	};
}

/** Answers changed since the newest send, as the client's own Check and send page counts them. */
async function unsentChanges(supabase: Client, organizationId: string, newest: SubmissionRow) {
	const [catalogue, serviceKeys, state] = await Promise.all([
		readSetupCatalogue(supabase),
		readSetupServiceKeys(supabase, organizationId),
		readSetupState(supabase, organizationId)
	]);
	if (!catalogue || !serviceKeys || !state) throw new Error('Setup could not be read.');
	return buildSetupCheck(
		catalogueForServices(catalogue, serviceKeys),
		state.answers,
		state.doneSections,
		snapshotAnswers(newest.answers)
	).changed_count;
}

/**
 * The Setup tab's view of one client: every send, `sendNumber` (or the newest) read back, and the reminders.
 * Returns null when the send asked for does not exist. Throws when the database cannot be read.
 */
export async function readClientSetupView(
	supabase: Client,
	organizationId: string,
	sendNumber: number | null
): Promise<ClientSetupView | null> {
	const [sendsResult, remindersResult] = await Promise.all([
		supabase
			.from('organization_setup_submissions')
			.select('submission_number, submitted_at, submitted_by_name, submitted_by_email')
			.eq('organization_id', organizationId)
			.order('submission_number', { ascending: false }),
		supabase
			.from('organization_setup_reminders')
			.select('paused_at, next_due_at, reminders_sent, last_sent_at')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);
	if (sendsResult.error) throw sendsResult.error;
	if (remindersResult.error) throw remindersResult.error;

	const sends = sendsResult.data.map((row) => ({
		number: row.submission_number,
		submitted_at: row.submitted_at,
		submitted_by_name: row.submitted_by_name,
		submitted_by_email: row.submitted_by_email
	}));
	const newestNumber = sends[0]?.number ?? null;
	const wanted = sendNumber ?? newestNumber;
	if (sendNumber !== null && !sends.some((send) => send.number === sendNumber)) return null;

	let send: ClientSetupSendView | null = null;
	let unsent = 0;
	if (wanted !== null && newestNumber !== null) {
		const [row, newest] = await Promise.all([
			readSubmission(supabase, organizationId, wanted),
			wanted === newestNumber ? null : readSubmission(supabase, organizationId, newestNumber)
		]);
		if (!row) return null;
		[send, unsent] = await Promise.all([
			readSendView(supabase, organizationId, row),
			unsentChanges(supabase, organizationId, newest ?? row)
		]);
	}

	return { sends, send, unsent_changes: unsent, reminders: remindersResult.data };
}
