import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { BrevoManagementError, deleteBrevoDomain } from '$lib/server/communications/brevo';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationDomainRemovalSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { z } from 'zod';

const noStore = { 'Cache-Control': 'no-store' };
const domainIdSchema = z.string().uuid();

type DomainRow = {
	id: string;
	domain_name: string;
	purpose: string;
	lifecycle_state: string;
	provider_domain_id: string | null;
};

type RemovalImpact = {
	live_sender_count: number;
	live_replacement_count: number;
};

async function loadDomain(
	client: ReturnType<typeof getOwnerSupabaseClient>,
	organizationId: string,
	domainId: string
): Promise<DomainRow | null> {
	const { data, error } = await client
		.from('communication_email_domains')
		.select('id, domain_name, purpose, lifecycle_state, provider_domain_id')
		.eq('organization_id', organizationId)
		.eq('id', domainId)
		.maybeSingle();
	if (error) throw error;
	return data;
}

async function loadImpact(
	client: ReturnType<typeof getOwnerSupabaseClient>,
	organizationId: string,
	domainId: string
): Promise<RemovalImpact> {
	const [senders, replacements] = await Promise.all([
		client
			.from('communication_email_senders')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.eq('domain_id', domainId)
			.neq('lifecycle_state', 'removed'),
		client
			.from('communication_email_domains')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.eq('replacement_of_domain_id', domainId)
			.neq('lifecycle_state', 'removed')
	]);
	if (senders.error) throw senders.error;
	if (replacements.error) throw replacements.error;
	return {
		live_sender_count: senders.count ?? 0,
		live_replacement_count: replacements.count ?? 0
	};
}

function invalidIdentifierResponse() {
	return json({ error: 'The domain identifier is invalid.' }, { status: 422, headers: noStore });
}

async function authenticateAndValidate(event: Parameters<RequestHandler>[0]): Promise<
	| {
			ok: true;
			session: NonNullable<Awaited<ReturnType<typeof getOwnerSession>>>;
			organizationId: string;
			domainId: string;
	  }
	| { ok: false; response: Response }
> {
	const session = await getOwnerSession(event);
	if (!session) return { ok: false, response: ownerUnauthorized() };
	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const domainId = domainIdSchema.safeParse(event.params.domainId);
	if (!organizationId.success || !domainId.success) {
		return { ok: false, response: invalidIdentifierResponse() };
	}
	return { ok: true, session, organizationId: organizationId.data, domainId: domainId.data };
}

export const GET: RequestHandler = async (event) => {
	const auth = await authenticateAndValidate(event);
	if (!auth.ok) {
		auth.response.headers.set('Cache-Control', 'no-store');
		return auth.response;
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `email_domain_remove_preview:${auth.session.sessionId}`,
			windowSeconds: 300,
			maxAttempts: 30
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const domain = await loadDomain(client, auth.organizationId, auth.domainId);
		if (!domain || domain.purpose !== 'sending' || domain.lifecycle_state === 'removed') {
			return json({ error: 'Sending domain was not found.' }, { status: 404, headers: noStore });
		}
		const impact = await loadImpact(client, auth.organizationId, auth.domainId);
		return json(
			{
				domain_id: domain.id,
				domain_name: domain.domain_name,
				lifecycle_state: domain.lifecycle_state,
				impact,
				can_remove: impact.live_sender_count === 0 && impact.live_replacement_count === 0
			},
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not preview sending-domain removal.', error);
		return json(
			{ error: 'The sending-domain removal impact could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
};

export const POST: RequestHandler = async (event) => {
	const auth = await authenticateAndValidate(event);
	if (!auth.ok) {
		auth.response.headers.set('Cache-Control', 'no-store');
		return auth.response;
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationDomainRemovalSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the sending-domain removal.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	const input = parsed.data;
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `email_domain_remove:${auth.session.sessionId}`,
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
			.eq('organization_id', auth.organizationId)
			.eq('target_id', auth.domainId)
			.eq('event_type', 'domain.removed')
			.eq('idempotency_key', input.idempotency_key)
			.maybeSingle();
		if (receiptError) throw receiptError;
		if (receipt) {
			return json(
				{ domain_id: receipt.target_id, ...(receipt.after_state as object), replayed: true },
				{ headers: noStore }
			);
		}

		const domain = await loadDomain(client, auth.organizationId, auth.domainId);
		if (!domain || domain.purpose !== 'sending' || domain.lifecycle_state === 'removed') {
			return json({ error: 'Sending domain was not found.' }, { status: 404, headers: noStore });
		}
		if (domain.domain_name !== input.confirm_domain_name) {
			return json(
				{
					error: 'The confirmation does not match this sending domain.',
					field_errors: { confirm_domain_name: 'Type the exact sending domain.' }
				},
				{ status: 422, headers: noStore }
			);
		}

		const { data: startResult, error: startError } = await client.rpc(
			'begin_communication_email_domain_removal',
			{
				target_organization_id: auth.organizationId,
				target_domain_id: auth.domainId,
				expected_live_sender_count: input.expected_impact.live_sender_count,
				expected_live_replacement_count: input.expected_impact.live_replacement_count
			}
		);
		if (startError) throw startError;
		const removalStart = startResult as {
			status: 'not_found' | 'impact_changed' | 'blocked' | 'started';
			live_sender_count?: number;
			live_replacement_count?: number;
			previous_lifecycle_state?: string;
		};
		const impact = {
			live_sender_count: removalStart.live_sender_count ?? 0,
			live_replacement_count: removalStart.live_replacement_count ?? 0
		};
		if (removalStart.status === 'not_found') {
			return json({ error: 'Sending domain was not found.' }, { status: 404, headers: noStore });
		}
		if (removalStart.status === 'impact_changed') {
			return json(
				{ error: 'The removal impact changed. Review it again before continuing.', impact },
				{ status: 409, headers: noStore }
			);
		}
		if (removalStart.status === 'blocked') {
			return json(
				{
					error: 'Remove or finish the affected senders and replacement domains first.',
					impact
				},
				{ status: 409, headers: noStore }
			);
		}

		try {
			await deleteBrevoDomain(domain.domain_name);
		} catch (error) {
			if (!(error instanceof BrevoManagementError) || error.status !== 404) {
				const cleanupCode =
					error instanceof BrevoManagementError ? error.code : 'brevo_cleanup_unknown';
				const { error: cleanupUpdateError } = await client
					.from('communication_email_domains')
					.update({ provider_cleanup_error: cleanupCode, updated_at: new Date().toISOString() })
					.eq('organization_id', auth.organizationId)
					.eq('id', domain.id)
					.eq('lifecycle_state', 'removal_pending');
				if (cleanupUpdateError) throw cleanupUpdateError;
				return json(
					{
						error:
							'Brevo cleanup is not confirmed yet. This removal remains pending and can be retried.',
						domain_id: domain.id,
						lifecycle_state: 'removal_pending',
						retryable: true
					},
					{ status: 502, headers: noStore }
				);
			}
		}

		const { data: finalizeResult, error: finalizeError } = await client.rpc(
			'finalize_communication_email_domain_removal',
			{
				target_organization_id: auth.organizationId,
				target_domain_id: domain.id,
				actor_owner_email: auth.session.email,
				removal_reason: input.reason,
				command_idempotency_key: input.idempotency_key
			}
		);
		if (finalizeError) throw finalizeError;
		const finalized = finalizeResult as unknown as {
			status: 'completed' | 'replayed' | 'not_found' | 'not_pending';
			domain_name?: string;
			purpose?: string;
			lifecycle_state?: string;
			provider_cleanup_confirmed?: boolean;
			removed_at?: string;
		};
		if (finalized.status === 'not_found' || finalized.status === 'not_pending') {
			throw new Error('Domain removal finalization lost its pending authority.');
		}

		const { status: finalizeStatus, ...afterState } = finalized;
		return json(
			{
				domain_id: domain.id,
				...afterState,
				replayed: finalizeStatus === 'replayed'
			},
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not remove the sending domain.', error);
		return json(
			{ error: 'The sending domain could not be removed.' },
			{ status: 500, headers: noStore }
		);
	}
};
