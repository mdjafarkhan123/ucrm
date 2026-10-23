import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	hasPermission,
	requireOrganizationPermission,
	featureUnavailable
} from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { conversationReplySmsEstimateSchema } from '$lib/server/validation/communications.schema';

// The composer's live impact line (segments + estimated cost) for a draft SMS reply, before Send is
// pressed. Read-only and cheap (one sender lookup plus the same estimate/rate helpers the enqueue command
// itself freezes from), so it carries no rate limit of its own -- same as the conversation context read.
type SmsReplyRoute = {
	recipient_country: string | null;
	sender_id: string | null;
	sender_type: string | null;
	ok: boolean;
	code: string | null;
	message: string | null;
	mms_route: boolean;
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;
	const unavailable = featureUnavailable(check.access, 'communications.inbox');
	if (unavailable) return unavailable;
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
		return json(
			{
				ready: false,
				reason: 'Enter a message to see its estimated cost.',
				mms_eligible: false
			} as const,
			{ headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		// Stage 10 Part 5: the customer this reply texts, their country, the number it goes from, and whether that
		// route may text right now -- the same check the send itself runs.
		const { data: routes, error: routeError } = await ownerClient.rpc(
			'communication_sms_reply_route_preview',
			{ p_organization_id: organizationId, p_client_id: event.params.clientId }
		);
		if (routeError) {
			console.error('Could not read the SMS reply route.', routeError);
			return databaseError();
		}
		const route = (routes as SmsReplyRoute[] | null)?.[0];
		if (!route?.ok || !route.sender_id || !route.sender_type || !route.recipient_country) {
			return json(
				{
					ready: false,
					reason: route?.message ?? 'No ready SMS number is available to send from.',
					route_code: route?.code ?? 'no_sender',
					recipient_country: route?.recipient_country ?? null,
					mms_eligible: false
				} as const,
				{ headers: NO_STORE_HEADERS }
			);
		}

		const { data: sender, error: senderError } = await ownerClient
			.from('communication_sms_sender_identities')
			.select('phone_number')
			.eq('organization_id', organizationId)
			.eq('id', route.sender_id)
			.maybeSingle();
		if (senderError || !sender) {
			console.error('Could not read the SMS sender.', senderError);
			return databaseError();
		}

		// Real picture messages only travel between US and Canadian numbers; elsewhere a picture goes as a link.
		const mmsEligible = route.mms_route;

		if (!parsed.data.body) {
			return json(
				{
					ready: false,
					reason: 'Enter a message to see its estimated cost.',
					mms_eligible: mmsEligible
				} as const,
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
				p_destination: route.recipient_country,
				p_sender_type: route.sender_type,
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
				{
					ready: false,
					reason: 'No SMS price is published for this destination yet.',
					route_code: 'no_price',
					recipient_country: route.recipient_country,
					mms_eligible: mmsEligible
				} as const,
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
				sender_phone: sender.phone_number,
				recipient_country: route.recipient_country,
				mms_eligible: mmsEligible
			} as const,
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not estimate the SMS reply.', error);
		return databaseError();
	}
};
