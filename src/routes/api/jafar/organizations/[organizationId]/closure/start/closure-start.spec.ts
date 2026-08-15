import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { sendClosureNotice } from '$lib/server/jafar/organization-closure-cron';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/jafar/organization-closure-cron', () => ({ sendClosureNotice: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedConsumeStepUp = vi.mocked(consumeOwnerStepUp);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedSendClosureNotice = vi.mocked(sendClosureNotice);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function event(id = organizationId, body: unknown = {}) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/closure/start`, {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function requestBody(overrides: Record<string, unknown> = {}) {
	return {
		reason: 'Contractor requested closure.',
		typed_organization_name: 'Acme Roofing',
		idempotency_key: idempotencyKey,
		...overrides
	};
}

function organizationRow(overrides: Record<string, unknown> = {}) {
	return { id: organizationId, name: 'Acme Roofing', lifecycle_status: 'active', ...overrides };
}

function clientMock(options: {
	organization: Record<string, unknown> | null;
	rpcResult?: { data: unknown; error: unknown };
	refreshedOrganization?: Record<string, unknown> | null;
}) {
	const rpc = vi.fn().mockResolvedValue(options.rpcResult ?? { data: { applied: true }, error: null });
	let call = 0;
	const organizations = [options.organization, options.refreshedOrganization ?? options.organization];
	return {
		rpc,
		from: () => ({
			select: () => ({
				eq: () => ({
					maybeSingle: async () => ({ data: organizations[call++] ?? null, error: null })
				})
			})
		})
	} as never;
}

describe('platform owner closure-start API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		mockedSendClosureNotice.mockResolvedValue({ sent: true });
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization identifier before database access', async () => {
		const response = await POST(event('not-a-uuid', requestBody()));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a request missing a reason', async () => {
		const response = await POST(event(organizationId, requestBody({ reason: '' })));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before starting closure', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		mockedClient.mockReturnValue(clientMock({ organization: null }));

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(404);
	});

	it('rejects a typed organization name that does not match', async () => {
		mockedClient.mockReturnValue(clientMock({ organization: organizationRow() }));

		const response = await POST(
			event(organizationId, requestBody({ typed_organization_name: 'Wrong Name' }))
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.typed_organization_name).toBeDefined();
	});

	it('starts closure, sends the closure_started notice, and returns the refreshed organization', async () => {
		const rpcResult = {
			data: { applied: true, event_id: 'evt-1', closure_record_id: 'closure-1', deadline_at: '2026-09-14' },
			error: null
		};
		mockedClient.mockReturnValue(
			clientMock({
				organization: organizationRow(),
				rpcResult,
				refreshedOrganization: organizationRow({ lifecycle_status: 'pending_closure' })
			})
		);

		const response = await POST(event(organizationId, requestBody()));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.organization.lifecycle_status).toBe('pending_closure');
		expect(mockedSendClosureNotice).toHaveBeenCalledWith(expect.anything(), {
			closureRecordId: 'closure-1',
			organizationId,
			noticeKind: 'closure_started',
			mergeValues: {}
		});
	});

	it('does not send a notice on an idempotent replay with no closure_record_id', async () => {
		const rpcResult = { data: { applied: false, event_id: 'evt-1' }, error: null };
		mockedClient.mockReturnValue(clientMock({ organization: organizationRow(), rpcResult }));

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(200);
		expect(mockedSendClosureNotice).not.toHaveBeenCalled();
	});

	it('maps database validation and serialization conflicts to a safe conflict response', async () => {
		const rpcResult = { data: null, error: { code: '23514', message: 'private details' } };
		mockedClient.mockReturnValue(clientMock({ organization: organizationRow(), rpcResult }));

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'private details' });
	});
});
