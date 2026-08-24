import { describe, expect, it, vi } from 'vitest';
import { runTeamInvitationWorker } from './invitation-worker';

const invitationId = 'a3000000-0000-0000-0000-000000000001';
const authUserId = 'a0000000-0000-0000-0000-000000000001';

function workerClient(
	options: {
		receipt?: 'matching' | 'password' | 'missing' | 'mismatch';
		deleteFails?: boolean;
		claimed?: boolean;
	} = {}
) {
	const calls: Array<{ name: string; args?: Record<string, unknown> }> = [];
	const receipt = options.receipt ?? 'matching';
	const rpc = vi.fn(async (name: string, args?: Record<string, unknown>) => {
		calls.push({ name, args });
		if (name === 'expire_team_invitations_bounded')
			return { data: [{ id: 'expired' }], error: null };
		if (name === 'sweep_team_invitation_reservations_bounded') {
			return { data: [{ id: 'reservation' }], error: null };
		}
		if (name === 'claim_team_invitation_reconciliation') {
			return {
				data: options.claimed === false ? [] : [{ id: invitationId, invited_user_id: authUserId }],
				error: null
			};
		}
		if (name === 'find_team_invitation_auth_receipt') {
			if (receipt === 'missing') return { data: [], error: null };
			return {
				data: [
					{
						user_id: authUserId,
						identity_invitation_id: receipt === 'mismatch' ? 'another-invitation' : invitationId,
						password_set_invitation_id: receipt === 'password' ? invitationId : null
					}
				],
				error: null
			};
		}
		return { data: { id: invitationId }, error: null };
	});
	const deleteUser = vi
		.fn()
		.mockResolvedValue(
			options.deleteFails
				? { data: {}, error: { message: 'private provider detail' } }
				: { data: {}, error: null }
		);

	return {
		client: { rpc, auth: { admin: { deleteUser } } },
		calls,
		deleteUser
	};
}

describe('team invitation maintenance worker', () => {
	it('runs bounded maintenance before claiming cleanup work', async () => {
		const { client, calls } = workerClient({ claimed: false });

		const result = await runTeamInvitationWorker(client as never, 12);

		expect(calls.map((call) => call.name)).toEqual([
			'expire_team_invitations_bounded',
			'sweep_team_invitation_reservations_bounded',
			'claim_team_invitation_reconciliation'
		]);
		expect(calls[0].args).toEqual({ target_batch_size: 12 });
		expect(calls[1].args).toEqual({
			target_batch_size: 12,
			target_stale_after: '1 hour'
		});
		expect(result).toMatchObject({ expired: 1, reservationsSwept: 1, claimed: 0 });
	});

	it('prepares, deletes, and settles only a receipt-owned Auth identity', async () => {
		const { client, calls, deleteUser } = workerClient();

		const result = await runTeamInvitationWorker(client as never);

		expect(deleteUser).toHaveBeenCalledWith(authUserId);
		expect(calls.slice(3).map((call) => call.name)).toEqual([
			'find_team_invitation_auth_receipt',
			'prepare_team_invitation_identity_cleanup',
			'settle_team_invitation_identity_cleanup'
		]);
		expect(result).toMatchObject({ claimed: 1, cleaned: 1, finalized: 0, retryRequired: 0 });
	});

	it('finalizes a matching password receipt without deleting the Auth identity', async () => {
		const { client, calls, deleteUser } = workerClient({ receipt: 'password' });

		const result = await runTeamInvitationWorker(client as never);

		expect(deleteUser).not.toHaveBeenCalled();
		expect(calls.at(-1)?.name).toBe('finalize_reconciled_team_invitation');
		expect(result.finalized).toBe(1);
	});

	it('settles a confirmed absent Auth identity without calling delete', async () => {
		const { client, calls, deleteUser } = workerClient({ receipt: 'missing' });

		const result = await runTeamInvitationWorker(client as never);

		expect(deleteUser).not.toHaveBeenCalled();
		expect(calls.slice(-2).map((call) => call.name)).toEqual([
			'prepare_team_invitation_identity_cleanup',
			'settle_team_invitation_identity_cleanup'
		]);
		expect(result.cleaned).toBe(1);
	});

	it('never deletes an identity carrying another invitation receipt', async () => {
		const { client, calls, deleteUser } = workerClient({ receipt: 'mismatch' });

		const result = await runTeamInvitationWorker(client as never);

		expect(deleteUser).not.toHaveBeenCalled();
		expect(calls.at(-1)?.name).toBe('release_team_invitation_reconciliation');
		expect(result.retryRequired).toBe(1);
	});

	it('keeps cleanup retryable after an uncertain Auth deletion', async () => {
		const { client, calls } = workerClient({ deleteFails: true });

		const result = await runTeamInvitationWorker(client as never);

		expect(calls.slice(-2).map((call) => call.name)).toEqual([
			'prepare_team_invitation_identity_cleanup',
			'release_team_invitation_reconciliation'
		]);
		expect(JSON.stringify(calls)).not.toContain('private provider detail');
		expect(result.retryRequired).toBe(1);
	});

	it('refuses an unsafe batch size before database or Auth work', async () => {
		const { client, calls, deleteUser } = workerClient();

		await expect(runTeamInvitationWorker(client as never, 101)).rejects.toThrow(
			'batch size must be between 1 and 100'
		);
		expect(calls).toEqual([]);
		expect(deleteUser).not.toHaveBeenCalled();
	});
});
