import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { changeClickDomain } from '$lib/server/communications/branded-click-domain';
import { marketingDomainErrorResponse } from '$lib/server/communications/marketing-domain-http';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	marketingClickDomainChangeSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'Cache-Control': 'no-store' };
const domainIdSchema = z.string().uuid();

// Owner-only branded click-link controls for a Marketing sending domain (M6d): turn on, turn off (keep the
// CloudFront tenant so turning on again is instant), or remove (delete the tenant and its DNS record). Same
// receipt-based idempotency and audit trail as the recheck route.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) {
		const response = ownerUnauthorized();
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const domainId = domainIdSchema.safeParse(event.params.domainId);
	if (!organizationId.success || !domainId.success) {
		return json({ error: 'The domain identifier is invalid.' }, { status: 422, headers: noStore });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = marketingClickDomainChangeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please start the branded link change again.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const eventType = `marketing_domain.click_domain.${parsed.data.action}`;
	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `marketing_click_domain:${session.sessionId}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const readReceipt = () =>
			client
				.from('communication_email_authority_events')
				.select('after_state')
				.eq('organization_id', organizationId.data)
				.eq('target_id', domainId.data)
				.eq('event_type', eventType)
				.eq('idempotency_key', parsed.data.idempotency_key)
				.maybeSingle();

		const { data: receipt, error: receiptError } = await readReceipt();
		if (receiptError) throw receiptError;
		if (receipt) {
			return json({ ...(receipt.after_state as object), replayed: true }, { headers: noStore });
		}

		const click = await changeClickDomain({
			client,
			organizationId: organizationId.data,
			domainId: domainId.data,
			action: parsed.data.action
		});
		const result = { click };

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: eventType,
			target_type: 'domain',
			target_id: domainId.data,
			after_state: result,
			idempotency_key: parsed.data.idempotency_key
		});
		if (auditError) {
			// A concurrent identical change already recorded the receipt; return its outcome.
			if (auditError.code !== '23505') throw auditError;
			const replay = await readReceipt();
			if (replay.error || !replay.data) throw replay.error ?? auditError;
			return json({ ...(replay.data.after_state as object), replayed: true }, { headers: noStore });
		}

		return json(result, { headers: noStore });
	} catch (error) {
		return marketingDomainErrorResponse(error, 'change branded links for');
	}
};
