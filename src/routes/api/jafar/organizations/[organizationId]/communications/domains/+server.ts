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
	communicationDomainProvisionSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'Cache-Control': 'no-store' };

export const GET: RequestHandler = async (event) => {
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

	const client = getOwnerSupabaseClient();
	const { data, error } = await client
		.from('communication_email_domains')
		.select(
			'id, domain_name, dns_zone, lifecycle_state, ownership_status, dkim_status, dmarc_status, spf_status, provider_verified, provider_authenticated, last_checked_at, verified_at, warmup_started_at, transition_until, replacement_of_domain_id, provider_cleanup_error, created_at'
		)
		.eq('organization_id', organizationId.data)
		.eq('purpose', 'sending')
		.neq('lifecycle_state', 'removed')
		.order('created_at');

	if (error) {
		console.error('Could not load sending domains for the owner.', error);
		return json({ error: 'Email domains could not be loaded.' }, { status: 500, headers: noStore });
	}

	return json({ domains: data ?? [] }, { headers: noStore });
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) {
		const response = ownerUnauthorized();
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success)
		return json(
			{ error: 'The organization identifier is invalid.' },
			{ status: 422, headers: noStore }
		);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationDomainProvisionSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the sending domain.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	const input = parsed.data;
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `email_domain_provision:${session.sessionId}`,
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
				.eq('idempotency_key', input.idempotency_key)
				.maybeSingle(),
			client.from('organizations').select('id').eq('id', organizationId.data).maybeSingle()
		]);
		const { data: receipt, error: receiptError } = receiptResult;
		if (receiptError) throw receiptError;
		if (receipt) {
			return json(
				{ domain_id: receipt.target_id, ...(receipt.after_state as object), replayed: true },
				{ headers: noStore }
			);
		}

		const { data: organization, error: organizationError } = organizationResult;
		if (organizationError) throw organizationError;
		if (!organization)
			return json({ error: 'Organization was not found.' }, { status: 404, headers: noStore });

		let { data: domain, error: domainError } = await client
			.from('communication_email_domains')
			.select('id, organization_id, domain_name, purpose, provider_domain_id, lifecycle_state')
			.eq('domain_name', input.domain_name)
			.neq('lifecycle_state', 'removed')
			.maybeSingle();
		if (domainError) throw domainError;
		if (
			domain &&
			(domain.organization_id !== organizationId.data || domain.purpose !== 'sending')
		) {
			return json({ error: 'This domain is already claimed.' }, { status: 409, headers: noStore });
		}

		if (!domain) {
			const inserted = await client
				.from('communication_email_domains')
				.insert({
					organization_id: organizationId.data,
					purpose: 'sending',
					domain_name: input.domain_name,
					dns_zone: input.dns_zone
				})
				.select('id, organization_id, domain_name, purpose, provider_domain_id, lifecycle_state')
				.single();
			if (inserted.error) {
				if (inserted.error.code === '23505') {
					const raced = await client
						.from('communication_email_domains')
						.select(
							'id, organization_id, domain_name, purpose, provider_domain_id, lifecycle_state'
						)
						.eq('domain_name', input.domain_name)
						.neq('lifecycle_state', 'removed')
						.maybeSingle();
					if (raced.error) throw raced.error;
					if (
						!raced.data ||
						raced.data.organization_id !== organizationId.data ||
						raced.data.purpose !== 'sending'
					) {
						return json(
							{ error: 'This domain is already claimed.' },
							{ status: 409, headers: noStore }
						);
					}
					domain = raced.data;
				} else {
					throw inserted.error;
				}
			} else {
				domain = inserted.data;
			}
		}

		let providerId = domain.provider_domain_id;
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
			provider_verified: configuration.verified,
			provider_authenticated: configuration.authenticated,
			dns_records: dnsRecords
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
			.eq('id', domain.id);
		if (updateError) throw updateError;

		const { error: auditError } = await client.from('communication_email_authority_events').insert({
			organization_id: organizationId.data,
			actor_kind: 'platform_owner',
			actor_owner_email: session.email,
			event_type: 'domain.provisioned',
			target_type: 'domain',
			target_id: domain.id,
			after_state: afterState,
			idempotency_key: input.idempotency_key
		});
		if (auditError) {
			if (auditError.code !== '23505') throw auditError;
			const replay = await client
				.from('communication_email_authority_events')
				.select('target_id, after_state')
				.eq('organization_id', organizationId.data)
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

		return json({ domain_id: domain.id, ...afterState }, { status: 201, headers: noStore });
	} catch (error) {
		console.error('Could not provision the sending domain.', error);
		const providerFailure = error instanceof BrevoManagementError;
		return json(
			{
				error: providerFailure
					? 'Brevo could not provision the sending domain.'
					: 'The sending domain could not be provisioned.'
			},
			{ status: providerFailure ? 502 : 500, headers: noStore }
		);
	}
};
