import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { recheckOperationalDomain } from '$lib/server/communications/operational-domain-activation';
import { sesDomainErrorResponse } from '$lib/server/communications/ses-domain-http';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationDomainRecheckSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { z } from 'zod';

const noStore = { 'Cache-Control': 'no-store' };
const domainIdSchema = z.string().uuid();

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
			bucketKey: `email_domain_recheck:${session.sessionId}`,
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
			.select('target_id, after_state')
			.eq('organization_id', organizationId.data)
			.eq('target_id', domainId.data)
			.eq('event_type', 'domain.rechecked')
			.eq('idempotency_key', parsed.data.idempotency_key)
			.maybeSingle();
		if (receiptError) throw receiptError;
		if (receipt) {
			return json(
				{ domain_id: receipt.target_id, ...(receipt.after_state as object), replayed: true },
				{ headers: noStore }
			);
		}

		const { data: domain, error: domainError } = await client
			.from('communication_email_domains')
			.select('id, purpose, provider')
			.eq('organization_id', organizationId.data)
			.eq('id', domainId.data)
			.neq('lifecycle_state', 'removed')
			.maybeSingle();
		if (domainError) throw domainError;
		if (!domain || domain.purpose !== 'sending' || domain.provider !== 'ses') {
			return json({ error: 'Sending domain was not found.' }, { status: 404, headers: noStore });
		}
		// Re-runs the whole idempotent Set up, which also writes the rows and routes customer replies once the
		// reply identity has verified.
		let afterState;
		try {
			const { sending, receiving } = await recheckOperationalDomain({
				client,
				organizationId: organizationId.data,
				domainId: domain.id
			});
			afterState = { ...sending, receiving };
		} catch (error) {
			return sesDomainErrorResponse(error, 'recheck', 'everyday email domain');
		}

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: 'domain.rechecked',
			target_type: 'domain',
			target_id: domain.id,
			after_state: afterState,
			idempotency_key: parsed.data.idempotency_key
		});
		if (auditError) {
			if (auditError.code !== '23505') throw auditError;
			const replay = await client
				.from('communication_email_authority_events')
				.select('target_id, after_state')
				.eq('organization_id', organizationId.data)
				.eq('target_id', domain.id)
				.eq('event_type', 'domain.rechecked')
				.eq('idempotency_key', parsed.data.idempotency_key)
				.single();
			if (replay.error) throw replay.error;
			return json(
				{
					domain_id: replay.data.target_id,
					...(replay.data.after_state as object),
					replayed: true
				},
				{ headers: noStore }
			);
		}

		return json(afterState, { headers: noStore });
	} catch (error) {
		console.error('Could not recheck the sending domain.', error);
		return json(
			{ error: 'The sending domain could not be rechecked.' },
			{ status: 500, headers: noStore }
		);
	}
};
