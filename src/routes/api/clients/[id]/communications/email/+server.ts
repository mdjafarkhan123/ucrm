import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { renderManualEmailHtml } from '$lib/server/communications/manual-email';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	manualCommunicationEmailSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'customers.view')) {
		return json(
			{ error: 'You do not have access to this customer.', reason: 'permission_denied' },
			{ status: 403, headers: noStore }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = manualCommunicationEmailSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the email details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communication_manual_email:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const input = parsed.data;
		const { data, error } = await ownerClient.rpc('enqueue_manual_communication_email', {
			target_organization_id: organizationId,
			target_actor_user_id: check.auth.user.id,
			target_client_id: event.params.id,
			target_contact_method_id: input.contact_method_id,
			target_logical_send_key: input.idempotency_key,
			target_subject: input.subject,
			target_html_content: renderManualEmailHtml(input.body),
			target_text_content: input.body
		});
		if (error) {
			if (['42501', '23503', '55000'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 422, headers: noStore });
			}
			console.error('Could not queue manual communication email.', error);
			return json({ error: 'The email could not be queued.' }, { status: 500, headers: noStore });
		}

		return json(
			{
				intent: { id: data.id, status: data.status, created_at: data.created_at }
			},
			{ status: 201, headers: noStore }
		);
	} catch (error) {
		console.error('Could not queue manual communication email.', error);
		return json({ error: 'The email could not be queued.' }, { status: 500, headers: noStore });
	}
};
