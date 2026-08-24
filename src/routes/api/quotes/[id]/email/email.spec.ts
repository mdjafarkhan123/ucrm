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
const quoteId = '00000000-0000-4000-8000-000000000091';

function event(body: unknown) {
	return {
		params: { id: quoteId },
		request: new Request(`http://localhost/api/quotes/${quoteId}/email`, {
			method: 'POST',
			body: JSON.stringify(body)
		})
	} as Parameters<typeof POST>[0];
}

describe('queueing a quote email', () => {
	const rpc = vi.fn();

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: {
				permissions: { 'quotes.send': true, 'conversations.send': true },
				features: { 'core.quotes': true }
			}
		} as never);
		mockedOwnerClient.mockReturnValue({ rpc } as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		mockedLink.mockReturnValue({ tokenHash: '\\xabc', url: 'https://app.example.com/q/token' });
		rpc.mockResolvedValue({
			data: { id: 'intent-1', status: 'queued', created_at: '2026-08-24T12:00:00Z' },
			error: null
		});
	});

	it('requires the quote send permission', async () => {
		await POST(event({ idempotency_key: '00000000-0000-4000-8000-000000000001' }));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.send');
	});

	it('refuses a member without conversation sending before it creates a link or calls the command', async () => {
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: {
				permissions: { 'quotes.send': true, 'conversations.send': false },
				features: { 'core.quotes': true }
			}
		} as never);

		const response = await POST(event({ idempotency_key: '00000000-0000-4000-8000-000000000001' }));

		expect(response.status).toBe(403);
		expect(await response.json()).toEqual({
			error: 'You do not have access to do that.',
			reason: 'permission_denied'
		});
		expect(mockedLink).not.toHaveBeenCalled();
		expect(mockedRateLimit).not.toHaveBeenCalled();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('accepts only an idempotency key from the browser', async () => {
		const response = await POST(
			event({
				idempotency_key: '00000000-0000-4000-8000-000000000001',
				recipient_email: 'attacker@example.com'
			})
		);
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('uses the server-generated link and service-only command', async () => {
		const response = await POST(event({ idempotency_key: '00000000-0000-4000-8000-000000000001' }));
		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('enqueue_quote_communication_email', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_quote_id: quoteId,
			target_logical_send_key: '00000000-0000-4000-8000-000000000001',
			target_quote_url: 'https://app.example.com/q/token',
			target_quote_token_hash: '\\xabc'
		});
	});
});
