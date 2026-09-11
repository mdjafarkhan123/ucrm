import { randomUUID } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

const DEFAULT_BATCH_SIZE = 25;
const LEASE_SECONDS = 300;
const AUTH_CONCURRENCY = 5;

// A ban has to be given a length, so Supabase's documented "effectively forever" duration is what a
// permanent removal gets.
const PERMANENT_BAN_DURATION = '876000h';

type RpcError = { message?: string };
type WorkerRpc = (
	name: string,
	args?: Record<string, unknown>
) => Promise<{ data: unknown; error: RpcError | null }>;

type ClaimedMember = {
	organization_id: string;
	user_id: string;
	identity_cleanup_state: string;
};

export type MemberIdentityWorkerResult = {
	claimed: number;
	completed: number;
	retryRequired: number;
};

// .invalid can never be registered (RFC 2606), and deriving it from the user id keeps a retried rename
// identical to the one that may already have landed.
function tombstoneEmail(userId: string) {
	return `removed-${userId}@removed.invalid`;
}

function workerRpc(client: SupabaseClient<Database>) {
	return client.rpc.bind(client) as unknown as WorkerRpc;
}

async function requireRpcRows<T>(
	rpc: WorkerRpc,
	name: string,
	args?: Record<string, unknown>
): Promise<T[]> {
	const { data, error } = await rpc(name, args);
	if (error) throw new Error(`Member identity worker database command failed: ${name}`);
	return (data ?? []) as T[];
}

async function recordStep(
	rpc: WorkerRpc,
	member: ClaimedMember,
	leaseNonce: string,
	state: 'ban_applied' | 'email_released' | 'done'
) {
	const { error } = await rpc('record_member_identity_cleanup_step', {
		target_organization_id: member.organization_id,
		target_user_id: member.user_id,
		target_lease_nonce: leaseNonce,
		new_cleanup_state: state
	});
	if (error) throw new Error('Member identity worker database command failed: record step');
}

async function releaseLease(
	rpc: WorkerRpc,
	member: ClaimedMember,
	leaseNonce: string,
	safeError: string
) {
	try {
		await rpc('release_member_identity_cleanup', {
			target_organization_id: member.organization_id,
			target_user_id: member.user_id,
			target_lease_nonce: leaseNonce,
			target_safe_error: safeError
		});
	} catch {
		// A crashed release stays safe: the short lease expires and a later run retries the same step.
	}
}

async function cleanUpIdentity(
	client: SupabaseClient<Database>,
	rpc: WorkerRpc,
	member: ClaimedMember,
	leaseNonce: string
): Promise<'completed' | 'retry'> {
	try {
		let state = member.identity_cleanup_state;

		if (state === 'required') {
			// The login has to die at Auth, not only at our status gate: removal is permanent, and an
			// unbanned account would still hold the address and still mint tokens.
			const { error } = await client.auth.admin.updateUserById(member.user_id, {
				ban_duration: PERMANENT_BAN_DURATION
			});
			if (error) {
				await releaseLease(rpc, member, leaseNonce, 'Banning the removed login needs a retry.');
				return 'retry';
			}
			await recordStep(rpc, member, leaseNonce, 'ban_applied');
			state = 'ban_applied';
		}

		if (state === 'ban_applied') {
			// Renaming the address is what frees the real email for a fresh invitation. Deleting the login
			// instead is not an option: authorship columns across the app point at it.
			const { error } = await client.auth.admin.updateUserById(member.user_id, {
				email: tombstoneEmail(member.user_id),
				email_confirm: true
			});
			if (error) {
				await releaseLease(rpc, member, leaseNonce, 'Releasing the removed email needs a retry.');
				return 'retry';
			}
			await recordStep(rpc, member, leaseNonce, 'email_released');
		}

		await recordStep(rpc, member, leaseNonce, 'done');
		return 'completed';
	} catch {
		await releaseLease(rpc, member, leaseNonce, 'The identity cleanup needs a retry.');
		return 'retry';
	}
}

export async function runMemberIdentityWorker(
	client: SupabaseClient<Database>,
	batchSize = DEFAULT_BATCH_SIZE
): Promise<MemberIdentityWorkerResult> {
	if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) {
		throw new Error('The member identity worker batch size must be between 1 and 100.');
	}

	const rpc = workerRpc(client);
	const leaseNonce = randomUUID();
	const claimed = await requireRpcRows<ClaimedMember>(rpc, 'claim_member_identity_cleanup', {
		target_lease_nonce: leaseNonce,
		target_batch_size: batchSize,
		target_lease_seconds: LEASE_SECONDS
	});

	const outcomes: Array<'completed' | 'retry'> = [];
	for (let start = 0; start < claimed.length; start += AUTH_CONCURRENCY) {
		const chunk = claimed.slice(start, start + AUTH_CONCURRENCY);
		outcomes.push(
			...(await Promise.all(
				chunk.map((member) => cleanUpIdentity(client, rpc, member, leaseNonce))
			))
		);
	}

	return {
		claimed: claimed.length,
		completed: outcomes.filter((outcome) => outcome === 'completed').length,
		retryRequired: outcomes.filter((outcome) => outcome === 'retry').length
	};
}
