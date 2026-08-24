import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	SenderCommandError,
	createCommunicationSender
} from '$lib/server/communications/sender-commands';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	communicationSenderCreateSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

function contractorSender(sender: Awaited<ReturnType<typeof createCommunicationSender>>['sender']) {
	return {
		id: sender.id,
		domain_id: sender.domain_id,
		email_address: sender.email_address,
		display_name: sender.display_name,
		lifecycle_state: sender.lifecycle_state,
		assigned_user_id: sender.assigned_user_id,
		is_organization_default: sender.is_organization_default,
		allows_manual: sender.allows_manual,
		allows_automated: sender.allows_automated,
		restriction_reason: sender.restriction_reason,
		created_at: sender.created_at,
		updated_at: sender.updated_at
	};
}

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const [senders, domains] = await Promise.all([
		event.locals.supabase
			.from('communication_email_senders')
			.select(
				'id, domain_id, email_address, display_name, lifecycle_state, assigned_user_id, is_organization_default, allows_manual, allows_automated, restriction_reason, created_at, updated_at'
			)
			.eq('organization_id', organizationId)
			.neq('lifecycle_state', 'removed')
			.order('created_at'),
		event.locals.supabase
			.from('communication_email_domains')
			.select('id, domain_name, lifecycle_state, ownership_status, dkim_status, spf_status')
			.eq('organization_id', organizationId)
			.eq('purpose', 'sending')
			.neq('lifecycle_state', 'removed')
			.order('created_at')
	]);

	if (senders.error || domains.error) {
		console.error('Could not load communication senders.', senders.error ?? domains.error);
		return json({ error: 'Email senders could not be loaded.' }, { status: 500, headers: noStore });
	}

	return json({ senders: senders.data ?? [], domains: domains.data ?? [] }, { headers: noStore });
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationSenderCreateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the sender details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `communication_sender:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const input = parsed.data;
		const result = await createCommunicationSender(client, {
			organizationId: check.auth.organization.id,
			actorUserId: check.auth.user.id,
			domainId: input.domain_id,
			emailAddress: input.email_address,
			displayName: input.display_name,
			assignedUserId: input.assigned_user_id,
			isOrganizationDefault: input.is_organization_default,
			allowsManual: input.allows_manual,
			allowsAutomated: input.allows_automated,
			idempotencyKey: input.idempotency_key
		});
		return json(
			{ sender: contractorSender(result.sender), replayed: result.replayed },
			{ status: result.replayed ? 200 : 201, headers: noStore }
		);
	} catch (error) {
		if (error instanceof SenderCommandError) {
			return json(
				{ error: error.message, reason: error.reason, field_errors: error.fieldErrors },
				{ status: error.status, headers: noStore }
			);
		}
		console.error('Could not create communication sender.', error);
		return json(
			{ error: 'The email sender could not be created.' },
			{ status: 500, headers: noStore }
		);
	}
};
