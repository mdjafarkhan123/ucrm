import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

type Sender = Database['public']['Tables']['communication_email_senders']['Row'];

type SenderClaim = {
	replayed: boolean;
	sender: Sender;
};

export class SenderCommandError extends Error {
	constructor(
		message: string,
		public readonly status: number,
		public readonly reason: string,
		public readonly fieldErrors?: Record<string, string>
	) {
		super(message);
		this.name = 'SenderCommandError';
	}
}

function databaseCommandError(error: { code?: string; message?: string }): never {
	const message = error.message ?? '';
	if (error.code === '23505')
		throw new SenderCommandError(
			message.includes('idempotency')
				? 'That sender action was already used for something different.'
				: 'That sender address or default is already in use.',
			409,
			'conflict'
		);
	if (error.code === '23503' || error.code === 'P0002')
		throw new SenderCommandError(
			'The sender or sending domain could not be found.',
			404,
			'not_found'
		);
	if (error.code === '23514' || error.code === '22023')
		throw new SenderCommandError(message || 'The sender is not eligible.', 422, 'not_eligible');
	throw error;
}

function parseClaim(value: unknown): SenderClaim {
	const claim = value as SenderClaim | null;
	if (!claim?.sender?.id) throw new Error('The sender command returned an invalid claim.');
	return claim;
}

export async function createCommunicationSender(
	client: SupabaseClient<Database>,
	input: {
		organizationId: string;
		actorUserId: string;
		domainId: string;
		emailAddress: string;
		displayName: string;
		assignedUserId: string | null;
		isOrganizationDefault: boolean;
		allowsManual: boolean;
		allowsAutomated: boolean;
		idempotencyKey: string;
	}
) {
	const started = await client.rpc('begin_communication_email_sender_create', {
		target_organization_id: input.organizationId,
		target_domain_id: input.domainId,
		target_email_address: input.emailAddress,
		target_display_name: input.displayName,
		// Postgres accepts NULL for this optional UUID argument; generated RPC argument types do not
		// preserve function-argument nullability.
		target_assigned_user_id: input.assignedUserId as string,
		target_is_organization_default: input.isOrganizationDefault,
		target_allows_manual: input.allowsManual,
		target_allows_automated: input.allowsAutomated,
		actor_user_id: input.actorUserId,
		command_idempotency_key: input.idempotencyKey
	});
	if (started.error) databaseCommandError(started.error);
	const claim = parseClaim(started.data);
	if (claim.sender.lifecycle_state === 'enabled') return { sender: claim.sender, replayed: true };

	// Amazon SES has no per-address sender registration: once the domain identity is verified, the domain
	// alone governs sending, so there is no provider-side sender to create and no provider id to store.
	const finalized = await client.rpc('finalize_communication_email_sender_create', {
		target_organization_id: input.organizationId,
		target_sender_id: claim.sender.id,
		actor_user_id: input.actorUserId,
		command_idempotency_key: input.idempotencyKey
	});
	if (finalized.error) databaseCommandError(finalized.error);
	return { sender: finalized.data, replayed: claim.replayed };
}

export async function updateCommunicationSender(
	client: SupabaseClient<Database>,
	input: {
		organizationId: string;
		actorUserId: string;
		senderId: string;
		displayName: string;
		assignedUserId: string | null;
		isOrganizationDefault: boolean;
		allowsManual: boolean;
		allowsAutomated: boolean;
		enabled: boolean;
		idempotencyKey: string;
	}
) {
	const started = await client.rpc('begin_communication_email_sender_update', {
		target_organization_id: input.organizationId,
		target_sender_id: input.senderId,
		target_display_name: input.displayName,
		// Postgres accepts NULL for this optional UUID argument; generated RPC argument types do not
		// preserve function-argument nullability.
		target_assigned_user_id: input.assignedUserId as string,
		target_is_organization_default: input.isOrganizationDefault,
		target_allows_manual: input.allowsManual,
		target_allows_automated: input.allowsAutomated,
		target_enabled: input.enabled,
		actor_user_id: input.actorUserId,
		command_idempotency_key: input.idempotencyKey
	});
	if (started.error) databaseCommandError(started.error);
	const claim = parseClaim(started.data);

	const finalized = await client.rpc('finalize_communication_email_sender_update', {
		target_organization_id: input.organizationId,
		target_sender_id: input.senderId,
		actor_user_id: input.actorUserId,
		command_idempotency_key: input.idempotencyKey
	});
	if (finalized.error) databaseCommandError(finalized.error);
	return { sender: finalized.data, replayed: claim.replayed };
}

/**
 * Removes a sender address. History that references it is kept; queued email is left to the claim command,
 * which holds manual email for review and cancels automated email rather than re-sending it from someone else.
 */
export async function removeCommunicationSender(
	client: SupabaseClient<Database>,
	input: {
		organizationId: string;
		actorUserId: string;
		senderId: string;
		idempotencyKey: string;
	}
) {
	const removed = await client.rpc('remove_communication_email_sender', {
		target_organization_id: input.organizationId,
		target_sender_id: input.senderId,
		actor_user_id: input.actorUserId,
		command_idempotency_key: input.idempotencyKey
	});
	if (removed.error) databaseCommandError(removed.error);
	return parseClaim(removed.data);
}

export type SenderRemovalImpact = {
	is_organization_default: boolean;
	assigned_member_name: string | null;
	queued_email_count: number;
	other_enabled_sender_count: number;
};

/** What removing a sender will change, shown before the owner confirms. */
export async function loadSenderRemovalImpact(
	client: SupabaseClient<Database>,
	organizationId: string,
	senderId: string
): Promise<SenderRemovalImpact | null> {
	const { data: sender, error } = await client
		.from('communication_email_senders')
		.select('id, assigned_user_id, is_organization_default, lifecycle_state')
		.eq('organization_id', organizationId)
		.eq('id', senderId)
		.neq('lifecycle_state', 'removed')
		.maybeSingle();
	if (error) throw error;
	if (!sender) return null;

	const [queued, others, member] = await Promise.all([
		client
			.from('communication_delivery_intents')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.eq('sender_id', senderId)
			.in('status', ['queued', 'claimed']),
		client
			.from('communication_email_senders')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.eq('lifecycle_state', 'enabled')
			.neq('id', senderId),
		sender.assigned_user_id
			? client.from('profiles').select('full_name').eq('id', sender.assigned_user_id).maybeSingle()
			: Promise.resolve({ data: null, error: null })
	]);
	if (queued.error) throw queued.error;
	if (others.error) throw others.error;
	if (member.error) throw member.error;

	return {
		is_organization_default: sender.is_organization_default,
		assigned_member_name: member.data?.full_name ?? null,
		queued_email_count: queued.count ?? 0,
		other_enabled_sender_count: others.count ?? 0
	};
}
