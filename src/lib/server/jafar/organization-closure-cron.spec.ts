import { beforeEach, describe, expect, it, vi } from 'vitest';
import { runOrganizationClosureCron } from './organization-closure-cron';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { recordOperationOutcome } from '$lib/server/events/outbox';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';

vi.mock('$lib/server/events/dispatcher', () => ({ enqueueEmailDelivery: vi.fn() }));
vi.mock('$lib/server/events/outbox', () => ({ recordOperationOutcome: vi.fn() }));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert: vi.fn() }));

const mockedEnqueueEmail = vi.mocked(enqueueEmailDelivery);
const mockedRecordOutcome = vi.mocked(recordOperationOutcome);
const mockedRaiseAlert = vi.mocked(raiseOwnerAlert);

const PUBLISHED_TEMPLATE = { subject_published: 'Reminder: {{business_name}}', body_published: '<p>{{business_name}}</p>' };

type ClosureRecord = { id: string; organization_id: string; deadline_at: string };
type UnfinishedReceipt = { operation_id: string; pending_auth_user_ids: string[] };

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
									return { data: config.existingNotices?.has(key) ? { id: 'existing' } : null, error: null };
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
								maybeSingle: async () => ({ data: config.ownerMembers?.[orgId] ?? null, error: null })
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
						not: async () => ({ data: config.unfinishedReceipts ?? [], error: null })
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

		expect(result).toEqual({
			noticesSent: 1,
			noticesSkipped: 0,
			purgesCompleted: 0,
			purgesFailed: 0,
			authCleanupsCompleted: 0,
			authCleanupsFailed: 0
		});
		expect(mockedEnqueueEmail).toHaveBeenCalledTimes(1);
		expect(mockedEnqueueEmail).toHaveBeenCalledWith(
			harness.client,
			expect.objectContaining({
				recipientEmail: 'owner@ridgeway.example',
				idempotencyKey: 'closure:closure-1:fourteen_day_reminder'
			})
		);
		expect(harness.__closureNoticeInserts).toEqual([
			{ closure_record_id: 'closure-1', notice_kind: 'fourteen_day_reminder', outbox_delivery_id: 'delivery-1' }
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
});
