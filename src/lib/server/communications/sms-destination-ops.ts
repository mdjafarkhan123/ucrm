import { json } from '@sveltejs/kit';
import type { OwnerSession } from '$lib/server/auth/owner';
import type { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Stage 10 Part 5b: the Control Room's country work. People there sign in by email and have no Supabase user,
// so the commands get no user id; the name below goes in the country's history instead ("Sam already did
// this"), and the email in the access audit.

type Client = ReturnType<typeof getOwnerSupabaseClient>;

/** The name a country's history shows for whoever did it: a teammate's name, else Jafar, the owner. */
export function destinationActorName(session: OwnerSession): string {
	if (session.name?.trim()) return session.name.trim();
	return session.role === null ? 'Jafar' : session.email;
}

type HistoryRow = { kind: string; at: string; who: string | null };

/** Who finished a country first, from its newest switched-on or closed history row. */
export function finishedBy(history: HistoryRow[] | null | undefined) {
	const row = history?.find((event) => event.kind === 'switched_on' || event.kind === 'closed');
	return row ? { kind: row.kind, at: row.at, who: row.who } : null;
}

/** One business country, or null when the id matches nothing. */
export async function loadDestination(client: Client, destinationId: string) {
	const { data, error } = await client
		.from('communication_sms_destinations')
		.select('id, organization_id, country_code, status')
		.eq('id', destinationId)
		.maybeSingle();
	if (error) throw error;
	return data;
}

/**
 * The task was no longer waiting: a teammate switched it on or closed it first. Says who and when, so the
 * panel can show "Sam already did this" instead of doing it twice.
 */
export async function alreadyFinished(client: Client, destinationId: string) {
	const { data, error } = await client
		.from('communication_sms_destination_events')
		.select('event_kind, occurred_at, actor_name')
		.eq('destination_id', destinationId)
		.in('event_kind', ['switched_on', 'closed'])
		.order('occurred_at', { ascending: false })
		.limit(1);
	if (error) throw error;
	const done = finishedBy(
		(data ?? []).map((row) => ({ kind: row.event_kind, at: row.occurred_at, who: row.actor_name }))
	);
	return json({ error: 'Someone already finished this task.', already_finished: done }, { status: 409 });
}
