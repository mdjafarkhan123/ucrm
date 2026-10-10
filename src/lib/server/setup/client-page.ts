// Client onboarding C2: Jafar's view of one client's setup (plan §8). Every read is the service role's, behind
// the owner session the route checks. A send is read back against the setup version it was taken with (ADR
// 0005), so a question Jafar later rewords or removes still reads as the client saw it.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueFacts,
	catalogueForServices,
	sectionFacts,
	type SetupAnswers,
	type SetupCatalogue,
	type SetupCatalogueRow
} from '$lib/setup/catalogue';
import { buildSetupCheck, type SetupConfirmation } from '$lib/setup/check';
import type { ClientSetupSendView, ClientSetupView } from '$lib/setup/client-page';
import {
	setupSectionReview,
	type SetupReviewDecision,
	type SetupSectionReview
} from '$lib/setup/review';
import { setupFileIds } from '$lib/setup/files';
import { setupReuseSource } from '$lib/setup/reuse';
import { readOrganizationSetupVersion, readSetupServiceKeys } from '$lib/server/setup/catalogue';
import { readSetupFiles } from '$lib/server/setup/files';
import { readSetupHelpAnswers } from '$lib/server/setup/help';
import { readSetupState, setupAnswerFromRow } from '$lib/server/setup/read';
import { applicableHelpAnswers, setupHelpItems, type SetupHelpItem } from '$lib/setup/help';
import { setupReadyBlockers, type SetupReady, type SetupReadyBlocker } from '$lib/setup/ready';
import {
	SETUP_SETTING_LABELS,
	type SetupSettingCopy,
	type SetupSettingKey,
	type SetupSettingOutcome
} from '$lib/setup/settings-copy';

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

export function snapshotAnswers(raw: unknown): SetupAnswers {
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

/**
 * One send read back by task, its "Changed" marks against the send before it. Also gives the catalogue and
 * answers it was read with, for the review of the newest send.
 */
async function readSendView(
	supabase: Client,
	organizationId: string,
	row: SubmissionRow
): Promise<{ view: ClientSetupSendView; catalogue: SetupCatalogue; answers: SetupAnswers }> {
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

	const view: ClientSetupSendView = {
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
	return { view, catalogue, answers };
}

/**
 * Uplift's decision on each section of the newest send (C3), keyed by section. An acceptance made on an
 * earlier send holds only while that section's answers are unchanged, so those sends are read too — one read.
 */
export async function readSectionReviews(
	supabase: Client,
	organizationId: string,
	newest: { number: number; answers: SetupAnswers; catalogue: SetupCatalogue }
): Promise<Record<string, SetupSectionReview>> {
	const { data, error } = await supabase
		.from('organization_setup_section_reviews')
		.select(
			'section_key, decision, submission_number, note, question_keys, reviewed_by_email, reviewed_at'
		)
		.eq('organization_id', organizationId);
	if (error) throw error;
	const decisions = new Map(
		(data as SetupReviewDecision[]).map((decision) => [decision.section_key, decision])
	);

	const earlier = [
		...new Set(
			[...decisions.values()]
				.filter((d) => d.decision === 'accepted' && d.submission_number !== newest.number)
				.map((d) => d.submission_number)
		)
	];
	const earlierAnswers = new Map<number, SetupAnswers>();
	if (earlier.length > 0) {
		const result = await supabase
			.from('organization_setup_submissions')
			.select('submission_number, answers')
			.eq('organization_id', organizationId)
			.in('submission_number', earlier);
		if (result.error) throw result.error;
		for (const row of result.data)
			earlierAnswers.set(row.submission_number, snapshotAnswers(row.answers));
	}

	const reviews: Record<string, SetupSectionReview> = {};
	for (const section of newest.catalogue.sections)
		reviews[section.key] = setupSectionReview({
			decision: decisions.get(section.key) ?? null,
			newestNumber: newest.number,
			newestAnswers: newest.answers,
			factKeys: sectionFacts(section).map((fact) => fact.key),
			answersOf: (number) => earlierAnswers.get(number)
		});
	return reviews;
}

/** Answers changed since the newest send, as the client's own Check and send page counts them. */
async function unsentChanges(supabase: Client, organizationId: string, newest: SubmissionRow) {
	const [catalogue, serviceKeys, state] = await Promise.all([
		readOrganizationSetupVersion(supabase, organizationId),
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

/** C4: the current Ready for Uplift, and whether the account or its payment stops it. */
async function readReadyFacts(supabase: Client, organizationId: string) {
	const [ready, organization, provision, settings] = await Promise.all([
		supabase
			.from('organization_setup_ready')
			.select(
				'submission_number, ready_at, ready_by_email, time_zone, start_date, target_from, target_to'
			)
			.eq('organization_id', organizationId)
			.maybeSingle(),
		supabase
			.from('organizations')
			.select('lifecycle_status')
			.eq('id', organizationId)
			.maybeSingle(),
		supabase
			.from('platform_onboarding_application_provisions')
			.select('platform_onboarding_applications(payment_reversed_at)')
			.eq('organization_id', organizationId)
			.eq('status', 'succeeded'),
		supabase
			.from('organization_settings')
			.select('timezone')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);
	for (const result of [ready, organization, provision, settings])
		if (result.error) throw result.error;
	// The database does not limit a business to one paid application, so any reversed payment counts.
	const reversed = (provision.data ?? []).some(
		(row) =>
			(row.platform_onboarding_applications as { payment_reversed_at: string | null } | null)
				?.payment_reversed_at
	);
	return {
		ready: (ready.data as SetupReady | null) ?? null,
		account: {
			paused: organization.data?.lifecycle_status !== 'active',
			payment_reversed: reversed
		},
		timeZone: settings.data?.timezone ?? 'UTC'
	};
}

/** C5: the last copy of each CRM setting from accepted answers, in the Setup tab's order. */
async function readSetupSettingCopies(
	supabase: Client,
	organizationId: string
): Promise<SetupSettingCopy[]> {
	const { data, error } = await supabase
		.from('organization_setup_settings_copies')
		.select('setting_key, outcome, checked_at')
		.eq('organization_id', organizationId);
	if (error) throw error;
	const order = Object.keys(SETUP_SETTING_LABELS);
	return data
		.map((row) => ({
			setting: row.setting_key as SetupSettingKey,
			outcome: row.outcome as SetupSettingOutcome,
			checked_at: row.checked_at
		}))
		.sort((a, b) => order.indexOf(a.setting) - order.indexOf(b.setting));
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
	const [sendsResult, remindersResult, readyFacts, settingsCopies] = await Promise.all([
		supabase
			.from('organization_setup_submissions')
			.select('submission_number, submitted_at, submitted_by_name, submitted_by_email')
			.eq('organization_id', organizationId)
			.order('submission_number', { ascending: false }),
		supabase
			.from('organization_setup_reminders')
			.select('paused_at, next_due_at, reminders_sent, last_sent_at')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		readReadyFacts(supabase, organizationId),
		readSetupSettingCopies(supabase, organizationId)
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
	let reviews: Record<string, SetupSectionReview> | null = null;
	let help: SetupHelpItem[] | null = null;
	let helpUnits: ClientSetupView['help_units'] = { country: null, currency: null };
	let unsent = 0;
	let readyBlockers: SetupReadyBlocker[] | null = null;
	if (wanted !== null && newestNumber !== null) {
		const [row, newest] = await Promise.all([
			readSubmission(supabase, organizationId, wanted),
			wanted === newestNumber ? null : readSubmission(supabase, organizationId, newestNumber)
		]);
		if (!row) return null;
		const [read, changes] = await Promise.all([
			readSendView(supabase, organizationId, row),
			unsentChanges(supabase, organizationId, newest ?? row)
		]);
		send = read.view;
		unsent = changes;
		// Decisions are made on the newest send only, so an earlier one is shown without them.
		if (wanted === newestNumber) {
			const facts = catalogueFacts(read.catalogue);
			const [readReviews, helpAnswers] = await Promise.all([
				readSectionReviews(supabase, organizationId, {
					number: wanted,
					answers: read.answers,
					catalogue: read.catalogue
				}),
				readSetupHelpAnswers(supabase, organizationId, facts)
			]);
			reviews = readReviews;
			// C3c: Uplift's to-do — the help requests of this send, with any answer Uplift has recorded.
			help = setupHelpItems(send.sections, facts, applicableHelpAnswers(helpAnswers, read.answers));
			readyBlockers = setupReadyBlockers({
				account: readyFacts.account,
				sections: send.sections,
				reviews,
				help
			});
			helpUnits = {
				country: read.answers['business.country']?.value ?? null,
				currency: read.answers['business.currency']?.value ?? null
			};
		}
	}

	return {
		sends,
		send,
		reviews,
		help,
		help_units: helpUnits,
		unsent_changes: unsent,
		reminders: remindersResult.data,
		ready: readyFacts.ready,
		ready_blockers:
			newestNumber === null
				? setupReadyBlockers({ account: readyFacts.account, sections: null, reviews: {}, help: [] })
				: readyBlockers,
		time_zone: readyFacts.timeZone,
		settings_copies: settingsCopies
	};
}
