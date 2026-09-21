import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The lines the inbox thread shows when a team member stops texting a customer or takes that stop back
// ("Sam stopped texts to +1 555 0100"). Only staff-made changes appear: a customer's own STOP already sits
// in the thread as their message. Read-only, newest 100 -- a customer has a handful of these, ever.
//
// Consent events are indexed by (organization, phone number), so this reads the customer's phone numbers
// first and asks for events on exactly those, rather than scanning the organization's consent history.
const STAFF_STOP_KINDS = ['staff_stop', 'staff_stop_undone'] as const;
const HISTORY_LIMIT = 100;

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'customers.view');
	if ('response' in check) return check.response;

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	const organizationId = check.auth.organization.id;
	const owner = getOwnerSupabaseClient();

	const phonesResult = await owner
		.from('client_contact_methods')
		.select('id, value')
		.eq('organization_id', organizationId)
		.eq('client_id', clientId)
		.eq('kind', 'phone');
	if (phonesResult.error) return databaseError();

	const phones = phonesResult.data ?? [];
	if (phones.length === 0) return json({ notes: [] }, { headers: PRIVATE_READ_HEADERS });

	const eventsResult = await owner
		.from('communication_sms_consent_events')
		.select('id, client_contact_method_id, occurred_at, created_by, evidence')
		.eq('organization_id', organizationId)
		.eq('source', 'staff')
		.in(
			'client_contact_method_id',
			phones.map((phone) => phone.id)
		)
		.in('evidence->>kind', [...STAFF_STOP_KINDS])
		.order('occurred_at', { ascending: false })
		.limit(HISTORY_LIMIT);
	if (eventsResult.error) return databaseError();

	const events = eventsResult.data ?? [];
	const actorIds = [...new Set(events.map((row) => row.created_by).filter(Boolean))] as string[];
	const profilesResult = actorIds.length
		? await owner.from('profiles').select('id, full_name').in('id', actorIds)
		: { data: [], error: null };
	if (profilesResult.error) return databaseError();

	const nameById = new Map((profilesResult.data ?? []).map((row) => [row.id, row.full_name]));
	const numberById = new Map(phones.map((phone) => [phone.id, phone.value]));

	return json(
		{
			notes: events.map((row) => {
				const evidence = (row.evidence ?? {}) as { kind?: string; note?: string };
				return {
					id: row.id,
					kind: evidence.kind === 'staff_stop_undone' ? 'turned_on' : 'stopped',
					phone: numberById.get(row.client_contact_method_id) ?? null,
					by_name: row.created_by ? (nameById.get(row.created_by) ?? null) : null,
					note: evidence.note?.trim() ? evidence.note.trim() : null,
					created_at: row.occurred_at
				};
			})
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
