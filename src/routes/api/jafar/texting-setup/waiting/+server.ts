import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { WaitingItem } from '$lib/jafar/texting-setup';

/** A turned-down item stays on the list this long, so Uplift sees it was answered. */
const TURNED_DOWN_DAYS = 7;

// Stage 10 Part 5b-2: Texting setup's Waiting on Twilio tab. What Uplift sent to Twilio for every business and is
// still waiting to hear back on (US texting registrations, number paperwork, toll-free checks), plus what was
// turned down in the last week. Read-only; Check now posts to `waiting/check`.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const since = new Date(Date.now() - TURNED_DOWN_DAYS * 86_400_000).toISOString();
	try {
		const client = getOwnerSupabaseClient();
		const [registrations, paperwork, tollfree] = await Promise.all([
			client
				.from('communication_sms_registrations')
				.select(
					'id, organization_id, status, submitted_at, updated_at, last_checked_at, organizations(name)'
				)
				.or(`status.eq.under_review,and(status.eq.action_needed,updated_at.gte.${since})`),
			client
				.from('communication_sms_number_paperwork')
				.select(
					'id, organization_id, status, country_code, number_type, submitted_at, decided_at, last_checked_at, organizations(name)'
				)
				.or(`status.eq.under_review,and(status.eq.needs_fix,decided_at.gte.${since})`),
			client
				.from('communication_sms_tollfree_verifications')
				.select(
					'id, organization_id, status, submitted_at, decided_at, last_checked_at, organizations(name), communication_sms_sender_identities(phone_number)'
				)
				.or(`status.eq.under_review,and(status.eq.needs_fix,decided_at.gte.${since})`)
		]);
		for (const result of [registrations, paperwork, tollfree]) if (result.error) throw result.error;

		const name = (row: { organizations: unknown }) =>
			(row.organizations as { name: string } | null)?.name ?? 'A business';
		const items: WaitingItem[] = [
			...(registrations.data ?? []).map((row) => ({
				kind: 'registration' as const,
				id: row.id,
				organization_id: row.organization_id,
				organization_name: name(row),
				turned_down: row.status === 'action_needed',
				sent_at: row.submitted_at,
				decided_at: row.status === 'action_needed' ? row.updated_at : null,
				detail: null
			})),
			...(paperwork.data ?? []).map((row) => ({
				kind: 'paperwork' as const,
				id: row.id,
				organization_id: row.organization_id,
				organization_name: name(row),
				turned_down: row.status === 'needs_fix',
				sent_at: row.submitted_at,
				decided_at: row.decided_at,
				detail: `${row.country_code}:${row.number_type}`
			})),
			...(tollfree.data ?? []).map((row) => ({
				kind: 'tollfree' as const,
				id: row.id,
				organization_id: row.organization_id,
				organization_name: name(row),
				turned_down: row.status === 'needs_fix',
				sent_at: row.submitted_at,
				decided_at: row.decided_at,
				detail:
					(row.communication_sms_sender_identities as { phone_number: string } | null)
						?.phone_number ?? null
			}))
		].sort((a, b) => (a.sent_at ?? '').localeCompare(b.sent_at ?? ''));

		const checked = [registrations, paperwork, tollfree]
			.flatMap((result) => (result.data ?? []) as { last_checked_at: string | null }[])
			.map((row) => row.last_checked_at)
			.filter((at): at is string => Boolean(at))
			.sort();

		return json(
			{ items, last_checked_at: checked.at(-1) ?? null },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not load what waits on Twilio.', error);
		return json({ error: 'The Waiting on Twilio list could not be loaded.' }, { status: 500 });
	}
};
