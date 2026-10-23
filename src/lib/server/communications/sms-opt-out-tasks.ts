import type { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { countryOptOutLanguages } from '$lib/communications/sms-opt-out-words';
import type { OptOutTask, TextingSetupQueue } from '$lib/jafar/texting-setup';

// Stage 10 Part 5d: the Texting setup page's opt-out word tasks. A business that asked for a country whose
// language is not English needs that language's words in its Twilio messaging service first; one task per
// business and language, however many of its countries share it (Mexico and Spain are both Spanish).

type Client = ReturnType<typeof getOwnerSupabaseClient>;

/** The languages Uplift already added for each business, beyond English. */
export async function addedOptOutLanguages(client: Client, organizationIds: string[]) {
	const added = new Map<string, Set<string>>();
	if (organizationIds.length === 0) return added;
	const { data, error } = await client
		.from('communication_sms_opt_out_languages')
		.select('organization_id, language')
		.in('organization_id', organizationIds);
	if (error) throw error;
	for (const row of data ?? []) {
		const languages = added.get(row.organization_id) ?? new Set<string>();
		languages.add(row.language);
		added.set(row.organization_id, languages);
	}
	return added;
}

/** The languages a business still needs before it texts a country. */
export function missingOptOutLanguages(country: string, added: Set<string> | undefined): string[] {
	return countryOptOutLanguages(country).filter((language) => !added?.has(language));
}

export function optOutTaskId(organizationId: string, language: string) {
	return `opt-out:${organizationId}:${language}`;
}

type RawQueue = Omit<TextingSetupQueue, 'tasks' | 'opt_out_tasks'> & {
	tasks: Omit<TextingSetupQueue['tasks'][number], 'opt_out_missing'>[];
};

/**
 * The queue with each country task's missing languages, the opt-out word tasks they make, and the counts
 * that include them. Languages added in the last day join the recently finished, for "Sam already did this".
 */
export async function withOptOutTasks(client: Client, queue: RawQueue): Promise<TextingSetupQueue> {
	const organizationIds = [...new Set(queue.tasks.map((task) => task.organization_id))];
	const added = await addedOptOutLanguages(client, organizationIds);

	const tasks = queue.tasks.map((task) => ({
		...task,
		opt_out_missing: missingOptOutLanguages(task.country, added.get(task.organization_id))
	}));

	const byId = new Map<string, OptOutTask>();
	for (const task of tasks) {
		for (const language of task.opt_out_missing) {
			const id = optOutTaskId(task.organization_id, language);
			const existing = byId.get(id);
			if (existing) {
				existing.countries.push(task.country);
				if (task.requested_at < existing.requested_at) existing.requested_at = task.requested_at;
				continue;
			}
			byId.set(id, {
				id,
				organization_id: task.organization_id,
				organization_name: task.organization_name,
				language,
				countries: [task.country],
				requested_at: task.requested_at,
				messaging_service_sid: null
			});
		}
	}
	const optOutTasks = [...byId.values()].sort((a, b) =>
		a.requested_at.localeCompare(b.requested_at)
	);

	const needServices = [...new Set(optOutTasks.map((task) => task.organization_id))];
	if (needServices.length) {
		const { data, error } = await client
			.from('communication_twilio_accounts')
			.select('organization_id, messaging_service_sid, created_at')
			.in('organization_id', needServices)
			.neq('lifecycle_state', 'closed')
			.order('created_at', { ascending: false });
		if (error) throw error;
		for (const task of optOutTasks) {
			task.messaging_service_sid =
				data?.find((row) => row.organization_id === task.organization_id)?.messaging_service_sid ??
				null;
		}
	}

	const { data: recent, error: recentError } = await client
		.from('communication_sms_opt_out_languages')
		.select('organization_id, language, added_at, added_by_name')
		.gt('added_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
	if (recentError) throw recentError;

	const oldest = [queue.summary.oldest_at, optOutTasks[0]?.requested_at]
		.filter((value): value is string => !!value)
		.sort()[0];

	return {
		...queue,
		summary: {
			...queue.summary,
			to_do: queue.summary.to_do + optOutTasks.length,
			oldest_at: oldest ?? null
		},
		recently_finished: [
			...queue.recently_finished,
			...(recent ?? []).map((row) => ({
				id: optOutTaskId(row.organization_id, row.language),
				kind: 'opt_out_added',
				at: row.added_at,
				who: row.added_by_name
			}))
		],
		tasks,
		opt_out_tasks: optOutTasks
	};
}
