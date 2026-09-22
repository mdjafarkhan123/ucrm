import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { activateMarketingDomain } from '$lib/server/communications/marketing-domain-activation';
import { marketingDomainErrorResponse } from '$lib/server/communications/marketing-domain-http';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationDomainActivationSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Owner-only Marketing sending-identity activation (M4 stage 1). Derives news.<root> with MAIL FROM
// bounce.news.<root>, provisions the organization's SES tenant, configuration set, event destination and
// domain identity, then writes only UCRM-owned records inside news.<root> through Cloudflare. The reconciler
// is a desired-state saga, so a replay of the same idempotency key returns the recorded outcome and a fresh
// key safely re-runs the reconciliation from current provider state.
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
	const parsed = communicationDomainActivationSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the root domain.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `marketing_domain_activation:${session.sessionId}`,
			windowSeconds: 300,
			maxAttempts: 10
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const [receiptResult, organizationResult] = await Promise.all([
			client
				.from('communication_email_authority_events')
				.select('target_id, after_state')
				.eq('organization_id', organizationId.data)
				.eq('event_type', 'marketing_domain.activated')
				.eq('idempotency_key', parsed.data.idempotency_key)
				.maybeSingle(),
			client.from('organizations').select('id').eq('id', organizationId.data).maybeSingle()
		]);
		if (receiptResult.error) throw receiptResult.error;
		if (receiptResult.data) {
			return json(
				{ ...(receiptResult.data.after_state as object), replayed: true },
				{ headers: noStore }
			);
		}
		if (organizationResult.error) throw organizationResult.error;
		if (!organizationResult.data) {
			return json({ error: 'Organization was not found.' }, { status: 404, headers: noStore });
		}

		const result = await activateMarketingDomain({
			client,
			organizationId: organizationId.data,
			rootDomain: parsed.data.root_domain
		});

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: 'marketing_domain.activated',
			target_type: 'domain',
			target_id: result.marketing.domain_id,
			after_state: result,
			idempotency_key: parsed.data.idempotency_key
		});
		if (auditError) {
			// A concurrent identical activation already recorded the receipt; return its outcome.
			if (auditError.code !== '23505') throw auditError;
			const replay = await client
				.from('communication_email_authority_events')
				.select('after_state')
				.eq('organization_id', organizationId.data)
				.eq('event_type', 'marketing_domain.activated')
				.eq('idempotency_key', parsed.data.idempotency_key)
				.single();
			if (replay.error) throw replay.error;
			return json({ ...(replay.data.after_state as object), replayed: true }, { headers: noStore });
		}

		return json(result, { status: 201, headers: noStore });
	} catch (error) {
		return marketingDomainErrorResponse(error, 'activate');
	}
};
