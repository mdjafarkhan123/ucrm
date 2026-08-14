import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import type { Json } from '$lib/database.types';

type HistoryEvent = {
	id: string;
	event_type: string;
	target_type: string;
	target_key: string | null;
	actor_email: string | null;
	occurred_at: string;
	before_state: Json | null;
	after_state: Json | null;
};

function jsonObject(value: Json | null): Record<string, Json> {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
	return value as Record<string, Json>;
}

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	const client = getOwnerSupabaseClient();

	try {
		const { data: organization, error: organizationError } = await client
			.from('organizations')
			.select('id, name')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		const [
			{ data: auditRows, error: auditError },
			{ data: freeAccessRows, error: freeAccessError },
			{ data: commercialRows, error: commercialError }
		] = await Promise.all([
			client
				.from('access_audit_events')
				.select(
					'id, event_type, target_type, target_key, actor_owner_email, before_state, after_state, created_at'
				)
				.eq('organization_id', parsedId.data)
				.order('created_at', { ascending: false })
				.limit(100),
			client
				.from('organization_free_access_events')
				.select(
					'id, action, package_version_id, access_until_date, reason, actor_owner_email, occurred_at'
				)
				.eq('organization_id', parsedId.data)
				.order('occurred_at', { ascending: false })
				.limit(100),
			client
				.from('organization_commercial_events')
				.select(
					'id, event_kind, summary, private_reason, private_reference, amount_usd_cents, original_confirmation_id, paid_through_effect, paid_through_before, paid_through_after, change_before, change_after, actor_owner_email, occurred_at'
				)
				.eq('organization_id', parsedId.data)
				.order('occurred_at', { ascending: false })
				.limit(100)
		]);
		if (auditError) throw auditError;
		if (freeAccessError) throw freeAccessError;
		if (commercialError) throw commercialError;

		const auditEvents: HistoryEvent[] = (auditRows ?? []).map((row) => ({
			id: `audit:${row.id}`,
			event_type: row.event_type,
			target_type: row.target_type,
			target_key: row.target_key,
			actor_email: row.actor_owner_email,
			occurred_at: row.created_at,
			before_state: row.before_state,
			after_state: row.after_state
		}));

		const freeAccessEvents: HistoryEvent[] = (freeAccessRows ?? []).map((row) => ({
			id: `free_access:${row.id}`,
			event_type: `free_access.${row.action}`,
			target_type: 'organization.free_access',
			target_key: row.package_version_id,
			actor_email: row.actor_owner_email,
			occurred_at: row.occurred_at,
			before_state: null,
			after_state: {
				action: row.action,
				access_until_date: row.access_until_date,
				reason: row.reason
			}
		}));

		const freeAccessCommercialKinds = new Set([
			'free_access_granted',
			'free_access_extended',
			'free_access_converted_forever',
			'free_access_ended'
		]);
		const commercialEvents: HistoryEvent[] = (commercialRows ?? [])
			.filter((row) => !freeAccessCommercialKinds.has(row.event_kind))
			.map((row) => {
				const changeAfter = jsonObject(row.change_after);
				return {
					id: `commercial:${row.id}`,
					event_type: `commercial.${row.event_kind}`,
					target_type: 'organization.commercial_access',
					target_key: row.original_confirmation_id,
					actor_email: row.actor_owner_email,
					occurred_at: row.occurred_at,
					before_state: row.change_before ?? { paid_through_date: row.paid_through_before },
					after_state: {
						...changeAfter,
						summary: row.summary,
						private_reason: row.private_reason,
						private_reference: row.private_reference,
						amount_usd_cents: row.amount_usd_cents,
						paid_through_effect: row.paid_through_effect,
						paid_through_date: row.paid_through_after
					}
				};
			});

		const events = [...auditEvents, ...freeAccessEvents, ...commercialEvents].sort((a, b) =>
			a.occurred_at < b.occurred_at ? 1 : a.occurred_at > b.occurred_at ? -1 : 0
		);

		return json({ organization, events });
	} catch (error) {
		console.error('Could not load organization history.', error);
		return json({ error: 'History could not be loaded.' }, { status: 500 });
	}
};
