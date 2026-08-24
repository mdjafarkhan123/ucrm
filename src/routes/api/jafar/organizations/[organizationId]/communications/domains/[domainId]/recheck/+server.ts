import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	authenticateBrevoDomain,
	BrevoManagementError,
	getBrevoDomain,
	type BrevoDnsRecord
} from '$lib/server/communications/brevo';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationDomainRecheckSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { z } from 'zod';

const noStore = { 'Cache-Control': 'no-store' };
const domainIdSchema = z.string().uuid();

type DnsStatus = 'unchecked' | 'pending' | 'passing' | 'failing';

function recordStatus(records: BrevoDnsRecord[], pattern: RegExp): DnsStatus {
	const matching = records.filter((record) => pattern.test(`${record.host_name} ${record.value}`));
	if (matching.length === 0) return 'unchecked';
	return matching.every((record) => record.status) ? 'passing' : 'failing';
}

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
			.select(
				'id, domain_name, purpose, lifecycle_state, spf_status, verified_at, provider_domain_id'
			)
			.eq('organization_id', organizationId.data)
			.eq('id', domainId.data)
			.neq('lifecycle_state', 'removed')
			.maybeSingle();
		if (domainError) throw domainError;
		if (!domain || domain.purpose !== 'sending') {
			return json({ error: 'Sending domain was not found.' }, { status: 404, headers: noStore });
		}
		if (domain.provider_domain_id == null) {
			return json(
				{ error: 'This sending domain has not been provisioned with Brevo.' },
				{ status: 409, headers: noStore }
			);
		}

		let authenticationRejected = false;
		try {
			await authenticateBrevoDomain(domain.domain_name);
		} catch (error) {
			if (!(error instanceof BrevoManagementError) || error.status !== 400) throw error;
			authenticationRejected = true;
		}
		const configuration = await getBrevoDomain(domain.domain_name);
		const dnsRecords = configuration.dns_records ?? [];
		const ownershipStatus = recordStatus(dnsRecords, /brevo-code|sendinblue-code/i);
		const dkimStatus = recordStatus(dnsRecords, /dkim/i);
		const dmarcStatus = recordStatus(dnsRecords, /_dmarc/i);
		const providerVerified = configuration.verified;
		const providerAuthenticated = configuration.authenticated && !authenticationRejected;
		const ready =
			providerVerified &&
			providerAuthenticated &&
			ownershipStatus === 'passing' &&
			dkimStatus === 'passing';
		const lifecycleState = ready
			? 'verified'
			: domain.verified_at || domain.lifecycle_state === 'unhealthy'
				? 'unhealthy'
				: 'pending_dns';
		const now = new Date().toISOString();
		const afterState = {
			domain_name: domain.domain_name,
			purpose: 'sending',
			lifecycle_state: lifecycleState,
			provider_verified: providerVerified,
			provider_authenticated: providerAuthenticated,
			ownership_status: ownershipStatus,
			dkim_status: dkimStatus,
			dmarc_status: dmarcStatus,
			// SPF is optional for Brevo shared-IP domain authentication. Keep its
			// recorded value for diagnostics, but never make a healthy Brevo domain
			// look pending because no separate SPF record was provisioned.
			spf_status: domain.spf_status,
			dns_records: dnsRecords,
			last_checked_at: now,
			verified_at: ready ? (domain.verified_at ?? now) : domain.verified_at
		};

		const { error: updateError } = await client
			.from('communication_email_domains')
			.update({ ...afterState, updated_at: now })
			.eq('organization_id', organizationId.data)
			.eq('id', domain.id);
		if (updateError) throw updateError;

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

		return json({ domain_id: domain.id, ...afterState }, { headers: noStore });
	} catch (error) {
		console.error('Could not recheck the sending domain.', error);
		const providerFailure = error instanceof BrevoManagementError;
		return json(
			{
				error: providerFailure
					? 'Brevo could not recheck the sending domain.'
					: 'The sending domain could not be rechecked.'
			},
			{ status: providerFailure ? 502 : 500, headers: noStore }
		);
	}
};
