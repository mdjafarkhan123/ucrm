import { describe, expect, it, vi } from 'vitest';
import { runMemberIdentityWorker } from './member-identity-worker';

const organizationId = 'b3000000-0000-0000-0000-000000000001';
const authUserId = 'a0000000-0000-0000-0000-000000000001';

function workerClient(
	options: {
		state?: 'required' | 'ban_applied' | 'email_released';
		claimed?: boolean;
		banFails?: boolean;
		renameFails?: boolean;
	} = {}
) {
	const calls: Array<{ name: string; args?: Record<string, unknown> }> = [];
	const rpc = vi.fn(async (name: string, args?: Record<string, unknown>) => {
		calls.push({ name, args });
		if (name === 'claim_member_identity_cleanup') {
			return {
				data:
					options.claimed === false
						? []
						: [
								{
									organization_id: organizationId,
									user_id: authUserId,
									identity_cleanup_state: options.state ?? 'required'
								}
							],
				error: null
			};
		}
		return { data: {}, error: null };
	});

	const updateUserById = vi.fn(async (_userId: string, attributes: Record<string, unknown>) => {
		if (options.banFails && 'ban_duration' in attributes) {
			return { data: {}, error: { message: 'private provider detail' } };
		}
		if (options.renameFails && 'email' in attributes) {
			return { data: {}, error: { message: 'private provider detail' } };
		}
		return { data: {}, error: null };
	});

	return { client: { rpc, auth: { admin: { updateUserById } } }, calls, updateUserById };
}

function stepStates(calls: Array<{ name: string; args?: Record<string, unknown> }>) {
	return calls
		.filter((call) => call.name === 'record_member_identity_cleanup_step')
		.map((call) => call.args?.new_cleanup_state);
}

describe('member identity cleanup worker', () => {
	it('claims a bounded batch and does no Auth work when nothing is queued', async () => {
		const { client, calls, updateUserById } = workerClient({ claimed: false });

		const result = await runMemberIdentityWorker(client as never, 12);

		expect(calls.map((call) => call.name)).toEqual(['claim_member_identity_cleanup']);
		expect(calls[0].args).toMatchObject({ target_batch_size: 12, target_lease_seconds: 300 });
		expect(updateUserById).not.toHaveBeenCalled();
		expect(result).toMatchObject({ claimed: 0, completed: 0, retryRequired: 0 });
	});

	it('bans the login, frees the email, and records each step in order', async () => {
		const { client, calls, updateUserById } = workerClient();

		const result = await runMemberIdentityWorker(client as never);

		expect(updateUserById).toHaveBeenNthCalledWith(1, authUserId, { ban_duration: '876000h' });
		expect(updateUserById).toHaveBeenNthCalledWith(2, authUserId, {
			email: `removed-${authUserId}@removed.invalid`,
			email_confirm: true
		});
		expect(stepStates(calls)).toEqual(['ban_applied', 'email_released', 'done']);
		expect(result).toMatchObject({ claimed: 1, completed: 1, retryRequired: 0 });
	});

	it('resumes a half-finished cleanup without repeating the ban', async () => {
		const { client, calls, updateUserById } = workerClient({ state: 'ban_applied' });

		const result = await runMemberIdentityWorker(client as never);

		expect(updateUserById).toHaveBeenCalledTimes(1);
		expect(updateUserById).toHaveBeenCalledWith(authUserId, {
			email: `removed-${authUserId}@removed.invalid`,
			email_confirm: true
		});
		expect(stepStates(calls)).toEqual(['email_released', 'done']);
		expect(result.completed).toBe(1);
	});

	it('only closes the ledger when both Auth steps are already recorded', async () => {
		const { client, calls, updateUserById } = workerClient({ state: 'email_released' });

		const result = await runMemberIdentityWorker(client as never);

		expect(updateUserById).not.toHaveBeenCalled();
		expect(stepStates(calls)).toEqual(['done']);
		expect(result.completed).toBe(1);
	});

	it('hands the lease back with a safe message when the ban fails', async () => {
		const { client, calls, updateUserById } = workerClient({ banFails: true });

		const result = await runMemberIdentityWorker(client as never);

		expect(updateUserById).toHaveBeenCalledTimes(1);
		expect(stepStates(calls)).toEqual([]);
		expect(calls.at(-1)?.name).toBe('release_member_identity_cleanup');
		expect(JSON.stringify(calls)).not.toContain('private provider detail');
		expect(result.retryRequired).toBe(1);
	});

	it('keeps a banned login queued when the email release fails', async () => {
		const { client, calls } = workerClient({ renameFails: true });

		const result = await runMemberIdentityWorker(client as never);

		expect(stepStates(calls)).toEqual(['ban_applied']);
		expect(calls.at(-1)?.name).toBe('release_member_identity_cleanup');
		expect(result.retryRequired).toBe(1);
	});

	it('refuses an unsafe batch size before database or Auth work', async () => {
		const { client, calls, updateUserById } = workerClient();

		await expect(runMemberIdentityWorker(client as never, 101)).rejects.toThrow(
			'batch size must be between 1 and 100'
		);
		expect(calls).toEqual([]);
		expect(updateUserById).not.toHaveBeenCalled();
	});
});
