import { json } from '@sveltejs/kit';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// "Stop texting this customer" for the inbox's Contact tab.
//
// GET reads, per phone number, whether texts may be sent and -- when they are stopped -- who stopped them,
// when, why, and whether staff may take that stop back. It also reports the primary email's marketing
// standing, read-only, so the tab tells the whole messaging story in one place.
//
// POST records a stop or takes a staff stop back. Both are commands in the database that keep the
// customer's own STOP locked against staff and refuse to invent consent; this route only decides who may
// press the button (anyone who can already reply to the customer) and translates the plain-English refusals.
const stopSchema = z.object({
	contact_method_id: z.string().uuid('Choose a phone number.'),
	action: z.enum(['stop', 'undo']),
	note: z
		.string()
		.trim()
		.max(500, 'Keep the note under 500 characters.')
		.optional()
		.transform((value) => (value ? value : undefined))
});

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'customers.view');
	if ('response' in check) return check.response;

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	const organizationId = check.auth.organization.id;
	const owner = getOwnerSupabaseClient();

	const [stateResult, emailResult] = await Promise.all([
		owner.rpc('communication_sms_client_stop_state', {
			p_organization_id: organizationId,
			p_client_id: clientId
		}),
		owner
			.from('client_contact_methods')
			.select('id, value')
			.eq('organization_id', organizationId)
			.eq('client_id', clientId)
			.eq('kind', 'email')
			.eq('is_primary', true)
			.maybeSingle()
	]);
	if (stateResult.error || emailResult.error) return databaseError();

	const rows = stateResult.data ?? [];

	const stopperIds = [
		...new Set(rows.map((row) => row.stopped_by_user).filter(Boolean))
	] as string[];
	const [profilesResult, marketingResult] = await Promise.all([
		stopperIds.length
			? owner.from('profiles').select('id, full_name').in('id', stopperIds)
			: Promise.resolve({ data: [], error: null }),
		emailResult.data
			? owner
					.from('client_marketing_consent_state')
					.select('state, effective_at')
					.eq('organization_id', organizationId)
					.eq('client_contact_method_id', emailResult.data.id)
					.maybeSingle()
			: Promise.resolve({ data: null, error: null })
	]);
	if (profilesResult.error || marketingResult.error) return databaseError();

	const nameById = new Map((profilesResult.data ?? []).map((row) => [row.id, row.full_name]));

	return json(
		{
			can_manage: hasPermission(check.access, 'conversations.send'),
			phones: rows.map((row) => ({
				contact_method_id: row.contact_method_id,
				value: row.value,
				is_primary: row.is_primary,
				state: row.state as 'opted_in' | 'opted_out' | 'unknown',
				stopped_by: row.stopped_by as 'customer' | 'staff' | null,
				stopped_at: row.stopped_at,
				stopped_by_name: row.stopped_by_user ? (nameById.get(row.stopped_by_user) ?? null) : null,
				note: row.note,
				can_undo: row.can_undo
			})),
			marketing_email: emailResult.data
				? {
						email: emailResult.data.value,
						state: (marketingResult.data?.state ?? 'unknown') as
							'opted_in' | 'opted_out' | 'unknown',
						effective_at: marketingResult.data?.effective_at ?? null
					}
				: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'customers.view')) {
		return json(
			{ error: 'You do not have access to this customer.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = stopSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;
	const owner = getOwnerSupabaseClient();

	try {
		const limit = await checkRateLimit(owner, {
			bucketKey: `communication_sms_stop:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 30
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const { contact_method_id, action, note } = parsed.data;
		const { error } =
			action === 'stop'
				? await owner.rpc('communication_sms_staff_stop', {
						p_organization_id: organizationId,
						p_actor: check.auth.user.id,
						p_client_id: clientId,
						p_client_contact_method_id: contact_method_id,
						p_note: note ?? '',
						p_source_event_key: `staff-stop:${randomUUID()}`
					})
				: await owner.rpc('communication_sms_staff_stop_undo', {
						p_organization_id: organizationId,
						p_actor: check.auth.user.id,
						p_client_id: clientId,
						p_client_contact_method_id: contact_method_id,
						p_source_event_key: `staff-stop-undo:${randomUUID()}`
					});

		if (error) {
			const dbError = error as { code?: string; message?: string };
			// P0001 is the database's own plain-English refusal (already stopped, customer's STOP, nothing to
			// restore, wrong number). Show it as written.
			if (dbError.code === 'P0001') {
				return json({ error: dbError.message }, { status: 422, headers: NO_STORE_HEADERS });
			}
			console.error('Could not change the text stop for a customer.', error);
			return databaseError();
		}

		return json({ ok: true }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not change the text stop for a customer.', error);
		return databaseError();
	}
};
