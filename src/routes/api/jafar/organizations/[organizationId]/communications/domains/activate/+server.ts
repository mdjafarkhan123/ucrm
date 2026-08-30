import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { BrevoManagementError } from '$lib/server/communications/brevo';
import { CloudflareDnsError } from '$lib/server/communications/cloudflare-dns';
import {
	activateEmailDomain,
	EmailDomainActivationError
} from '$lib/server/communications/email-domain-activation';
import { getBrevoInboundWebhookUrl } from '$lib/server/email/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationDomainActivationSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Owner-only managed email-domain activation (A1-D). Derives mail.<root> + reply.<root>, writes only
// UCRM-owned records through Cloudflare, verifies Brevo, and registers the inbound webhook. The reconciler
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
			bucketKey: `email_domain_activation:${session.sessionId}`,
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
				.eq('event_type', 'domain.activated')
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

		// Built before any provider call so a misconfigured origin fails closed rather than mid-saga.
		const webhookUrl = getBrevoInboundWebhookUrl();

		const result = await activateEmailDomain({
			client,
			organizationId: organizationId.data,
			rootDomain: parsed.data.root_domain,
			webhookUrl
		});

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: 'domain.activated',
			target_type: 'domain',
			target_id: result.sending.domain_id,
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
				.eq('event_type', 'domain.activated')
				.eq('idempotency_key', parsed.data.idempotency_key)
				.single();
			if (replay.error) throw replay.error;
			return json({ ...(replay.data.after_state as object), replayed: true }, { headers: noStore });
		}

		return json(result, { status: 201, headers: noStore });
	} catch (error) {
		// An occupied/conflicting name or another non-retryable decision the owner must resolve by hand.
		if (error instanceof EmailDomainActivationError && !error.retryable) {
			return json({ error: error.message, code: error.code }, { status: 409, headers: noStore });
		}
		// An ambiguous provider outcome (timeout/network). The reconciler wrote nothing it cannot re-derive;
		// the owner can safely run activation again.
		const providerUnknown =
			error instanceof EmailDomainActivationError ||
			(error instanceof CloudflareDnsError && (error.status === null || error.status >= 500)) ||
			(error instanceof BrevoManagementError && (error.status === null || error.status >= 500));
		if (providerUnknown) {
			return json(
				{ error: 'A provider did not confirm the change. Check the domain and try again.' },
				{ status: 502, headers: noStore }
			);
		}
		if (error instanceof CloudflareDnsError) {
			return json(
				{ error: 'Cloudflare rejected a DNS change during activation.' },
				{ status: 502, headers: noStore }
			);
		}
		if (error instanceof BrevoManagementError) {
			return json(
				{ error: 'Brevo could not complete domain activation.' },
				{ status: 502, headers: noStore }
			);
		}
		console.error('Could not activate the email domain.', error);
		return json(
			{ error: 'The email domain could not be activated.' },
			{ status: 500, headers: noStore }
		);
	}
};
