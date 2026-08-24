import { randomUUID } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

const DEFAULT_BATCH_SIZE = 25;
const LEASE_SECONDS = 300;
const AUTH_CONCURRENCY = 5;

type RpcError = { message?: string };
type WorkerRpc = (
	name: string,
	args?: Record<string, unknown>
) => Promise<{ data: unknown; error: RpcError | null }>;

type ClaimedInvitation = {
	id: string;
	invited_user_id: string | null;
};

type AuthReceipt = {
	user_id: string;
	identity_invitation_id: string | null;
	password_set_invitation_id: string | null;
};

export type TeamInvitationWorkerResult = {
	expired: number;
	reservationsSwept: number;
	claimed: number;
	finalized: number;
	cleaned: number;
	retryRequired: number;
};

function workerRpc(client: SupabaseClient<Database>) {
	return client.rpc.bind(client) as unknown as WorkerRpc;
}

async function requireRpcRows<T>(
	rpc: WorkerRpc,
	name: string,
	args?: Record<string, unknown>
): Promise<T[]> {
	const { data, error } = await rpc(name, args);
	if (error) throw new Error(`Invitation worker database command failed: ${name}`);
	return (data ?? []) as T[];
}

async function requireRpcResult(
	rpc: WorkerRpc,
	name: string,
	args: Record<string, unknown>
): Promise<void> {
	const { error } = await rpc(name, args);
	if (error) throw new Error(`Invitation worker database command failed: ${name}`);
}

async function releaseLease(
	rpc: WorkerRpc,
	invitationId: string,
	leaseNonce: string,
	safeError: string
) {
	try {
		await requireRpcResult(rpc, 'release_team_invitation_reconciliation', {
			target_invitation_id: invitationId,
			target_lease_nonce: leaseNonce,
			target_safe_error: safeError
		});
	} catch {
		// A crashed release remains safe: the short lease expires and a later run can retry it.
	}
}

async function prepareAndSettleAbsentIdentity(
	rpc: WorkerRpc,
	invitationId: string,
	leaseNonce: string
) {
	await requireRpcResult(rpc, 'prepare_team_invitation_identity_cleanup', {
		target_invitation_id: invitationId,
		target_lease_nonce: leaseNonce
	});
	await requireRpcResult(rpc, 'settle_team_invitation_identity_cleanup', {
		target_invitation_id: invitationId,
		target_lease_nonce: leaseNonce
	});
}

async function reconcileInvitation(
	client: SupabaseClient<Database>,
	rpc: WorkerRpc,
	invitation: ClaimedInvitation,
	leaseNonce: string
): Promise<'finalized' | 'cleaned' | 'retry'> {
	try {
		const receipts = await requireRpcRows<AuthReceipt>(rpc, 'find_team_invitation_auth_receipt', {
			target_invitation_id: invitation.id
		});
		const receipt = receipts[0];

		if (!receipt) {
			await prepareAndSettleAbsentIdentity(rpc, invitation.id, leaseNonce);
			return 'cleaned';
		}

		if (receipt.identity_invitation_id !== invitation.id) {
			await releaseLease(
				rpc,
				invitation.id,
				leaseNonce,
				'Invitation Auth identity receipt does not match; manual review is required.'
			);
			return 'retry';
		}

		if (receipt.password_set_invitation_id === invitation.id) {
			await requireRpcResult(rpc, 'finalize_reconciled_team_invitation', {
				target_invitation_id: invitation.id,
				target_lease_nonce: leaseNonce
			});
			return 'finalized';
		}

		await requireRpcResult(rpc, 'prepare_team_invitation_identity_cleanup', {
			target_invitation_id: invitation.id,
			target_lease_nonce: leaseNonce
		});

		const { error: deleteError } = await client.auth.admin.deleteUser(receipt.user_id);
		if (deleteError) {
			await releaseLease(
				rpc,
				invitation.id,
				leaseNonce,
				'Invitation Auth identity deletion needs retry.'
			);
			return 'retry';
		}

		await requireRpcResult(rpc, 'settle_team_invitation_identity_cleanup', {
			target_invitation_id: invitation.id,
			target_lease_nonce: leaseNonce
		});
		return 'cleaned';
	} catch {
		await releaseLease(rpc, invitation.id, leaseNonce, 'Invitation reconciliation needs retry.');
		return 'retry';
	}
}

export async function runTeamInvitationWorker(
	client: SupabaseClient<Database>,
	batchSize = DEFAULT_BATCH_SIZE
): Promise<TeamInvitationWorkerResult> {
	if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) {
		throw new Error('The invitation worker batch size must be between 1 and 100.');
	}

	const rpc = workerRpc(client);
	const expired = await requireRpcRows(rpc, 'expire_team_invitations_bounded', {
		target_batch_size: batchSize
	});
	const reservations = await requireRpcRows(rpc, 'sweep_team_invitation_reservations_bounded', {
		target_batch_size: batchSize,
		target_stale_after: '1 hour'
	});

	const leaseNonce = randomUUID();
	const claimed = await requireRpcRows<ClaimedInvitation>(
		rpc,
		'claim_team_invitation_reconciliation',
		{
			target_lease_nonce: leaseNonce,
			target_batch_size: batchSize,
			target_lease_seconds: LEASE_SECONDS
		}
	);

	const outcomes: Array<'finalized' | 'cleaned' | 'retry'> = [];
	for (let start = 0; start < claimed.length; start += AUTH_CONCURRENCY) {
		const chunk = claimed.slice(start, start + AUTH_CONCURRENCY);
		outcomes.push(
			...(await Promise.all(
				chunk.map((invitation) => reconcileInvitation(client, rpc, invitation, leaseNonce))
			))
		);
	}

	return {
		expired: expired.length,
		reservationsSwept: reservations.length,
		claimed: claimed.length,
		finalized: outcomes.filter((outcome) => outcome === 'finalized').length,
		cleaned: outcomes.filter((outcome) => outcome === 'cleaned').length,
		retryRequired: outcomes.filter((outcome) => outcome === 'retry').length
	};
}
