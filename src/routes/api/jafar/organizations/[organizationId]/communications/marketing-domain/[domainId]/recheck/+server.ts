import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { recheckMarketingDomain } from '$lib/server/communications/marketing-domain-activation';
import { marketingDomainErrorResponse } from '$lib/server/communications/marketing-domain-http';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationDomainRecheckSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'Cache-Control': 'no-store' };
const domainIdSchema = z.string().uuid();

// Owner-only recheck of a Marketing sending identity. Every provider step is idempotent, so a recheck is
// simply another pass of the same reconciliation: it re-reads SES, repairs any DNS record that drifted, and
// re-derives the health values. That is what lets an activation started before DNS propagated finish later.
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
	const parsed = communicationDomainRecheckSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please start a new domain check.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `marketing_domain_recheck:${session.sessionId}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const { data: receipt, error: receiptError } = await client
			.from('communication_email_authority_events')
			.select('after_state')
			.eq('organization_id', organizationId.data)
			.eq('target_id', domainId.data)
			.eq('event_type', 'marketing_domain.rechecked')
			.eq('idempotency_key', parsed.data.idempotency_key)
			.maybeSingle();
		if (receiptError) throw receiptError;
		if (receipt) {
			return json({ ...(receipt.after_state as object), replayed: true }, { headers: noStore });
		}

		const result = await recheckMarketingDomain({
			client,
			organizationId: organizationId.data,
			domainId: domainId.data
		});

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: 'marketing_domain.rechecked',
			target_type: 'domain',
			target_id: result.marketing.domain_id,
			after_state: result,
			idempotency_key: parsed.data.idempotency_key
		});
		if (auditError) {
			// A concurrent identical recheck already recorded the receipt; return its outcome.
			if (auditError.code !== '23505') throw auditError;
			const replay = await client
				.from('communication_email_authority_events')
				.select('after_state')
				.eq('organization_id', organizationId.data)
				.eq('target_id', result.marketing.domain_id)
				.eq('event_type', 'marketing_domain.rechecked')
				.eq('idempotency_key', parsed.data.idempotency_key)
				.single();
			if (replay.error) throw replay.error;
			return json({ ...(replay.data.after_state as object), replayed: true }, { headers: noStore });
		}

		return json(result, { headers: noStore });
	} catch (error) {
		return marketingDomainErrorResponse(error, 'recheck');
	}
};
