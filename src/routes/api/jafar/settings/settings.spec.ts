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

// The Settings home's two attention reads: an awaitable count query, whatever filters are chained on it.
function countQuery(count: number) {
	const result = { count, error: null };
	const chain: Record<string, unknown> = {
		eq: () => chain,
		is: () => chain,
		then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve)
	};
	return chain;
}

function settingsClient(
	settingsTable: Record<string, unknown>,
	counts: { pauses?: number; cleanups?: number } = {}
) {
	return {
		from: (table: string) => {
			if (table === 'communication_email_sending_pauses')
				return { select: () => countQuery(counts.pauses ?? 0) };
			if (table === 'organization_deletion_receipts')
				return { select: () => countQuery(counts.cleanups ?? 0) };
			return settingsTable;
		}
	} as never;
}

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
			mockedOwnerSession.mockResolvedValue(null);

			const response = await GET(getEvent());

			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('creates the singleton row on first read and returns it', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});
			const upsert = vi.fn().mockResolvedValue({ error: null });
			const single = vi.fn().mockResolvedValue({
				data: { ...validSettings, updated_at: '2026-08-12T00:00:00Z' },
				error: null
			});
			mockedClient.mockReturnValue(
				settingsClient({ upsert, select: () => ({ eq: () => ({ single }) }) })
			);

			const response = await GET(getEvent());

			expect(response.status).toBe(200);
			expect(upsert).toHaveBeenCalledWith(
				{ id: true, alert_recipient_emails: ['owner@example.com'] },
				{ onConflict: 'id', ignoreDuplicates: true }
			);
			const body = await response.json();
			expect(body.settings.reply_to_address).toBe('hello@example.com');
			expect(body.attention).toEqual({ email_sending_paused: false, unfinished_cleanups: 0 });
		});

		it('reports a platform email pause and unfinished cleanups for the Settings home', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});
			const single = vi.fn().mockResolvedValue({
				data: { ...validSettings, updated_at: '2026-08-12T00:00:00Z' },
				error: null
			});
			mockedClient.mockReturnValue(
				settingsClient(
					{
						upsert: vi.fn().mockResolvedValue({ error: null }),
						select: () => ({ eq: () => ({ single }) })
					},
					{ pauses: 1, cleanups: 2 }
				)
			);

			const body = await (await GET(getEvent())).json();

			expect(body.attention).toEqual({ email_sending_paused: true, unfinished_cleanups: 2 });
		});

		it('returns a safe error when the read fails', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});
			mockedClient.mockReturnValue(
				settingsClient({
					upsert: vi.fn().mockResolvedValue({ error: null }),
					select: () => ({
						eq: () => ({
							single: vi.fn().mockResolvedValue({ data: null, error: { message: 'db down' } })
						})
					})
				})
			);

			const response = await GET(getEvent());

			expect(response.status).toBe(500);
			expect(await response.json()).toEqual({ error: 'Settings could not be loaded.' });
		});
	});

	describe('PATCH', () => {
		it('rejects callers without the separate owner session', async () => {
			mockedOwnerSession.mockResolvedValue(null);

			const response = await PATCH(patchEvent(validSettings));

			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('rejects invalid JSON bodies', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
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
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});

			const response = await PATCH(
				patchEvent({ ...validSettings, reply_to_address: 'not-an-email' })
			);

			expect(response.status).toBe(422);
			const body = await response.json();
			expect(body.field_errors.reply_to_address).toBeDefined();
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('requires at least one alert recipient', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});

			const response = await PATCH(patchEvent({ ...validSettings, alert_recipient_emails: [] }));

			expect(response.status).toBe(422);
			const body = await response.json();
			expect(body.field_errors.alert_recipient_emails).toBeDefined();
		});

		it('returns a safe error when the update fails', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});
			mockedClient.mockReturnValue({
				rpc: vi.fn().mockResolvedValue({ data: null, error: { message: 'db down' } })
			} as never);

			const response = await PATCH(patchEvent(validSettings));

			expect(response.status).toBe(500);
			expect(await response.json()).toEqual({ error: 'Settings could not be saved.' });
		});

		it('saves valid settings through the atomic update RPC', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
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

		it('saves one section alone, sending null for every field it left out', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});
			const rpc = vi.fn().mockResolvedValue({
				data: {
					...validSettings,
					sender_display_name: 'Uplift',
					updated_at: '2026-08-12T01:00:00Z'
				},
				error: null
			});
			mockedClient.mockReturnValue({ rpc } as never);

			const response = await PATCH(
				patchEvent({ sender_display_name: 'Uplift', reply_to_address: 'Hello@Example.com' })
			);

			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('update_owner_settings', {
				actor_email: 'owner@example.com',
				new_privacy_policy_url: null,
				new_privacy_policy_version: null,
				new_payment_instructions: null,
				new_sender_display_name: 'Uplift',
				new_reply_to_address: 'hello@example.com',
				new_alert_recipient_emails: null
			});
		});

		it('rejects an empty body and fields it does not know', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});

			expect((await PATCH(patchEvent({}))).status).toBe(422);
			expect((await PATCH(patchEvent({ sender_display_name: 'Uplift', extra: 1 }))).status).toBe(
				422
			);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('still refuses to clear a field it was sent', async () => {
			mockedOwnerSession.mockResolvedValue({
				email: 'owner@example.com',
				sessionId: 'session-id'
			});

			const response = await PATCH(patchEvent({ sender_display_name: '   ' }));

			expect(response.status).toBe(422);
			expect((await response.json()).field_errors.sender_display_name).toBeDefined();
		});
	});
});
