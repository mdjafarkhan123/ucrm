import { json } from '@sveltejs/kit';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Owner/admin records one real marketing-email consent change for a client's email — a verbal or written
// preference the office was told about. It writes an append-only evidence event (who, when, how) that the
// state projection reads; marketing eligibility is decided only from that ledger, never from a toggle.
//
// Gated on customers.edit + owner/admin (via requireOrganizationAdmin) rather than a marketing.* permission
// on purpose: consent must be capturable now, before Marketing itself is published, exactly as the public
// form already records opt-ins today. The marketing.* permissions stay dark until the feature ships.
const consentSchema = z.object({
	contact_method_id: z.string().uuid('Choose an email to record consent for.'),
	decision: z.enum(['opt_in', 'opt_out']),
	note: z
		.string()
		.trim()
		.max(500, 'Keep the note under 500 characters.')
		.optional()
		.transform((value) => (value ? value : undefined))
});

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationAdmin(event, 'customers.edit');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = consentSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;
	const clientId = event.params.id;
	const { contact_method_id, decision, note } = parsed.data;

	// The email must belong to this client, in this organization. The request's RLS-scoped client already
	// sees only this organization's contact methods, so a mismatched or foreign id simply returns nothing.
	const { data: method, error: methodError } = await event.locals.supabase
		.from('client_contact_methods')
		.select('id, value')
		.eq('organization_id', organizationId)
		.eq('client_id', clientId)
		.eq('id', contact_method_id)
		.eq('kind', 'email')
		.maybeSingle();
	if (methodError) return databaseError();
	if (!method) return validationError({ contact_method_id: 'That email is not on this client.' });

	const owner = getOwnerSupabaseClient();
	const occurredAt = new Date().toISOString();

	const { error: insertError } = await owner.from('client_marketing_consent_events').insert({
		organization_id: organizationId,
		client_id: clientId,
		client_contact_method_id: contact_method_id,
		event_kind: decision,
		source: 'staff',
		// Unique per (organization, source); each staff recording is its own event.
		source_event_key: `staff:${randomUUID()}`,
		// Staff opt-ins carry no on-screen disclosure text; the context lives in the note instead.
		disclosure: null,
		evidence: {
			channel: 'staff',
			recorded_via: 'customer_page',
			...(note ? { note } : {})
		},
		occurred_at: occurredAt,
		created_by: access.auth.user.id
	});
	if (insertError) return databaseError();

	// Read the projected state back rather than assuming this event won: the projection is last-writer-wins,
	// so a rare newer event could still hold the current state.
	const { data: state, error: stateError } = await owner
		.from('client_marketing_consent_state')
		.select('state, effective_at')
		.eq('organization_id', organizationId)
		.eq('client_contact_method_id', contact_method_id)
		.maybeSingle();
	if (stateError) return databaseError();

	return json({
		marketing_consent: {
			email: method.value,
			contact_method_id,
			state: (state?.state as 'opted_in' | 'opted_out' | undefined) ?? 'unknown',
			source: 'staff',
			effective_at: state?.effective_at ?? occurredAt
		}
	});
};
