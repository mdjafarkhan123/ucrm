// Client onboarding C3c: Uplift's answers to the questions a client asked help with (`$lib/setup/help`). The
// question is checked against the setup version the newest send was taken with, and the value against that
// question's own rules, the same ones the client's box applies. The database refuses an answer on anything but
// the newest send, or to a question that send did not ask help with, and records each one in Jafar's history.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueFacts,
	catalogueForServices,
	setupValueError,
	shownCatalogueFacts,
	storedSetupValue,
	type SetupCatalogueRow,
	type SetupFact
} from '$lib/setup/catalogue';
import { SETUP_ANSWER_MAX_BYTES, setupStoredBytes } from '$lib/setup/answer-values';
import { setupHelpAnswerForm, setupHelpAnswerFromRow, type SetupHelpAnswer } from '$lib/setup/help';
import { setupAnswerFromRow } from '$lib/server/setup/read';
import type { SetupHelpAnswerInput } from '$lib/server/validation/setup.schema';

type Client = SupabaseClient<Database>;

/** Every answer Uplift has recorded for this organization, keyed by question, read in words against `facts`. */
export async function readSetupHelpAnswers(
	supabase: Client,
	organizationId: string,
	facts: ReadonlyMap<string, SetupFact>
): Promise<Record<string, SetupHelpAnswer>> {
	const { data, error } = await supabase
		.from('organization_setup_help_answers')
		.select('fact_key, value, note, recorded_by_email, recorded_at')
		.eq('organization_id', organizationId);
	if (error) throw error;
	return Object.fromEntries(
		data.map((row) => [row.fact_key, setupHelpAnswerFromRow(facts.get(row.fact_key), row)])
	);
}

export type SetupHelpAnswerResult =
	| { status: 'saved' | 'unchanged' }
	| { status: 'stale'; latest_number: number }
	| { status: 'not_found'; message: string }
	| { status: 'invalid'; field: 'fact_key' | 'value' | 'note'; message: string };

export async function recordSetupHelpAnswer(
	supabase: Client,
	organizationId: string,
	actorEmail: string,
	input: SetupHelpAnswerInput
): Promise<SetupHelpAnswerResult> {
	const { data: send, error } = await supabase
		.from('organization_setup_submissions')
		.select('setup_version_id, service_keys, answers')
		.eq('organization_id', organizationId)
		.eq('submission_number', input.send)
		.maybeSingle();
	if (error) throw error;
	if (!send) return { status: 'not_found', message: 'That setup send does not exist.' };

	const catalogueResult = await supabase.rpc('owner_setup_version_catalogue', {
		target_version_id: send.setup_version_id
	});
	if (catalogueResult.error || !catalogueResult.data)
		throw catalogueResult.error ?? new Error('The setup version of a send is missing.');
	const catalogue = catalogueForServices(
		buildSetupCatalogue(catalogueResult.data as unknown as SetupCatalogueRow),
		new Set(send.service_keys)
	);

	const answers = Object.fromEntries(
		Object.entries((send.answers ?? {}) as Record<string, never>).map(([key, row]) => [
			key,
			setupAnswerFromRow(row)
		])
	);
	const fact = catalogueFacts(catalogue).get(input.fact_key);
	if (
		!fact ||
		!shownCatalogueFacts(catalogue, answers).has(fact.key) ||
		answers[fact.key]?.availability !== 'need_help'
	)
		return {
			status: 'invalid',
			field: 'fact_key',
			message: 'The client did not ask for help with this question in this send.'
		};

	let value: unknown = null;
	let note: string | null = null;
	if (setupHelpAnswerForm(fact) === 'note') {
		if (!input.note)
			return { status: 'invalid', field: 'note', message: 'Write what Uplift found or did.' };
		note = input.note;
	} else {
		if (!input.value) return { status: 'invalid', field: 'value', message: 'Enter an answer.' };
		const problem = setupValueError(fact, input.value, answers);
		if (problem) return { status: 'invalid', field: 'value', message: problem };
		value = storedSetupValue(fact, input.value);
		if (setupStoredBytes(value) > SETUP_ANSWER_MAX_BYTES)
			return {
				status: 'invalid',
				field: 'value',
				message: 'This is too long to save. Shorten some entries or remove a few.'
			};
	}

	const { data, error: saveError } = await supabase.rpc('owner_answer_setup_help', {
		target_organization_id: organizationId,
		target_fact_key: fact.key,
		seen_number: input.send,
		new_value: value as Json,
		new_note: note ?? '',
		actor_email: actorEmail
	});
	if (saveError) throw saveError;
	return data as unknown as SetupHelpAnswerResult;
}
