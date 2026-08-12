import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/env', () => ({
	getServerEnv: () => ({
		SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
		SUPER_ADMIN_EMAIL: 'owner@example.com',
		SUPER_ADMIN_PASSWORD_HASH: 'hash',
		SESSION_SECRET: 'secret'
	})
}));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const validSettings = {
	privacy_policy_url: 'https://example.com/privacy',
	privacy_policy_version: 'v1',
	payment_instructions: 'Pay via bank transfer.',
	sender_display_name: 'UpliftContractor',
	reply_to_address: 'hello@example.com',
	alert_recipient_emails: ['owner@example.com']
};

function getEvent(url = 'http://localhost/api/jafar/settings') {
	return { url: new URL(url), params: {}, cookies: {} } as Parameters<typeof GET>[0];
}

function patchEvent(body: unknown) {
	return {
		params: {},
		request: new Request('http://localhost/api/jafar/settings', {
			method: 'PATCH',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/settings'),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

describe('platform owner settings API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	describe('GET', () => {
		it('rejects callers without the separate owner session', async () => {
			mockedOwnerSession.mockReturnValue(null);

			const response = await GET(getEvent());

			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('creates the singleton row on first read and returns it', async () => {
			mockedOwnerSession.mockReturnValue({
				email: 'owner@example.com',
				expiresAt: Date.now() + 1000
			});
			const upsert = vi.fn().mockResolvedValue({ error: null });
			const single = vi.fn().mockResolvedValue({
				data: { ...validSettings, updated_at: '2026-08-12T00:00:00Z' },
				error: null
			});
			mockedClient.mockReturnValue({
				from: () => ({ upsert, select: () => ({ eq: () => ({ single }) }) })
			} as never);

			const response = await GET(getEvent());

			expect(response.status).toBe(200);
			expect(upsert).toHaveBeenCalledWith(
				{ id: true, alert_recipient_emails: ['owner@example.com'] },
				{ onConflict: 'id', ignoreDuplicates: true }
			);
			const body = await response.json();
			expect(body.settings.reply_to_address).toBe('hello@example.com');
		});

		it('returns a safe error when the read fails', async () => {
			mockedOwnerSession.mockReturnValue({
				email: 'owner@example.com',
				expiresAt: Date.now() + 1000
			});
			mockedClient.mockReturnValue({
				from: () => ({
					upsert: vi.fn().mockResolvedValue({ error: null }),
					select: () => ({
						eq: () => ({
							single: vi.fn().mockResolvedValue({ data: null, error: { message: 'db down' } })
						})
					})
				})
			} as never);

			const response = await GET(getEvent());

			expect(response.status).toBe(500);
			expect(await response.json()).toEqual({ error: 'Settings could not be loaded.' });
		});
	});

	describe('PATCH', () => {
		it('rejects callers without the separate owner session', async () => {
			mockedOwnerSession.mockReturnValue(null);

			const response = await PATCH(patchEvent(validSettings));

			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('rejects invalid JSON bodies', async () => {
			mockedOwnerSession.mockReturnValue({
				email: 'owner@example.com',
				expiresAt: Date.now() + 1000
			});
			const event = {
				params: {},
				request: new Request('http://localhost/api/jafar/settings', {
					method: 'PATCH',
					body: 'not json',
					headers: { 'content-type': 'application/json' }
				}),
				url: new URL('http://localhost/api/jafar/settings'),
				cookies: {}
			} as Parameters<typeof PATCH>[0];

			const response = await PATCH(event);

			expect(response.status).toBe(400);
		});

		it('returns field errors for an invalid payload', async () => {
			mockedOwnerSession.mockReturnValue({
				email: 'owner@example.com',
				expiresAt: Date.now() + 1000
			});

			const response = await PATCH(patchEvent({ ...validSettings, reply_to_address: 'not-an-email' }));

			expect(response.status).toBe(422);
			const body = await response.json();
			expect(body.field_errors.reply_to_address).toBeDefined();
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('requires at least one alert recipient', async () => {
			mockedOwnerSession.mockReturnValue({
				email: 'owner@example.com',
				expiresAt: Date.now() + 1000
			});

			const response = await PATCH(patchEvent({ ...validSettings, alert_recipient_emails: [] }));

			expect(response.status).toBe(422);
			const body = await response.json();
			expect(body.field_errors.alert_recipient_emails).toBeDefined();
		});

		it('returns a safe error when the update fails', async () => {
			mockedOwnerSession.mockReturnValue({
				email: 'owner@example.com',
				expiresAt: Date.now() + 1000
			});
			mockedClient.mockReturnValue({
				rpc: vi.fn().mockResolvedValue({ data: null, error: { message: 'db down' } })
			} as never);

			const response = await PATCH(patchEvent(validSettings));

			expect(response.status).toBe(500);
			expect(await response.json()).toEqual({ error: 'Settings could not be saved.' });
		});

		it('saves valid settings through the atomic update RPC', async () => {
			mockedOwnerSession.mockReturnValue({
				email: 'owner@example.com',
				expiresAt: Date.now() + 1000
			});
			const rpc = vi.fn().mockResolvedValue({
				data: { ...validSettings, updated_at: '2026-08-12T01:00:00Z' },
				error: null
			});
			mockedClient.mockReturnValue({ rpc } as never);

			const response = await PATCH(patchEvent(validSettings));

			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('update_owner_settings', {
				actor_email: 'owner@example.com',
				new_privacy_policy_url: validSettings.privacy_policy_url,
				new_privacy_policy_version: validSettings.privacy_policy_version,
				new_payment_instructions: validSettings.payment_instructions,
				new_sender_display_name: validSettings.sender_display_name,
				new_reply_to_address: validSettings.reply_to_address,
				new_alert_recipient_emails: validSettings.alert_recipient_emails
			});
		});
	});
});
