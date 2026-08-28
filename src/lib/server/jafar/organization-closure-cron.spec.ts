import { beforeEach, describe, expect, it, vi } from 'vitest';
import { retryReceiptCleanup, runOrganizationClosureCron } from './organization-closure-cron';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { recordOperationOutcome } from '$lib/server/events/outbox';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import {
	BrevoManagementError,
	deleteBrevoDomainById,
	deleteBrevoSender
} from '$lib/server/communications/brevo';

vi.mock('$lib/server/events/dispatcher', () => ({ enqueueEmailDelivery: vi.fn() }));
vi.mock('$lib/server/events/outbox', () => ({ recordOperationOutcome: vi.fn() }));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert: vi.fn() }));
vi.mock('$lib/server/communications/brevo', () => {
	class MockBrevoManagementError extends Error {
		constructor(
			message: string,
			public readonly status: number | null,
			public readonly code: string
		) {
			super(message);
			this.name = 'BrevoManagementError';
		}
	}
	return {
		BrevoManagementError: MockBrevoManagementError,
		deleteBrevoDomainById: vi.fn(),
		deleteBrevoSender: vi.fn()
	};
});

const mockedEnqueueEmail = vi.mocked(enqueueEmailDelivery);
const mockedRecordOutcome = vi.mocked(recordOperationOutcome);
const mockedRaiseAlert = vi.mocked(raiseOwnerAlert);
const mockedDeleteDomain = vi.mocked(deleteBrevoDomainById);
const mockedDeleteSender = vi.mocked(deleteBrevoSender);

const PUBLISHED_TEMPLATE = {
	subject_published: 'Reminder: {{business_name}}',
	body_published: '<p>{{business_name}}</p>'
};

type ClosureRecord = { id: string; organization_id: string; deadline_at: string };
type ProviderResource = { kind: 'domain' | 'sender'; provider_id: string };
type UnfinishedReceipt = { operation_id: string; pending_auth_user_ids: string[] };
type UnfinishedProviderReceipt = {
	operation_id: string;
	pending_provider_resources: ProviderResource[];
};

const EMPTY_RESULT = {
	noticesSent: 0,
	noticesSkipped: 0,
	purgesCompleted: 0,
	purgesFailed: 0,
	authCleanupsCompleted: 0,
	authCleanupsFailed: 0,
	providerCleanupsCompleted: 0,
	providerCleanupsFailed: 0
};

function daysFromNow(days: number) {
	return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
}

function clientWith(config: {
	closureRecords?: ClosureRecord[];
	existingNotices?: Set<string>;
	organizations?: Record<string, { name: string }>;
	ownerMembers?: Record<string, { user_id: string }>;
	userEmails?: Record<string, string>;
	templates?: Record<string, { subject_published: string | null; body_published: string | null }>;
	unfinishedReceipts?: UnfinishedReceipt[];
	unfinishedProviderReceipts?: UnfinishedProviderReceipt[];
	receiptComponents?: Record<string, Record<string, string>>;
	purgeRpcResult?: { data: unknown; error: { message: string } | null };
	deleteUserResult?: (userId: string) => { error: { message: string } | null };
}) {
	const closureNoticeInserts: unknown[] = [];
	const receiptUpdates: Array<{ payload: unknown; operationId: string }> = [];
	const deleteUserCalls: string[] = [];

	const rpc = vi.fn((fnName: string) => {
		if (fnName === 'apply_organization_purge') {
			return Promise.resolve(
				config.purgeRpcResult ?? {
					data: { applied: true, operation_id: 'op-default', member_user_ids: [] },
					error: null
				}
			);
		}
		throw new Error(`unexpected rpc ${fnName}`);
	});

	const deleteUser = vi.fn(async (userId: string) => {
		deleteUserCalls.push(userId);
		return config.deleteUserResult ? config.deleteUserResult(userId) : { error: null };
	});
	const getUserById = vi.fn(async (userId: string) => ({
		data: { user: config.userEmails?.[userId] ? { email: config.userEmails[userId] } : null },
		error: null
	}));

	const client = {
		from: (table: string) => {
			if (table === 'organization_closure_records') {
				return {
					select: () => ({
						eq: async () => ({ data: config.closureRecords ?? [], error: null })
					})
				};
			}
			if (table === 'organization_closure_notices') {
				return {
					select: () => ({
						eq: (_col1: string, val1: string) => ({
							eq: (_col2: string, val2: string) => ({
								maybeSingle: async () => {
									const key = `${val1}:${val2}`;
									return {
										data: config.existingNotices?.has(key) ? { id: 'existing' } : null,
										error: null
									};
								}
							})
						})
					}),
					insert: (payload: unknown) => {
						closureNoticeInserts.push(payload);
						return Promise.resolve({ error: null });
					}
				};
			}
			if (table === 'organizations') {
				return {
					select: () => ({
						eq: (_col: string, id: string) => ({
							maybeSingle: async () => ({ data: config.organizations?.[id] ?? null, error: null })
						})
					})
				};
			}
			if (table === 'organization_members') {
				return {
					select: () => ({
						eq: (_col1: string, orgId: string) => ({
							eq: () => ({
								maybeSingle: async () => ({
									data: config.ownerMembers?.[orgId] ?? null,
									error: null
								})
							})
						})
					})
				};
			}
			if (table === 'platform_message_templates') {
				return {
					select: () => ({
						eq: (_col: string, key: string) => ({
							maybeSingle: async () => ({ data: config.templates?.[key] ?? null, error: null })
						})
					})
				};
			}
			if (table === 'organization_deletion_receipts') {
				return {
					select: () => ({
						eq: (_col: string, operationId: string) => ({
							maybeSingle: async () => ({
								data: { component_results: config.receiptComponents?.[operationId] ?? {} },
								error: null
							})
						}),
						not: async (column: string) => ({
							data:
								column === 'pending_provider_resources'
									? (config.unfinishedProviderReceipts ?? [])
									: (config.unfinishedReceipts ?? []),
							error: null
						})
					}),
					update: (payload: unknown) => ({
						eq: (_col: string, operationId: string) => {
							receiptUpdates.push({ payload, operationId });
							return Promise.resolve({ error: null });
						}
					})
				};
			}
			throw new Error(`unexpected table ${table}`);
		},
		auth: { admin: { getUserById, deleteUser } },
		rpc
	};

	return {
		client: client as never,
		__closureNoticeInserts: closureNoticeInserts,
		__receiptUpdates: receiptUpdates,
		__deleteUserCalls: deleteUserCalls,
		__rpc: rpc
	};
}

describe('runOrganizationClosureCron', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedEnqueueEmail.mockResolvedValue('delivery-1');
		mockedRaiseAlert.mockResolvedValue('notification-1');
		mockedDeleteDomain.mockResolvedValue(undefined);
		mockedDeleteSender.mockResolvedValue(undefined);
	});

	it('sends a due 14-day reminder and claims it, but not the 3-day reminder yet', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(10) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			ownerMembers: { 'org-1': { user_id: 'user-1' } },
			userEmails: { 'user-1': 'owner@ridgeway.example' },
			templates: { organization_closure_fourteen_day_reminder: PUBLISHED_TEMPLATE }
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toEqual({ ...EMPTY_RESULT, noticesSent: 1 });
		expect(mockedEnqueueEmail).toHaveBeenCalledTimes(1);
		expect(mockedEnqueueEmail).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({
				recipientEmail: 'owner@ridgeway.example',
				idempotencyKey: 'closure:closure-1:fourteen_day_reminder'
			})
		);
		expect(harness.__closureNoticeInserts).toEqual([
			{
				closure_record_id: 'closure-1',
				notice_kind: 'fourteen_day_reminder',
				outbox_delivery_id: 'delivery-1'
			}
		]);
	});

	it('sends both the 14-day and 3-day reminders once inside the 3-day window', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(2) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			ownerMembers: { 'org-1': { user_id: 'user-1' } },
			userEmails: { 'user-1': 'owner@ridgeway.example' },
			templates: {
				organization_closure_fourteen_day_reminder: PUBLISHED_TEMPLATE,
				organization_closure_three_day_reminder: PUBLISHED_TEMPLATE
			}
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result.noticesSent).toBe(2);
		expect(mockedEnqueueEmail).toHaveBeenCalledTimes(2);
	});

	it('skips a notice already claimed by a prior run instead of sending it again', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(10) }],
			existingNotices: new Set(['closure-1:fourteen_day_reminder']),
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			ownerMembers: { 'org-1': { user_id: 'user-1' } },
			userEmails: { 'user-1': 'owner@ridgeway.example' },
			templates: { organization_closure_fourteen_day_reminder: PUBLISHED_TEMPLATE }
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ noticesSent: 0, noticesSkipped: 1 });
		expect(mockedEnqueueEmail).not.toHaveBeenCalled();
	});

	it('skips a due notice without sending or claiming it when the template has not been published yet', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(10) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			ownerMembers: { 'org-1': { user_id: 'user-1' } },
			userEmails: { 'user-1': 'owner@ridgeway.example' }
			// no templates configured
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ noticesSent: 0, noticesSkipped: 1 });
		expect(mockedEnqueueEmail).not.toHaveBeenCalled();
		expect(harness.__closureNoticeInserts).toHaveLength(0);
	});

	it('skips a due notice when the organization has no resolvable owner email', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(10) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			// no ownerMembers entry for org-1
			templates: { organization_closure_fourteen_day_reminder: PUBLISHED_TEMPLATE }
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ noticesSent: 0, noticesSkipped: 1 });
		expect(mockedEnqueueEmail).not.toHaveBeenCalled();
	});

	it('purges an organization past its deadline and deletes its members from Auth', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(-1) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			ownerMembers: { 'org-1': { user_id: 'user-1' } },
			userEmails: { 'user-1': 'owner@ridgeway.example' },
			purgeRpcResult: {
				data: { applied: true, operation_id: 'op-1', member_user_ids: ['user-1', 'user-2'] },
				error: null
			}
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ purgesCompleted: 1, purgesFailed: 0 });
		expect(harness.__rpc).toHaveBeenCalledWith(
			'apply_organization_purge',
			expect.objectContaining({ target_organization_id: 'org-1', purge_trigger_kind: 'scheduled' })
		);
		expect(harness.__deleteUserCalls).toEqual(['user-1', 'user-2']);
		expect(harness.__receiptUpdates).toContainEqual(
			expect.objectContaining({
				operationId: 'op-1',
				payload: expect.objectContaining({
					component_results: expect.objectContaining({ auth_users: 'succeeded' }),
					pending_auth_user_ids: null
				})
			})
		);
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({ operationType: 'organization_purge', success: true })
		);
	});

	it('records a failure and raises an urgent alert when the purge RPC itself fails', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(-1) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			purgeRpcResult: { data: null, error: { message: 'no open closure window' } }
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ purgesCompleted: 0, purgesFailed: 1 });
		expect(harness.__deleteUserCalls).toEqual([]);
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({
				operationType: 'organization_purge',
				success: false,
				error: 'no open closure window'
			})
		);
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({ kind: 'organization_purge_failed', severity: 'urgent' })
		);
	});

	it('finishes an Auth cleanup left over from a previous run, once the organization is already gone', async () => {
		const harness = clientWith({
			closureRecords: [],
			unfinishedReceipts: [{ operation_id: 'op-2', pending_auth_user_ids: ['user-3'] }],
			receiptComponents: { 'op-2': { organization_data: 'succeeded', auth_users: 'pending' } }
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ authCleanupsCompleted: 1, authCleanupsFailed: 0 });
		expect(harness.__deleteUserCalls).toEqual(['user-3']);
		expect(harness.__receiptUpdates).toContainEqual(
			expect.objectContaining({
				operationId: 'op-2',
				payload: expect.objectContaining({
					component_results: { organization_data: 'succeeded', auth_users: 'succeeded' },
					pending_auth_user_ids: null
				})
			})
		);
	});

	it('treats an already-gone Auth user as success rather than a failure to retry forever', async () => {
		const harness = clientWith({
			closureRecords: [],
			unfinishedReceipts: [{ operation_id: 'op-2', pending_auth_user_ids: ['user-3'] }],
			deleteUserResult: () => ({ error: { message: 'User not found' } })
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ authCleanupsCompleted: 1, authCleanupsFailed: 0 });
		expect(mockedRaiseAlert).not.toHaveBeenCalled();
	});

	it('keeps the pending ids and raises an alert when Auth cleanup genuinely fails', async () => {
		const harness = clientWith({
			closureRecords: [],
			unfinishedReceipts: [{ operation_id: 'op-2', pending_auth_user_ids: ['user-3'] }],
			deleteUserResult: () => ({ error: { message: 'Network error' } })
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ authCleanupsCompleted: 0, authCleanupsFailed: 1 });
		expect(harness.__receiptUpdates).toContainEqual(
			expect.objectContaining({
				operationId: 'op-2',
				payload: expect.objectContaining({ pending_auth_user_ids: ['user-3'] })
			})
		);
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({ kind: 'organization_purge_failed', severity: 'urgent' })
		);
	});

	it('cleans up the Brevo provider resources returned by a successful purge', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(-1) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			purgeRpcResult: {
				data: {
					applied: true,
					operation_id: 'op-1',
					member_user_ids: [],
					provider_resources: [
						{ kind: 'domain', provider_id: 'brevo-domain-abc' },
						{ kind: 'sender', provider_id: '42' }
					]
				},
				error: null
			}
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ purgesCompleted: 1, purgesFailed: 0 });
		expect(mockedDeleteDomain).toHaveBeenCalledWith('brevo-domain-abc');
		expect(mockedDeleteSender).toHaveBeenCalledWith(42);
		expect(harness.__receiptUpdates).toContainEqual(
			expect.objectContaining({
				operationId: 'op-1',
				payload: expect.objectContaining({
					component_results: expect.objectContaining({ provider_resources: 'succeeded' }),
					pending_provider_resources: null,
					status: 'completed'
				})
			})
		);
	});

	it('leaves the purge complete only after both external legs finish', async () => {
		const harness = clientWith({
			closureRecords: [{ id: 'closure-1', organization_id: 'org-1', deadline_at: daysFromNow(-1) }],
			organizations: { 'org-1': { name: 'Ridgeway Electric' } },
			ownerMembers: { 'org-1': { user_id: 'user-1' } },
			// The receipt already carries the provider leg as pending, so the Auth helper -- which runs
			// first -- must not mark the whole receipt completed while provider cleanup is outstanding.
			receiptComponents: {
				'op-1': {
					organization_data: 'succeeded',
					auth_users: 'pending',
					provider_resources: 'pending'
				}
			},
			purgeRpcResult: {
				data: {
					applied: true,
					operation_id: 'op-1',
					member_user_ids: ['user-1'],
					provider_resources: [{ kind: 'sender', provider_id: '42' }]
				},
				error: null
			}
		});

		await runOrganizationClosureCron(harness.client);

		const authUpdate = harness.__receiptUpdates.find(
			(update) =>
				update.operationId === 'op-1' &&
				(update.payload as { component_results?: Record<string, string> }).component_results
					?.auth_users === 'succeeded'
		);
		expect((authUpdate?.payload as { status?: string }).status).toBe('in_progress');
		expect((authUpdate?.payload as { completed_at?: string | null }).completed_at).toBeNull();
	});

	it('keeps the provider anchor and raises an alert when Brevo cleanup genuinely fails', async () => {
		mockedDeleteSender.mockRejectedValueOnce(
			new BrevoManagementError('Brevo down', 503, 'brevo_http_503')
		);
		const resources: ProviderResource[] = [{ kind: 'sender', provider_id: '42' }];
		const harness = clientWith({
			closureRecords: [],
			unfinishedProviderReceipts: [{ operation_id: 'op-3', pending_provider_resources: resources }],
			receiptComponents: {
				'op-3': { organization_data: 'succeeded', provider_resources: 'pending' }
			}
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ providerCleanupsCompleted: 0, providerCleanupsFailed: 1 });
		expect(harness.__receiptUpdates).toContainEqual(
			expect.objectContaining({
				operationId: 'op-3',
				payload: expect.objectContaining({
					component_results: expect.objectContaining({ provider_resources: 'failed' }),
					pending_provider_resources: resources,
					status: 'failed_partial',
					completed_at: null
				})
			})
		);
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({ kind: 'organization_purge_failed', severity: 'urgent' })
		);
	});

	it('treats an already-gone Brevo resource (404) as success rather than retrying forever', async () => {
		mockedDeleteSender.mockRejectedValueOnce(
			new BrevoManagementError('Not found', 404, 'brevo_http_404')
		);
		const harness = clientWith({
			closureRecords: [],
			unfinishedProviderReceipts: [
				{
					operation_id: 'op-3',
					pending_provider_resources: [{ kind: 'sender', provider_id: '42' }]
				}
			],
			receiptComponents: {
				'op-3': { organization_data: 'succeeded', provider_resources: 'pending' }
			}
		});

		const result = await runOrganizationClosureCron(harness.client);

		expect(result).toMatchObject({ providerCleanupsCompleted: 1, providerCleanupsFailed: 0 });
		expect(mockedRaiseAlert).not.toHaveBeenCalled();
		expect(harness.__receiptUpdates).toContainEqual(
			expect.objectContaining({
				operationId: 'op-3',
				payload: expect.objectContaining({
					component_results: expect.objectContaining({ provider_resources: 'succeeded' }),
					pending_provider_resources: null,
					status: 'completed'
				})
			})
		);
	});
});

function receiptHarness(receipt: {
	operation_id: string;
	retry_count: number;
	pending_auth_user_ids?: string[] | null;
	pending_provider_resources?: ProviderResource[] | null;
	component_results?: Record<string, string>;
	deleteUserResult?: (userId: string) => { error: { message: string } | null };
}) {
	const row = {
		operation_id: receipt.operation_id,
		retry_count: receipt.retry_count,
		pending_auth_user_ids: receipt.pending_auth_user_ids ?? null,
		pending_provider_resources: receipt.pending_provider_resources ?? null,
		component_results: receipt.component_results ?? {}
	};
	const updates: unknown[] = [];
	const deleteUserCalls: string[] = [];

	const deleteUser = vi.fn(async (userId: string) => {
		deleteUserCalls.push(userId);
		return receipt.deleteUserResult ? receipt.deleteUserResult(userId) : { error: null };
	});

	const client = {
		from: (table: string) => {
			if (table !== 'organization_deletion_receipts') throw new Error(`unexpected table ${table}`);
			return {
				select: (cols: string) => ({
					eq: () => ({
						maybeSingle: async () =>
							cols.includes('retry_count')
								? {
										data: {
											operation_id: row.operation_id,
											retry_count: row.retry_count,
											pending_auth_user_ids: row.pending_auth_user_ids,
											pending_provider_resources: row.pending_provider_resources
										},
										error: null
									}
								: { data: { component_results: row.component_results }, error: null }
					})
				}),
				update: (payload: Record<string, unknown>) => ({
					eq: () => {
						updates.push(payload);
						Object.assign(row, payload);
						return Promise.resolve({ error: null });
					}
				})
			};
		},
		auth: { admin: { deleteUser } }
	};

	return { client: client as never, updates, deleteUserCalls };
}

describe('retryReceiptCleanup', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRaiseAlert.mockResolvedValue('notification-1');
		mockedDeleteDomain.mockResolvedValue(undefined);
		mockedDeleteSender.mockResolvedValue(undefined);
	});

	it('reports not found without bumping retry_count when the receipt is gone', async () => {
		const updates: unknown[] = [];
		const client = {
			from: () => ({
				select: () => ({
					eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) })
				}),
				update: (payload: unknown) => ({
					eq: () => {
						updates.push(payload);
						return Promise.resolve({ error: null });
					}
				})
			})
		} as never;

		const result = await retryReceiptCleanup(client, 'op-missing');

		expect(result).toEqual({ found: false, authOk: true, providerOk: true });
		expect(updates).toHaveLength(0);
	});

	it('retries only the still-pending auth leg and skips the already-cleared provider leg', async () => {
		const harness = receiptHarness({
			operation_id: 'op-1',
			retry_count: 1,
			pending_auth_user_ids: ['user-1'],
			pending_provider_resources: null
		});

		const result = await retryReceiptCleanup(harness.client, 'op-1');

		expect(result).toEqual({ found: true, authOk: true, providerOk: true });
		expect(harness.deleteUserCalls).toEqual(['user-1']);
		expect(mockedDeleteDomain).not.toHaveBeenCalled();
		expect(mockedDeleteSender).not.toHaveBeenCalled();
		expect(harness.updates).toContainEqual({ retry_count: 2 });
	});

	it('retries both legs when both are still pending and reports full resolution', async () => {
		const harness = receiptHarness({
			operation_id: 'op-1',
			retry_count: 0,
			pending_auth_user_ids: ['user-1'],
			pending_provider_resources: [{ kind: 'sender', provider_id: '42' }]
		});

		const result = await retryReceiptCleanup(harness.client, 'op-1');

		expect(result).toEqual({ found: true, authOk: true, providerOk: true });
		expect(harness.deleteUserCalls).toEqual(['user-1']);
		expect(mockedDeleteSender).toHaveBeenCalledWith(42);
	});

	it('keeps reporting unresolved when a leg fails again', async () => {
		const harness = receiptHarness({
			operation_id: 'op-1',
			retry_count: 0,
			pending_auth_user_ids: ['user-1'],
			deleteUserResult: () => ({ error: { message: 'Network error' } })
		});

		const result = await retryReceiptCleanup(harness.client, 'op-1');

		expect(result).toEqual({ found: true, authOk: false, providerOk: true });
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({ kind: 'organization_purge_failed', severity: 'urgent' })
		);
	});
});
