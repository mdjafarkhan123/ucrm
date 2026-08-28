import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	communicationSuppressionRemovalRequestSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function blockedAddresses(organizationId: string): Promise<Record<string, unknown>> {
	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_communication_email_blocked_addresses',
		{ p_organization_id: organizationId }
	);
	if (error) throw error;
	return (data ?? {}) as Record<string, unknown>;
}

function mapRpcError(code: string | undefined) {
	if (code === 'P0002') return 404;
	if (code === '23505' || code === '23514') return 409;
	return null;
}

// File a removal request for one blocked address. Restricted to organization administrators, per
// docs/contractor-email-contract.md § Preferences, consent, and suppressions. A hard-bounce request is
// approved and released inside the command; a complaint request is left pending for Jafar.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const suppressionId = event.params.suppressionId ?? '';
	if (!uuidPattern.test(suppressionId)) {
		return json(
			{ error: 'That blocked address was not found.' },
			{ status: 404, headers: noStore }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationSuppressionRemovalRequestSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the removal request.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `communication_suppression_removal:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const { data: request, error } = await client.rpc(
			'request_communication_email_suppression_removal',
			{
				p_organization_id: check.auth.organization.id,
				p_suppression_id: suppressionId,
				p_actor_user_id: check.auth.user.id,
				p_actor_email: check.auth.user.email ?? '',
				p_reason: parsed.data.reason,
				p_evidence: parsed.data.evidence,
				p_consent_confirmed: parsed.data.consent_confirmed
			}
		);
		if (error) {
			const status = mapRpcError(error.code ?? undefined);
			if (status) return json({ error: error.message }, { status, headers: noStore });
			throw error;
		}

		return json(
			{ request, ...(await blockedAddresses(check.auth.organization.id)) },
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not file a suppression removal request.', error);
		return json(
			{ error: 'The removal request could not be filed.' },
			{ status: 500, headers: noStore }
		);
	}
};

// Withdraw the organization's own still-pending request.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const suppressionId = event.params.suppressionId ?? '';
	if (!uuidPattern.test(suppressionId)) {
		return json(
			{ error: 'That blocked address was not found.' },
			{ status: 404, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const { data: request, error } = await client.rpc(
			'withdraw_communication_email_suppression_removal',
			{
				p_organization_id: check.auth.organization.id,
				p_suppression_id: suppressionId,
				p_actor_user_id: check.auth.user.id,
				p_actor_email: check.auth.user.email ?? ''
			}
		);
		if (error) {
			const status = mapRpcError(error.code ?? undefined);
			if (status) return json({ error: error.message }, { status, headers: noStore });
			throw error;
		}

		return json(
			{ request, ...(await blockedAddresses(check.auth.organization.id)) },
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not withdraw a suppression removal request.', error);
		return json(
			{ error: 'The removal request could not be withdrawn.' },
			{ status: 500, headers: noStore }
		);
	}
};
