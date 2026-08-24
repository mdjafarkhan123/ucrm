import { beforeEach, describe, expect, it, vi } from 'vitest';
import { sendTransactionalEmail } from '$lib/server/email/brevo';
import {
	acceptTeamInvitation,
	cancelTeamInvitation,
	createTeamInvitation,
	inspectTeamInvitation,
	mapTeamInvitationError,
	replaceTeamInvitationEmail,
	resendTeamInvitation,
	TeamInvitationError
} from './invitations';

vi.mock('$lib/server/email/brevo', () => ({ sendTransactionalEmail: vi.fn() }));

const mockedSendEmail = vi.mocked(sendTransactionalEmail);

function invitationClient(
	options: {
		rpcErrorAt?: string;
		rpcError?: { code?: string; message: string };
		authError?: { status?: number; message: string };
	} = {}
) {
	const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
	const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
		calls.push({ name, args });
		if (name === options.rpcErrorAt) return { data: null, error: options.rpcError };
		if (name === 'begin_team_invitation') {
			return { data: { id: 'invitation-1', invited_email: 'member@example.com' }, error: null };
		}
		if (name === 'resend_team_invitation') {
			return { data: { id: 'invitation-1', invited_email: 'member@example.com' }, error: null };
		}
		if (name === 'claim_cancelled_team_invitation_cleanup') {
			return {
				data: {
					id: 'invitation-1',
					invited_email: 'member@example.com',
					invited_user_id: 'auth-user-1',
					identity_cleanup_state: 'required',
					requested_permission_overrides: params.permissionAdjustments,
					role: 'field',
					state: 'cancelled'
				},
				error: null
			};
		}
		return { data: { id: 'invitation-1' }, error: null };
	});
	const createUser = vi.fn(async (_attributes: Record<string, unknown>) =>
		options.authError
			? { data: { user: null }, error: options.authError }
			: { data: { user: { id: 'auth-user-1' } }, error: null }
	);
	const getUserById = vi.fn(async (_userId: string) => ({
		data: {
			user: {
				id: 'auth-user-1',
				app_metadata: { team_invitation_identity_for: 'invitation-1' }
			}
		},
		error: null
	}));
	const deleteUser = vi.fn(async (_userId: string) => ({ data: {}, error: null }));

	const maybeSingle = vi.fn(async () => ({
		data: {
			id: 'invitation-1',
			invited_email: 'member@example.com',
			invited_user_id: 'auth-user-1',
			identity_cleanup_state: 'required',
			requested_permission_overrides: params.permissionAdjustments,
			role: 'field',
			state: 'invited'
		},
		error: null
	}));
	const eq = vi.fn(() => ({ eq, maybeSingle }));
	const select = vi.fn(() => ({ eq }));
	const from = vi.fn(() => ({ select }));

	return {
		rpc,
		from,
		auth: { admin: { createUser, deleteUser, getUserById } },
		__calls: calls,
		__createUser: createUser,
		__deleteUser: deleteUser,
		__getUserById: getUserById,
		__maybeSingle: maybeSingle
	};
}

const params = {
	organizationId: 'organization-1',
	invitedBy: 'owner-1',
	email: ' Member@Example.COM ',
	role: 'field',
	permissionAdjustments: [{ permission_key: 'customers.view', override_state: 'grant' as const }],
	businessName: 'Ridgeway & Sons',
	origin: 'https://app.example.com'
};

describe('createTeamInvitation', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedSendEmail.mockResolvedValue(undefined);
	});

	it('runs reserve, Auth receipt, identity attachment, then delivery in the required order', async () => {
		const client = invitationClient();

		const result = await createTeamInvitation(client as never, params);

		expect(result).toEqual({ invitationId: 'invitation-1', status: 'sent' });
		expect(client.__calls.map((call) => call.name)).toEqual([
			'begin_team_invitation',
			'mark_team_invitation_auth_attempt_started',
			'attach_team_invitation_identity',
			'record_team_invitation_delivery'
		]);
		expect(client.__calls[0].args).toMatchObject({
			target_invited_email: 'member@example.com',
			target_permission_overrides: params.permissionAdjustments
		});
		expect(client.__createUser).toHaveBeenCalledWith({
			email: 'member@example.com',
			email_confirm: true,
			app_metadata: { team_invitation_identity_for: 'invitation-1' }
		});
		expect(client.__createUser.mock.calls[0][0]).not.toHaveProperty('password');
	});

	it('keeps the raw token only in the email and attaches only its sha256 hash', async () => {
		const client = invitationClient();

		await createTeamInvitation(client as never, params);

		const email = mockedSendEmail.mock.calls[0][0];
		const token = new URL(
			email.htmlContent.match(/href="([^"]+)"/)?.[1].replaceAll('&amp;', '&') ?? ''
		).searchParams.get('token');
		const attach = client.__calls.find((call) => call.name === 'attach_team_invitation_identity');
		expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
		expect(attach?.args.target_token_hash).toMatch(/^[a-f0-9]{64}$/);
		expect(JSON.stringify(client.__calls)).not.toContain(token);
		expect(email.htmlContent).toContain('Ridgeway &amp; Sons');
	});

	it('does not call Auth when the seat reservation fails', async () => {
		const client = invitationClient({
			rpcErrorAt: 'begin_team_invitation',
			rpcError: { code: '23514', message: 'No employee seats are available for this organization.' }
		});

		await expect(createTeamInvitation(client as never, params)).rejects.toMatchObject({
			code: 'seat_limit'
		});
		expect(client.__createUser).not.toHaveBeenCalled();
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});

	it('marks the Auth attempt immediately before creating the identity', async () => {
		const client = invitationClient();
		client.__createUser.mockImplementationOnce(async (_attributes) => {
			expect(client.__calls.at(-1)?.name).toBe('mark_team_invitation_auth_attempt_started');
			return { data: { user: { id: 'auth-user-1' } }, error: null };
		});

		await createTeamInvitation(client as never, params);
	});

	it('maps an existing Auth email without exposing the provider error', async () => {
		const client = invitationClient({
			authError: {
				status: 422,
				message: 'A user with this email address has already been registered'
			}
		});

		await expect(createTeamInvitation(client as never, params)).rejects.toEqual(
			expect.objectContaining({
				code: 'email_in_use',
				message: 'That email cannot be invited. Ask the person to use another email.'
			})
		);
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});

	it('keeps a failed delivery pending and records only a safe error', async () => {
		const client = invitationClient();
		mockedSendEmail.mockRejectedValueOnce(
			new Error('Brevo 500 included private provider diagnostics and recipient data')
		);

		const result = await createTeamInvitation(client as never, params);

		expect(result).toEqual({ invitationId: 'invitation-1', status: 'delivery_failed' });
		expect(client.__calls.at(-1)).toEqual({
			name: 'record_team_invitation_delivery',
			args: {
				target_invitation_id: 'invitation-1',
				target_success: false,
				target_error: 'The invitation email could not be delivered.'
			}
		});
		expect(JSON.stringify(client.__calls)).not.toContain('private provider diagnostics');
	});

	it('does not send when identity attachment fails after Auth creation', async () => {
		const client = invitationClient({
			rpcErrorAt: 'attach_team_invitation_identity',
			rpcError: { code: '23514', message: 'Invitation cannot attach that Auth identity.' }
		});

		await expect(createTeamInvitation(client as never, params)).rejects.toBeInstanceOf(
			TeamInvitationError
		);
		expect(client.__createUser).toHaveBeenCalledOnce();
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});

	it('does not record a delivery failure when the email sent but success bookkeeping fails', async () => {
		const client = invitationClient({
			rpcErrorAt: 'record_team_invitation_delivery',
			rpcError: { code: 'P0409', message: 'The invitation changed.' }
		});

		await expect(createTeamInvitation(client as never, params)).rejects.toMatchObject({
			code: 'invitation_conflict'
		});
		expect(mockedSendEmail).toHaveBeenCalledOnce();
		expect(
			client.__calls.filter((call) => call.name === 'record_team_invitation_delivery')
		).toHaveLength(1);
	});
});

const acceptanceToken = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO12';
const acceptanceInvitationId = '00000000-0000-4000-8000-000000000091';
const acceptanceUserId = '00000000-0000-4000-8000-000000000092';

function acceptanceClient(options: {
	claim?: boolean;
	state?: string;
	expiresAt?: string;
	passwordSetAt?: string | null;
	passwordReceipt?: string;
	identityReceipt?: string;
	updateError?: boolean;
}) {
	const calls: string[] = [];
	const rpc = vi.fn(async (name: string) => {
		calls.push(name);
		if (name === 'claim_team_invitation') {
			return {
				data: [
					options.claim === false
						? { claimed: false, invitation_id: null, invited_user_id: null }
						: {
								claimed: true,
								invitation_id: acceptanceInvitationId,
								invited_user_id: acceptanceUserId
							}
				],
				error: null
			};
		}
		if (name === 'record_invitation_password_set')
			return { data: { id: acceptanceInvitationId }, error: null };
		if (name === 'finalize_team_invitation') return { data: { state: 'accepted' }, error: null };
		throw new Error(`Unexpected RPC ${name}`);
	});
	const maybeSingle = vi.fn().mockResolvedValue({
		data: {
			id: acceptanceInvitationId,
			invited_email: 'member@example.com',
			invited_user_id: acceptanceUserId,
			state: options.state ?? 'invited',
			expires_at: options.expiresAt ?? new Date(Date.now() + 60_000).toISOString(),
			password_set_at: options.passwordSetAt ?? null,
			organizations: { name: 'Ridgeway Electric' }
		},
		error: null
	});
	const getUserById = vi.fn(async () => {
		calls.push('getUserById');
		return {
			data: {
				user: {
					app_metadata: {
						team_invitation_identity_for: options.identityReceipt ?? acceptanceInvitationId,
						...(options.passwordReceipt
							? { invitation_password_set_for: options.passwordReceipt }
							: {})
					}
				}
			},
			error: null
		};
	});
	const updateUserById = vi.fn(async () => {
		calls.push('updateUserById');
		return options.updateError
			? { data: null, error: { message: 'private provider detail' } }
			: { data: { user: {} }, error: null };
	});

	return {
		rpc,
		from: () => ({ select: () => ({ eq: () => ({ maybeSingle }) }) }),
		auth: { admin: { getUserById, updateUserById } },
		__calls: calls,
		__maybeSingle: maybeSingle,
		__getUserById: getUserById,
		__updateUserById: updateUserById
	};
}

describe('public team invitation acceptance orchestration', () => {
	it('inspects a usable token without returning the full email', async () => {
		const client = acceptanceClient({});
		const result = await inspectTeamInvitation(client as never, acceptanceToken);
		expect(result).toEqual({
			valid: true,
			emailHint: 'm*****@example.com',
			companyName: 'Ridgeway Electric'
		});
		expect(client.__maybeSingle).toHaveBeenCalledOnce();
		expect(JSON.stringify(client.__maybeSingle.mock.calls)).not.toContain(acceptanceToken);
	});

	it('reports an expired token as unusable', async () => {
		const client = acceptanceClient({ expiresAt: new Date(Date.now() - 60_000).toISOString() });
		await expect(inspectTeamInvitation(client as never, acceptanceToken)).resolves.toEqual({
			valid: false
		});
	});

	it('claims, writes one merged Auth receipt, records it, and finalizes in order', async () => {
		const client = acceptanceClient({});
		await expect(
			acceptTeamInvitation(client as never, {
				token: acceptanceToken,
				email: 'MEMBER@example.com',
				password: 'longenough1'
			})
		).resolves.toEqual({ accepted: true });

		expect(client.__calls).toEqual([
			'claim_team_invitation',
			'getUserById',
			'updateUserById',
			'record_invitation_password_set',
			'finalize_team_invitation'
		]);
		expect(client.__updateUserById).toHaveBeenCalledWith(acceptanceUserId, {
			password: 'longenough1',
			app_metadata: {
				team_invitation_identity_for: acceptanceInvitationId,
				invitation_password_set_for: acceptanceInvitationId
			}
		});
	});

	it('uses an existing Auth receipt without submitting the password again', async () => {
		const client = acceptanceClient({ passwordReceipt: acceptanceInvitationId });
		await acceptTeamInvitation(client as never, {
			token: acceptanceToken,
			email: 'member@example.com',
			password: 'must-not-be-resubmitted'
		});

		expect(client.__updateUserById).not.toHaveBeenCalled();
		expect(client.__calls).toEqual([
			'claim_team_invitation',
			'getUserById',
			'record_invitation_password_set',
			'finalize_team_invitation'
		]);
	});

	it('finalizes directly when a retry finds both receipts after a lost finalizer response', async () => {
		const client = acceptanceClient({
			claim: false,
			state: 'accepting',
			passwordSetAt: new Date().toISOString(),
			passwordReceipt: acceptanceInvitationId
		});
		await expect(
			acceptTeamInvitation(client as never, {
				token: acceptanceToken,
				email: 'member@example.com',
				password: 'must-not-be-resubmitted'
			})
		).resolves.toEqual({ accepted: true });

		expect(client.__updateUserById).not.toHaveBeenCalled();
		expect(client.__calls).toEqual([
			'claim_team_invitation',
			'getUserById',
			'finalize_team_invitation'
		]);
	});

	it('does not consume or touch Auth when the recipient email is wrong', async () => {
		const client = acceptanceClient({ claim: false });
		await expect(
			acceptTeamInvitation(client as never, {
				token: acceptanceToken,
				email: 'wrong@example.com',
				password: 'longenough1'
			})
		).rejects.toMatchObject({ code: 'invalid_or_expired' });

		expect(client.__getUserById).not.toHaveBeenCalled();
		expect(client.__updateUserById).not.toHaveBeenCalled();
	});

	it('stops safely after an uncertain Auth write without exposing provider details', async () => {
		const client = acceptanceClient({ updateError: true });
		await expect(
			acceptTeamInvitation(client as never, {
				token: acceptanceToken,
				email: 'member@example.com',
				password: 'longenough1'
			})
		).rejects.toEqual(
			new TeamInvitationError(
				'service_unavailable',
				'The invitation could not be completed right now. Try again shortly.'
			)
		);
		expect(client.__calls).toEqual(['claim_team_invitation', 'getUserById', 'updateUserById']);
		expect(JSON.stringify(client.__calls)).not.toContain('private provider detail');
	});
});

describe('mapTeamInvitationError', () => {
	it('maps the global invitation email uniqueness guard', () => {
		expect(
			mapTeamInvitationError({
				code: '23505',
				message: 'duplicate key contains private@example.com'
			})
		).toMatchObject({ code: 'email_in_use' });
	});

	it('uses a stable fallback for unrestricted provider failures', () => {
		expect(mapTeamInvitationError(new Error('provider secret detail'))).toEqual(
			expect.objectContaining({
				code: 'service_unavailable',
				message: 'The invitation could not be created right now. Try again.'
			})
		);
	});
});

describe('resendTeamInvitation', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedSendEmail.mockResolvedValue(undefined);
	});

	it('checks tenant ownership and rotates the token before delivery', async () => {
		const client = invitationClient();

		const result = await resendTeamInvitation(client as never, {
			organizationId: 'organization-1',
			invitationId: 'invitation-1',
			businessName: 'Ridgeway',
			origin: 'https://app.example.com'
		});

		expect(result.status).toBe('sent');
		expect(client.__calls.map((call) => call.name)).toEqual([
			'resend_team_invitation',
			'record_team_invitation_delivery'
		]);
		expect(mockedSendEmail).toHaveBeenCalledOnce();
		const token = new URL(
			mockedSendEmail.mock.calls[0][0].textContent.match(/https:\/\/\S+/)?.[0] ?? ''
		).searchParams.get('token');
		expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
		expect(JSON.stringify(client.__calls)).not.toContain(token);
	});

	it('does not deliver when the invitation is outside the manager organization', async () => {
		const client = invitationClient();
		client.__maybeSingle.mockResolvedValueOnce({ data: null, error: null } as never);

		await expect(
			resendTeamInvitation(client as never, {
				organizationId: 'another-organization',
				invitationId: 'invitation-1',
				businessName: 'Ridgeway',
				origin: 'https://app.example.com'
			})
		).rejects.toMatchObject({ code: 'invalid_or_expired' });
		expect(client.rpc).not.toHaveBeenCalled();
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});

	it('keeps the rotated link invalidating older links when delivery fails', async () => {
		const client = invitationClient();
		mockedSendEmail.mockRejectedValueOnce(new Error('private provider failure'));

		const result = await resendTeamInvitation(client as never, {
			organizationId: 'organization-1',
			invitationId: 'invitation-1',
			businessName: 'Ridgeway',
			origin: 'https://app.example.com'
		});

		expect(result.status).toBe('delivery_failed');
		expect(client.__calls[0].name).toBe('resend_team_invitation');
		expect(client.__calls.at(-1)).toEqual({
			name: 'record_team_invitation_delivery',
			args: {
				target_invitation_id: 'invitation-1',
				target_success: false,
				target_error: 'The invitation email could not be delivered.'
			}
		});
	});
});

describe('cancelTeamInvitation', () => {
	it('checks tenant ownership before queuing cancellation cleanup', async () => {
		const client = invitationClient();

		const result = await cancelTeamInvitation(client as never, {
			organizationId: 'organization-1',
			invitationId: 'invitation-1',
			cancelledBy: 'owner-1'
		});

		expect(result).toEqual({ invitationId: 'invitation-1', status: 'cancelled' });
		expect(client.__calls).toEqual([
			{
				name: 'cancel_team_invitation',
				args: {
					target_invitation_id: 'invitation-1',
					target_cancelled_by: 'owner-1'
				}
			}
		]);
	});

	it('does no privileged work for an invitation outside the manager organization', async () => {
		const client = invitationClient();
		client.__maybeSingle.mockResolvedValueOnce({ data: null, error: null } as never);

		await expect(
			cancelTeamInvitation(client as never, {
				organizationId: 'another-organization',
				invitationId: 'invitation-1',
				cancelledBy: 'owner-1'
			})
		).rejects.toMatchObject({ code: 'invalid_or_expired' });
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('returns a stable conflict while acceptance holds the invitation', async () => {
		const client = invitationClient({
			rpcErrorAt: 'cancel_team_invitation',
			rpcError: { code: '23514', message: 'Invitation has an open acceptance lease.' }
		});

		await expect(
			cancelTeamInvitation(client as never, {
				organizationId: 'organization-1',
				invitationId: 'invitation-1',
				cancelledBy: 'owner-1'
			})
		).rejects.toMatchObject({ code: 'acceptance_in_progress' });
	});
});

describe('replaceTeamInvitationEmail', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedSendEmail.mockResolvedValue(undefined);
	});

	const replacement = {
		organizationId: 'organization-1',
		invitationId: 'invitation-1',
		replacedBy: 'owner-1',
		email: ' New.Member@Example.COM ',
		businessName: 'Ridgeway',
		origin: 'https://app.example.com'
	};

	function cancelledRow(identityCleanupState = 'required') {
		return {
			data: {
				id: 'invitation-1',
				invited_email: 'member@example.com',
				invited_user_id: identityCleanupState === 'required' ? 'auth-user-1' : null,
				identity_cleanup_state: identityCleanupState,
				requested_permission_overrides: params.permissionAdjustments,
				role: 'field',
				state: 'cancelled'
			},
			error: null
		};
	}

	it('cancels and deletes the receipt-owned identity before creating the replacement', async () => {
		const client = invitationClient();
		client.__maybeSingle
			.mockResolvedValueOnce({
				data: { ...cancelledRow().data, state: 'invited' },
				error: null
			} as never)
			.mockResolvedValueOnce({
				data: { ...cancelledRow().data, state: 'invited' },
				error: null
			} as never)
			.mockResolvedValueOnce(cancelledRow() as never);

		const result = await replaceTeamInvitationEmail(client as never, replacement);

		expect(result).toEqual({ invitationId: 'invitation-1', status: 'sent' });
		expect(client.__getUserById).toHaveBeenCalledWith('auth-user-1');
		expect(client.__deleteUser).toHaveBeenCalledWith('auth-user-1');
		expect(client.__calls.map((call) => call.name)).toEqual([
			'cancel_team_invitation',
			'claim_cancelled_team_invitation_cleanup',
			'prepare_team_invitation_identity_cleanup',
			'settle_team_invitation_identity_cleanup',
			'begin_team_invitation',
			'mark_team_invitation_auth_attempt_started',
			'attach_team_invitation_identity',
			'record_team_invitation_delivery'
		]);
		expect(client.__calls[4].args).toMatchObject({
			target_invited_email: 'new.member@example.com',
			target_role: 'field',
			target_permission_overrides: params.permissionAdjustments
		});
	});

	it('retries creation from an already-cleaned cancelled invitation', async () => {
		const client = invitationClient();
		client.__maybeSingle.mockResolvedValueOnce(cancelledRow('done') as never);

		await replaceTeamInvitationEmail(client as never, replacement);

		expect(client.__calls[0].name).toBe('begin_team_invitation');
		expect(client.__deleteUser).not.toHaveBeenCalled();
	});

	it('does not delete an Auth identity whose receipt belongs to another invitation', async () => {
		const client = invitationClient();
		client.__maybeSingle.mockResolvedValueOnce(cancelledRow() as never);
		client.__getUserById.mockResolvedValueOnce({
			data: {
				user: {
					id: 'auth-user-1',
					app_metadata: { team_invitation_identity_for: 'another-invitation' }
				}
			},
			error: null
		} as never);

		await expect(replaceTeamInvitationEmail(client as never, replacement)).rejects.toMatchObject({
			code: 'service_unavailable'
		});
		expect(client.__deleteUser).not.toHaveBeenCalled();
		expect(client.__calls.at(-1)?.name).toBe('release_team_invitation_reconciliation');
	});

	it('stops before cancellation when the invitation belongs to another organization', async () => {
		const client = invitationClient();
		client.__maybeSingle.mockResolvedValueOnce({ data: null, error: null } as never);

		await expect(replaceTeamInvitationEmail(client as never, replacement)).rejects.toMatchObject({
			code: 'invalid_or_expired'
		});
		expect(client.rpc).not.toHaveBeenCalled();
		expect(client.__deleteUser).not.toHaveBeenCalled();
	});

	it('releases the cleanup lease when Auth deletion is uncertain', async () => {
		const client = invitationClient();
		client.__maybeSingle.mockResolvedValueOnce(cancelledRow() as never);
		client.__deleteUser.mockResolvedValueOnce({
			data: {},
			error: { message: 'private provider detail' }
		} as never);

		await expect(replaceTeamInvitationEmail(client as never, replacement)).rejects.toMatchObject({
			code: 'service_unavailable'
		});
		expect(client.__calls.map((call) => call.name)).toEqual([
			'claim_cancelled_team_invitation_cleanup',
			'prepare_team_invitation_identity_cleanup',
			'release_team_invitation_reconciliation'
		]);
		expect(client.__createUser).not.toHaveBeenCalled();
		expect(JSON.stringify(client.__calls)).not.toContain('private provider detail');
	});

	it('keeps the old invitation cancelled when replacement creation fails', async () => {
		const client = invitationClient({
			rpcErrorAt: 'begin_team_invitation',
			rpcError: { code: '23505', message: 'duplicate key' }
		});
		client.__maybeSingle.mockResolvedValueOnce(cancelledRow('done') as never);

		await expect(replaceTeamInvitationEmail(client as never, replacement)).rejects.toMatchObject({
			code: 'email_in_use'
		});
		expect(client.__calls.map((call) => call.name)).toEqual(['begin_team_invitation']);
	});
});
