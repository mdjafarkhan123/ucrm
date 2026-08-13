import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { issueSetupLink } from '$lib/server/jafar/setup-link';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/jafar/setup-link', () => ({ issueSetupLink: vi.fn() }));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedIssueSetupLink = vi.mocked(issueSetupLink);
const mockedCheckRateLimit = vi.mocked(checkRateLimit);
const mockedRaiseAlert = vi.mocked(raiseOwnerAlert);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/provision', {
			method: 'POST'
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/provision'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

type ClaimRow = {
	claim_status: 'claimed' | 'already_succeeded' | 'in_progress';
	organization_id: string | null;
	administrator_user_id: string | null;
	attempt_count: number;
};

type ClientOptions = {
	applicationStage: string | null;
	existingProvision?: { status: string; organization_id: string | null } | null;
	claimResult?: { data: ClaimRow[] | null; error: { message: string } | null };
	existingSlugs?: string[];
	createUserResult?: { data: { user: { id: string } | null }; error: { message: string } | null };
	deleteUserResult?: { error: { message: string } | null };
	rpcResult?: { error: { message: string } | null };
};

const defaultClaim: ClaimRow = {
	claim_status: 'claimed',
	organization_id: null,
	administrator_user_id: null,
	attempt_count: 1
};

function clientWith(options: ClientOptions) {
	const provisionUpdateCalls: unknown[] = [];
	const provisionUpdate = vi.fn((payload: unknown) => {
		provisionUpdateCalls.push(payload);
		return { eq: vi.fn().mockResolvedValue({ error: null }) };
	});
	const applicationUpdateCalls: unknown[] = [];
	const applicationUpdate = vi.fn((payload: unknown) => {
		applicationUpdateCalls.push(payload);
		return { eq: vi.fn().mockResolvedValue({ error: null }) };
	});
	const createUser = vi
		.fn()
		.mockResolvedValue(
			options.createUserResult ?? { data: { user: { id: 'admin-user-id' } }, error: null }
		);
	const deleteUser = vi.fn().mockResolvedValue(options.deleteUserResult ?? { error: null });
	const auditEventInsert = vi.fn().mockResolvedValue({ error: null });

	const rpc = vi.fn((fnName: string) => {
		if (fnName === 'claim_onboarding_application_provision') {
			return Promise.resolve(
				options.claimResult ?? { data: [defaultClaim], error: null }
			);
		}
		if (fnName === 'provision_organization_from_application') {
			return Promise.resolve({ data: null, error: (options.rpcResult ?? { error: null }).error });
		}
		throw new Error(`unexpected rpc ${fnName}`);
	});

	// Generic chainable stub for platform_operation_attempts: eq()/select() return itself so any
	// number of filters can precede a terminal call, and both terminal shapes recordOperationOutcome
	// uses (maybeSingle for the lookup, neq for the plain update) resolve successfully.
	function operationAttemptBuilder(): Record<string, unknown> {
		const builder: Record<string, unknown> = {};
		builder.select = () => builder;
		builder.eq = () => builder;
		builder.maybeSingle = async () => ({ data: null, error: null });
		builder.neq = async () => ({ error: null });
		return builder;
	}

	return {
		from: (table: string) => {
			if (table === 'platform_onboarding_applications') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () =>
								options.applicationStage === null
									? { data: null, error: null }
									: {
											data: {
												stage: options.applicationStage,
												business_name: 'Ridgeway Electric',
												main_contact_name: 'Jordan Diaz',
												main_contact_email: 'jordan@ridgeway.example',
												initial_administrator_name: null,
												initial_administrator_email: null
											},
											error: null
										}
						})
					}),
					update: applicationUpdate
				};
			}
			if (table === 'platform_onboarding_application_provisions') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({ data: options.existingProvision ?? null, error: null })
						})
					}),
					update: provisionUpdate
				};
			}
			if (table === 'organizations') {
				return {
					select: () => ({
						ilike: async () => ({
							data: (options.existingSlugs ?? []).map((slug) => ({ slug })),
							error: null
						})
					})
				};
			}
			if (table === 'platform_operation_attempts') {
				return {
					select: () => operationAttemptBuilder(),
					insert: () => ({
						select: () => ({
							single: async () => ({ data: { correlation_id: 'corr-1' }, error: null })
						})
					}),
					update: () => operationAttemptBuilder()
				};
			}
			if (table === 'platform_owner_audit_events') {
				return { insert: auditEventInsert };
			}
			throw new Error(`unexpected table ${table}`);
		},
		auth: { admin: { createUser, deleteUser } },
		rpc,
		__provisionUpdateCalls: provisionUpdateCalls,
		__applicationUpdateCalls: applicationUpdateCalls,
		__createUser: createUser,
		__deleteUser: deleteUser,
		__rpc: rpc,
		__auditEventInsert: auditEventInsert
	};
}

describe('platform owner prospect provisioning API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedIssueSetupLink.mockResolvedValue({ sent: true });
		mockedCheckRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 429 once the per-owner-session rate limit is exceeded', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ applicationStage: 'payment_confirmed' }) as never);
		mockedCheckRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });

		const response = await POST(event(prospectId));
		expect(response.status).toBe(429);
		expect(response.headers.get('Retry-After')).toBe('30');
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ applicationStage: null }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects provisioning when the application is not payment_confirmed or needs_attention', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ applicationStage: 'new' }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('replays the existing organization when already successfully provisioned, even if the stage moved on', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({
			applicationStage: 'account_created',
			existingProvision: { status: 'succeeded', organization_id: 'org-1' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ organization_id: 'org-1' });
		expect(client.__rpc).not.toHaveBeenCalled();
		expect(client.__createUser).not.toHaveBeenCalled();
	});

	it('rejects a concurrent request while another claim is in progress', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({
			applicationStage: 'payment_confirmed',
			claimResult: {
				data: [
					{
						claim_status: 'in_progress',
						organization_id: null,
						administrator_user_id: null,
						attempt_count: 1
					}
				],
				error: null
			}
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
		expect(client.__createUser).not.toHaveBeenCalled();
	});

	it('provisions the organization on the happy path', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({ applicationStage: 'payment_confirmed' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(201);
		const body = (await response.json()) as {
			organization_id: string;
			setup_email_sent: boolean;
		};
		expect(body.organization_id).toEqual(expect.any(String));
		expect(body.setup_email_sent).toBe(true);

		expect(mockedIssueSetupLink).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				applicationId: prospectId,
				administratorUserId: 'admin-user-id',
				intendedEmail: 'jordan@ridgeway.example',
				businessName: 'Ridgeway Electric'
			})
		);

		expect(client.__createUser).toHaveBeenCalledWith(
			expect.objectContaining({
				email: 'jordan@ridgeway.example',
				email_confirm: true,
				app_metadata: { organization_id: body.organization_id, role: 'owner' }
			})
		);
		expect(client.__createUser.mock.calls[0][0]).not.toHaveProperty('password');

		// The login account id is persisted before the organization RPC runs.
		expect(client.__provisionUpdateCalls).toContainEqual({ administrator_user_id: 'admin-user-id' });

		expect(client.__rpc).toHaveBeenCalledWith(
			'provision_organization_from_application',
			expect.objectContaining({
				target_application_id: prospectId,
				target_organization_id: body.organization_id,
				target_organization_name: 'Ridgeway Electric',
				target_administrator_user_id: 'admin-user-id'
			})
		);
		expect(client.__provisionUpdateCalls).toContainEqual(
			expect.objectContaining({ status: 'succeeded', organization_id: body.organization_id })
		);
		expect(client.__deleteUser).not.toHaveBeenCalled();
	});

	it('rejects provisioning when the administrator email is already registered', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({
			applicationStage: 'payment_confirmed',
			createUserResult: {
				data: { user: null },
				error: { message: 'A user with this email address has already been registered' }
			}
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
		expect(client.__rpc).toHaveBeenCalledTimes(1); // only the claim call, never the org RPC
		expect(client.__provisionUpdateCalls).toContainEqual(
			expect.objectContaining({ status: 'failed' })
		);
	});

	it('resumes with an earlier interrupted attempt\'s login account instead of creating a new one', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({
			applicationStage: 'needs_attention',
			claimResult: {
				data: [
					{
						claim_status: 'claimed',
						organization_id: null,
						administrator_user_id: 'earlier-admin-user-id',
						attempt_count: 2
					}
				],
				error: null
			}
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(201);
		expect(client.__createUser).not.toHaveBeenCalled();
		expect(client.__rpc).toHaveBeenCalledWith(
			'provision_organization_from_application',
			expect.objectContaining({ target_administrator_user_id: 'earlier-admin-user-id' })
		);
	});

	it('compensates the administrator account and marks the application needs_attention when provisioning fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({
			applicationStage: 'payment_confirmed',
			rpcResult: { error: { message: 'Payment must be confirmed before provisioning.' } }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(client.__deleteUser).toHaveBeenCalledWith('admin-user-id');
		expect(client.__applicationUpdateCalls).toContainEqual(
			expect.objectContaining({ stage: 'needs_attention' })
		);
		// Deletion succeeded, so the stored account id is cleared -- a future retry must create a
		// fresh login account rather than reusing one that no longer exists.
		expect(client.__provisionUpdateCalls).toContainEqual(
			expect.objectContaining({ status: 'failed', administrator_user_id: null })
		);
		// A failed provisioning is one of the few events Jafar is emailed about, not just shown
		// in the panel -- a paid prospect is stuck until someone acts.
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				kind: 'onboarding_application_provisioning_failed',
				severity: 'urgent',
				target: { targetKind: 'onboarding_application', targetId: prospectId }
			})
		);
	});

	it('still returns the failure response when the provisioning alert itself cannot be raised', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedRaiseAlert.mockRejectedValue(new Error('notifications table unreachable'));
		const client = clientWith({
			applicationStage: 'payment_confirmed',
			rpcResult: { error: { message: 'Payment must be confirmed before provisioning.' } }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(client.__applicationUpdateCalls).toContainEqual(
			expect.objectContaining({ stage: 'needs_attention' })
		);
	});

	it('keeps the stored administrator id when compensating deletion itself fails, so a retry can still resume', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({
			applicationStage: 'payment_confirmed',
			rpcResult: { error: { message: 'Payment must be confirmed before provisioning.' } },
			deleteUserResult: { error: { message: 'Network error' } }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(client.__provisionUpdateCalls).toContainEqual(
			expect.objectContaining({ status: 'failed', administrator_user_id: 'admin-user-id' })
		);
	});
});
