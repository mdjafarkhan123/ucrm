import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	activateReplyIngestion,
	ReplyIngestionNotReadyError
} from '$lib/server/communications/operational-reply-ingestion';
import { sesDomainErrorResponse } from '$lib/server/communications/ses-domain-http';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	customerRepliesActivationSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'Cache-Control': 'no-store' };
const EVENT_TYPE = 'reply_ingestion.activated';

// Owner-only "Turn on customer replies" (and its Check). Deliberately separate from the everyday-email Set up /
// Check routes: this moves the organization's reply.<root> mail route to Amazon SES, so it only ever runs when
// the owner presses this specific button. The root domain is never taken from the request -- it is the
// organization's own verified SES sending domain's zone, so this cannot touch a domain the organization does
// not already send from. Re-running is safe: every step is idempotent and only advances the MX status.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) {
		const response = ownerUnauthorized();
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success) {
		return json(
			{ error: 'The organization identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = customerRepliesActivationSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please try turning on customer replies again.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `customer_replies_activation:${session.sessionId}`,
			windowSeconds: 300,
			maxAttempts: 10
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const [receiptResult, sendingResult] = await Promise.all([
			client
				.from('communication_email_authority_events')
				.select('after_state')
				.eq('organization_id', organizationId.data)
				.eq('event_type', EVENT_TYPE)
				.eq('idempotency_key', parsed.data.idempotency_key)
				.maybeSingle(),
			client
				.from('communication_email_domains')
				.select('dns_zone')
				.eq('organization_id', organizationId.data)
				.eq('purpose', 'sending')
				.eq('provider', 'ses')
				.eq('lifecycle_state', 'verified')
				.order('created_at', { ascending: false })
				.limit(1)
				.maybeSingle()
		]);
		if (receiptResult.error) throw receiptResult.error;
		if (receiptResult.data) {
			return json(
				{ ...(receiptResult.data.after_state as object), replayed: true },
				{ headers: noStore }
			);
		}
		if (sendingResult.error) throw sendingResult.error;
		if (!sendingResult.data?.dns_zone) {
			return json(
				{
					error: 'Everyday email must be set up and ready before customer replies can be turned on.'
				},
				{ status: 409, headers: noStore }
			);
		}

		const result = await activateReplyIngestion({
			client,
			organizationId: organizationId.data,
			rootDomain: sendingResult.data.dns_zone
		});

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: EVENT_TYPE,
			target_type: 'domain',
			target_id: result.domain_id,
			after_state: result,
			idempotency_key: parsed.data.idempotency_key
		});
		// A concurrent identical request already recorded the receipt; the outcome is the same either way.
		if (auditError && auditError.code !== '23505') throw auditError;

		return json(result, { headers: noStore });
	} catch (error) {
		if (error instanceof ReplyIngestionNotReadyError) {
			return json({ error: error.message, code: error.code }, { status: 409, headers: noStore });
		}
		return sesDomainErrorResponse(error, 'activate', 'customer reply domain');
	}
};
