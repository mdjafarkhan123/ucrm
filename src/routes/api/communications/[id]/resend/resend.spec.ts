import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { createQuoteEmailAccessLink } from '$lib/server/communications/quote-email';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});
vi.mock('$lib/server/communications/quote-email', () => ({ createQuoteEmailAccessLink: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedLink = vi.mocked(createQuoteEmailAccessLink);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const mockedRateLimit = vi.mocked(checkRateLimit);
const intentId = '00000000-0000-4000-8000-000000000091';
const idempotencyKey = '00000000-0000-4000-8000-000000000001';

function event(body: unknown) {
	return {
		params: { id: intentId },
		request: new Request(`http://localhost/api/communications/${intentId}/resend`, {
			method: 'POST',
			body: JSON.stringify(body)
		})
	} as Parameters<typeof POST>[0];
}

describe('resending a communication email', () => {
	const rpc = vi.fn();
	const maybeSingle = vi.fn();
	const from = vi.fn(() => ({
		select: () => ({ eq: () => ({ eq: () => ({ maybeSingle }) }) })
	}));

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: { 'conversations.send': true }, features: {} }
		} as never);
		mockedOwnerClient.mockReturnValue({ rpc, from } as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		maybeSingle.mockResolvedValue({ data: { quote_id: null }, error: null });
		mockedLink.mockReturnValue({ tokenHash: '\\xabc', url: 'https://app.example.com/q/token' });
		rpc.mockResolvedValue({
			data: { id: 'intent-2', status: 'queued', created_at: '2026-08-25T12:00:00Z' },
			error: null
		});
	});

	it('requires conversations.send', async () => {
		await POST(event({ idempotency_key: idempotencyKey }));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'conversations.send');
	});

	it('accepts only an idempotency key from the browser', async () => {
		const response = await POST(
			event({ idempotency_key: idempotencyKey, subject: 'attacker-supplied subject' })
		);
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('does not mint a quote link for a manual-sourced message', async () => {
		const response = await POST(event({ idempotency_key: idempotencyKey }));
		expect(response.status).toBe(201);
		expect(mockedLink).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith('resend_communication_email', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_original_intent_id: intentId,
			target_logical_send_key: idempotencyKey,
			target_quote_url: undefined,
			target_quote_token_hash: undefined
		});
	});

	it('mints a fresh quote link when the original message was quote-sourced', async () => {
		maybeSingle.mockResolvedValue({ data: { quote_id: 'quote-1' }, error: null });
		const response = await POST(event({ idempotency_key: idempotencyKey }));
		expect(response.status).toBe(201);
		expect(mockedLink).toHaveBeenCalledOnce();
		expect(rpc).toHaveBeenCalledWith('resend_communication_email', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_original_intent_id: intentId,
			target_logical_send_key: idempotencyKey,
			target_quote_url: 'https://app.example.com/q/token',
			target_quote_token_hash: '\\xabc'
		});
	});

	it('maps a not-yet-resendable message to a 409', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '55000', message: 'This message cannot be resent right now.' }
		});
		const response = await POST(event({ idempotency_key: idempotencyKey }));
		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'This message cannot be resent right now.',
			reason: 'not_resendable'
		});
	});

	it('maps a missing message to a 404', async () => {
		rpc.mockResolvedValue({ data: null, error: { code: 'P0002' } });
		const response = await POST(event({ idempotency_key: idempotencyKey }));
		expect(response.status).toBe(404);
	});

	it('maps a permission failure from the command to a 403', async () => {
		rpc.mockResolvedValue({ data: null, error: { code: '42501' } });
		const response = await POST(event({ idempotency_key: idempotencyKey }));
		expect(response.status).toBe(403);
		expect(await response.json()).toEqual({
			error: 'You do not have access to do that.',
			reason: 'permission_denied'
		});
	});
});
