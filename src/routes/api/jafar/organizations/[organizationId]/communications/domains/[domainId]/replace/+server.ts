import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	BrevoManagementError,
	createBrevoDomain,
	getBrevoDomain,
	listBrevoDomains
} from '$lib/server/communications/brevo';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationDomainReplacementSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { z } from 'zod';

const noStore = { 'Cache-Control': 'no-store' };
const domainIdSchema = z.string().uuid();

const domainColumns =
	'id, organization_id, domain_name, dns_zone, purpose, provider_domain_id, lifecycle_state, replacement_of_domain_id';

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
	const parsed = communicationDomainReplacementSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the replacement sending domain.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	const input = parsed.data;
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `email_domain_replace:${session.sessionId}`,
			windowSeconds: 300,
			maxAttempts: 10
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
			.eq('event_type', 'domain.replacement_provisioned')
			.eq('idempotency_key', input.idempotency_key)
			.maybeSingle();
		if (receiptError) throw receiptError;
		if (receipt) {
			return json(
				{ domain_id: receipt.target_id, ...(receipt.after_state as object), replayed: true },
				{ headers: noStore }
			);
		}

		const { data: currentDomain, error: currentDomainError } = await client
			.from('communication_email_domains')
			.select('id, domain_name, purpose, lifecycle_state')
			.eq('organization_id', organizationId.data)
			.eq('id', domainId.data)
			.maybeSingle();
		if (currentDomainError) throw currentDomainError;
		if (!currentDomain || currentDomain.purpose !== 'sending') {
			return json({ error: 'Sending domain was not found.' }, { status: 404, headers: noStore });
		}
		if (currentDomain.lifecycle_state !== 'verified') {
			return json(
				{ error: 'Only a verified sending domain can be replaced.' },
				{ status: 409, headers: noStore }
			);
		}
		if (currentDomain.domain_name === input.domain_name) {
			return json(
				{ error: 'Choose a different replacement domain.' },
				{ status: 409, headers: noStore }
			);
		}

		let { data: replacement, error: replacementError } = await client
			.from('communication_email_domains')
			.select(domainColumns)
			.eq('domain_name', input.domain_name)
			.neq('lifecycle_state', 'removed')
			.maybeSingle();
		if (replacementError) throw replacementError;
		if (
			replacement &&
			(replacement.organization_id !== organizationId.data ||
				replacement.purpose !== 'sending' ||
				replacement.replacement_of_domain_id !== currentDomain.id)
		) {
			return json({ error: 'This domain is already claimed.' }, { status: 409, headers: noStore });
		}

		// This row is the durable replacement claim. It must exist before any provider request.
		if (!replacement) {
			const inserted = await client
				.from('communication_email_domains')
				.insert({
					organization_id: organizationId.data,
					purpose: 'sending',
					domain_name: input.domain_name,
					dns_zone: input.dns_zone,
					replacement_of_domain_id: currentDomain.id
				})
				.select(domainColumns)
				.single();
			if (inserted.error) {
				if (inserted.error.code !== '23505') throw inserted.error;
				const raced = await client
					.from('communication_email_domains')
					.select(domainColumns)
					.eq('domain_name', input.domain_name)
					.neq('lifecycle_state', 'removed')
					.maybeSingle();
				if (raced.error) throw raced.error;
				if (
					!raced.data ||
					raced.data.organization_id !== organizationId.data ||
					raced.data.purpose !== 'sending' ||
					raced.data.replacement_of_domain_id !== currentDomain.id
				) {
					return json(
						{ error: 'This domain is already claimed.' },
						{ status: 409, headers: noStore }
					);
				}
				replacement = raced.data;
			} else {
				replacement = inserted.data;
			}
		}

		let providerId = replacement.provider_domain_id;
		let configuration;
		try {
			configuration = await getBrevoDomain(input.domain_name);
			if (providerId == null) {
				providerId =
					(await listBrevoDomains()).find(
						(candidate) => candidate.domain_name.toLowerCase() === input.domain_name
					)?.id ?? null;
				if (providerId == null) {
					throw new BrevoManagementError(
						'Brevo returned the domain configuration without a matching domain identity.',
						null,
						'brevo_missing_domain_id'
					);
				}
			}
		} catch (error) {
			if (!(error instanceof BrevoManagementError) || error.status !== 404) throw error;
			const created = await createBrevoDomain(input.domain_name);
			providerId = created.id;
			configuration = await getBrevoDomain(input.domain_name);
		}

		const dnsRecords = configuration.dns_records ?? [];
		const ownership = dnsRecords.find((record) =>
			/brevo-code|sendinblue-code/i.test(`${record.host_name} ${record.value}`)
		);
		const dkimRecords = dnsRecords.filter((record) => /dkim/i.test(record.host_name));
		const dmarc = dnsRecords.find((record) => /_dmarc/i.test(record.host_name));
		const now = new Date().toISOString();
		const afterState = {
			domain_name: input.domain_name,
			dns_zone: input.dns_zone,
			purpose: 'sending',
			lifecycle_state: 'pending_dns',
			replacement_of_domain_id: currentDomain.id,
			current_domain_id: currentDomain.id,
			current_domain_state: currentDomain.lifecycle_state,
			provider_verified: configuration.verified,
			provider_authenticated: configuration.authenticated,
			dns_records: dnsRecords,
			queued_manual_email_policy: 'hold_for_review'
		};
		const { error: updateError } = await client
			.from('communication_email_domains')
			.update({
				dns_zone: input.dns_zone,
				provider_domain_id: providerId,
				provider_verified: configuration.verified,
				provider_authenticated: configuration.authenticated,
				ownership_status: ownership?.status ? 'passing' : 'pending',
				dkim_status:
					dkimRecords.length > 0 && dkimRecords.every((record) => record.status)
						? 'passing'
						: 'pending',
				dmarc_status: dmarc?.status ? 'passing' : 'pending',
				dns_records: dnsRecords,
				last_checked_at: now,
				updated_at: now
			})
			.eq('organization_id', organizationId.data)
			.eq('id', replacement.id);
		if (updateError) throw updateError;

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: 'domain.replacement_provisioned',
			target_type: 'domain',
			target_id: replacement.id,
			before_state: {
				current_domain_id: currentDomain.id,
				current_domain_name: currentDomain.domain_name,
				current_domain_state: currentDomain.lifecycle_state
			},
			after_state: afterState,
			idempotency_key: input.idempotency_key
		});
		if (auditError) {
			if (auditError.code !== '23505') throw auditError;
			const replay = await client
				.from('communication_email_authority_events')
				.select('target_id, after_state')
				.eq('organization_id', organizationId.data)
				.eq('event_type', 'domain.replacement_provisioned')
				.eq('idempotency_key', input.idempotency_key)
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

		return json({ domain_id: replacement.id, ...afterState }, { status: 201, headers: noStore });
	} catch (error) {
		console.error('Could not provision the replacement sending domain.', error);
		const providerFailure = error instanceof BrevoManagementError;
		return json(
			{
				error: providerFailure
					? 'Brevo could not provision the replacement sending domain.'
					: 'The replacement sending domain could not be provisioned.'
			},
			{ status: providerFailure ? 502 : 500, headers: noStore }
		);
	}
};
