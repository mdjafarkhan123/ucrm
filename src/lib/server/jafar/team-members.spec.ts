import { createHash } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
	TeamMemberError,
	acceptTeamInvitation,
	completeTeamPasswordReset,
	inviteTeamMember,
	removeTeamMember,
	requestTeamPasswordReset,
	verifyTeammateCredentials
} from './team-members';

const sendTransactionalEmail = vi.fn();
vi.mock('$lib/server/email/brevo', () => ({
	sendTransactionalEmail: (params: unknown) => sendTransactionalEmail(params)
}));

type Call = { table: string; op: string; values?: Record<string, unknown>; filters: string[] };

/**
 * A stand-in for the service-role client: records each statement's table, operation, values and filters,
 * and answers from `results` in order.
 */
function fakeClient(results: { data: unknown; error: unknown }[]) {
	const calls: Call[] = [];
	const client = {
		from(table: string) {
			const call: Call = { table, op: 'select', filters: [] };
			calls.push(call);
			const builder: Record<string, unknown> = {};
			const chain =
				(name: string) =>
				(...args: unknown[]) => {
					if (['insert', 'update'].includes(name)) {
						call.op = name;
						call.values = args[0] as Record<string, unknown>;
					} else if (name !== 'select' && name !== 'order') {
						call.filters.push(`${name}:${String(args[0])}=${String(args[1])}`);
					}
					return builder;
				};
			for (const name of ['select', 'insert', 'update', 'eq', 'neq', 'gt', 'is', 'order']) {
				builder[name] = chain(name);
			}
			const answer = () => Promise.resolve(results.shift() ?? { data: null, error: null });
			builder.single = answer;
			builder.maybeSingle = answer;
			builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
				answer().then(resolve, reject);
			return builder;
		}
	};
	return { client: client as never, calls };
}

const sha256 = (value: string) => createHash('sha256').update(value).digest('hex');

beforeEach(() => {
	sendTransactionalEmail.mockReset();
	sendTransactionalEmail.mockResolvedValue(undefined);
});

describe('inviting a teammate', () => {
	const params = {
		email: ' Sam@Uplift.Example ',
		role: 'sales' as const,
		invitedBy: 'owner@example.com',
		origin: 'https://app.example.com',
		ownerEmail: 'owner@example.com'
	};

	it('refuses the owner’s own email before touching the database', async () => {
		const { client, calls } = fakeClient([]);
		await expect(
			inviteTeamMember(client, { ...params, email: 'OWNER@example.com' })
		).rejects.toMatchObject({ code: 'owner_email' });
		expect(calls).toHaveLength(0);
	});

	it('stores only the link’s hash, and emails the link itself', async () => {
		const { client, calls } = fakeClient([
			{
				data: { id: 'm1', email: 'sam@uplift.example', role: 'sales', status: 'invited' },
				error: null
			}
		]);
		await inviteTeamMember(client, params);

		expect(calls[0].values).toMatchObject({ email: 'sam@uplift.example', status: 'invited' });
		const sent = sendTransactionalEmail.mock.calls[0][0];
		const token = new URL(sent.textContent.match(/https:\/\/\S+/)[0]).searchParams.get('token')!;
		expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
		expect(calls[0].values?.invitation_token_hash).toBe(sha256(token));
		expect(JSON.stringify(calls[0].values)).not.toContain(token);
	});

	it('explains a duplicate instead of failing', async () => {
		const { client } = fakeClient([{ data: null, error: { code: '23505' } }]);
		await expect(inviteTeamMember(client, params)).rejects.toMatchObject({
			code: 'already_on_team'
		});
	});

	it('keeps the invitation when its email fails, so it can be resent', async () => {
		sendTransactionalEmail.mockRejectedValue(new Error('provider down'));
		const { client } = fakeClient([{ data: { id: 'm1', role: 'sales' }, error: null }]);
		await expect(inviteTeamMember(client, params)).rejects.toMatchObject({ code: 'email_failed' });
	});
});

describe('accepting an invitation', () => {
	it('works once: the update is conditional on a waiting, unexpired link', async () => {
		const { client, calls } = fakeClient([
			{ data: { id: 'm1', email: 'sam@uplift.example' }, error: null }
		]);
		const result = await acceptTeamInvitation(client, {
			token: 'a'.repeat(43),
			fullName: 'Sam Seller',
			password: 'long enough'
		});

		expect(result).toEqual({ memberId: 'm1', email: 'sam@uplift.example' });
		expect(calls[0].filters).toEqual(
			expect.arrayContaining([
				`eq:invitation_token_hash=${sha256('a'.repeat(43))}`,
				'eq:status=invited'
			])
		);
		expect(calls[0].values).toMatchObject({ status: 'active', invitation_token_hash: null });
		expect(await bcrypt.compare('long enough', calls[0].values?.password_hash as string)).toBe(
			true
		);
	});

	it('reports a used or expired link', async () => {
		const { client } = fakeClient([{ data: null, error: null }]);
		await expect(
			acceptTeamInvitation(client, {
				token: 'b'.repeat(43),
				fullName: 'S',
				password: 'long enough'
			})
		).rejects.toBeInstanceOf(TeamMemberError);
	});
});

describe('signing in', () => {
	it('accepts the right password of an active teammate', async () => {
		const hash = await bcrypt.hash('correct horse', 4);
		const { client } = fakeClient([
			{ data: { id: 'm1', email: 'sam@uplift.example', password_hash: hash }, error: null }
		]);
		expect(await verifyTeammateCredentials(client, 'SAM@uplift.example', 'correct horse')).toEqual({
			memberId: 'm1',
			email: 'sam@uplift.example'
		});
	});

	it('still compares a password when nobody matches, and refuses', async () => {
		const compare = vi.spyOn(bcrypt, 'compare');
		const { client } = fakeClient([{ data: null, error: null }]);
		expect(await verifyTeammateCredentials(client, 'nobody@example.com', 'anything')).toBeNull();
		expect(compare).toHaveBeenCalledTimes(1);
		compare.mockRestore();
	});
});

describe('removing a teammate', () => {
	it('clears their password and links and revokes every open session', async () => {
		const { client, calls } = fakeClient([
			{
				data: { id: 'm1', email: 'sam@uplift.example', role: 'sales', status: 'active' },
				error: null
			},
			{ data: { id: 'm1' }, error: null },
			{ data: null, error: null }
		]);
		const removed = await removeTeamMember(client, {
			memberId: 'm1',
			removedBy: 'owner@example.com'
		});

		expect(removed.status).toBe('active');
		expect(calls[1].values).toMatchObject({ status: 'removed', password_hash: null });
		expect(calls[1].filters).toContain('eq:status=active');
		expect(calls[2]).toMatchObject({ table: 'platform_owner_sessions', op: 'update' });
		expect(calls[2].filters).toEqual(['eq:team_member_id=m1', 'is:revoked_at=null']);
	});
});

describe('password reset', () => {
	it('answers the same way for an unknown email, sending nothing', async () => {
		const { client } = fakeClient([{ data: null, error: null }]);
		await expect(
			requestTeamPasswordReset(client, {
				email: 'nobody@example.com',
				origin: 'https://app.example.com'
			})
		).resolves.toBeUndefined();
		expect(sendTransactionalEmail).not.toHaveBeenCalled();
	});

	it('emails a one-hour link to an active teammate', async () => {
		const { client, calls } = fakeClient([{ data: { email: 'sam@uplift.example' }, error: null }]);
		await requestTeamPasswordReset(client, {
			email: 'sam@uplift.example',
			origin: 'https://app.example.com'
		});
		const expiresAt = new Date(calls[0].values?.password_reset_expires_at as string).getTime();
		expect(expiresAt - Date.now()).toBeLessThanOrEqual(60 * 60 * 1000);
		expect(sendTransactionalEmail.mock.calls[0][0].textContent).toContain(
			'/jafar/reset-password?token='
		);
	});

	it('sets the new password once and signs the teammate out elsewhere', async () => {
		const { client, calls } = fakeClient([
			{ data: { id: 'm1' }, error: null },
			{ data: null, error: null }
		]);
		await completeTeamPasswordReset(client, { token: 'c'.repeat(43), password: 'brand new pass' });
		expect(calls[0].values).toMatchObject({ password_reset_token_hash: null });
		expect(calls[1]).toMatchObject({ table: 'platform_owner_sessions', op: 'update' });
	});
});
