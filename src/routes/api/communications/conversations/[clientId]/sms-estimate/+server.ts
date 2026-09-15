import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { conversationReplySmsEstimateSchema } from '$lib/server/validation/communications.schema';

// The composer's live impact line (segments + estimated cost) for a draft SMS reply, before Send is
// pressed. Read-only and cheap (one sender lookup plus the same estimate/rate helpers the enqueue command
// itself freezes from), so it carries no rate limit of its own -- same as the conversation context read.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'customers.view')) {
		return json(
			{ error: 'You do not have access to this customer.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	if (!event.params.clientId) return validationError({ form: 'Choose a valid conversation.' });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = conversationReplySmsEstimateSchema.safeParse(body);
	if (!parsed.success) {
		return json({ ready: false, reason: 'Enter a message to see its estimated cost.' } as const, {
			headers: NO_STORE_HEADERS
		});
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const { data: sender, error: senderError } = await ownerClient
			.from('communication_sms_sender_identities')
			.select('phone_number, country_code, sender_type')
			.eq('organization_id', organizationId)
			.eq('is_default_sender', true)
			.eq('lifecycle_state', 'ready')
			.eq('capable_sms', true)
			.maybeSingle();
		if (senderError) {
			console.error('Could not read the default SMS sender.', senderError);
			return databaseError();
		}
		if (!sender?.country_code || !sender.sender_type) {
			return json(
				{ ready: false, reason: 'No ready SMS number is available to send from.' } as const,
				{ headers: NO_STORE_HEADERS }
			);
		}

		const { data: segments, error: segmentError } = await ownerClient.rpc(
			'communication_sms_estimate_segments',
			{ p_body: parsed.data.body }
		);
		const segment = (segments as { encoding: string; segment_count: number }[] | null)?.[0];
		if (segmentError || !segment) {
			console.error('Could not estimate SMS segments.', segmentError);
			return databaseError();
		}

		const { data: rate, error: rateError } = await ownerClient.rpc(
			'communication_sms_effective_retail_rate',
			{
				p_destination: sender.country_code,
				p_sender_type: sender.sender_type,
				p_message_unit: 'segment'
			}
		);
		if (rateError) {
			console.error('Could not read the SMS retail rate.', rateError);
			return databaseError();
		}
		const retailRate = rate as { retail_rate_major: number; currency_code: string } | null;
		if (!retailRate) {
			return json(
				{ ready: false, reason: 'No SMS price is published for this destination yet.' } as const,
				{ headers: NO_STORE_HEADERS }
			);
		}

		return json(
			{
				ready: true,
				encoding: segment.encoding,
				segment_count: segment.segment_count,
				cost_minor: Math.ceil(segment.segment_count * Number(retailRate.retail_rate_major) * 100),
				currency: retailRate.currency_code,
				sender_phone: sender.phone_number
			} as const,
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not estimate the SMS reply.', error);
		return databaseError();
	}
};
