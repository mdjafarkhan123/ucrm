import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', () => ({
	hasPermission: vi.fn(),
	requireOrganizationPermission: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '123e4567-e89b-12d3-a456-426614174001';
const clientId = '123e4567-e89b-12d3-a456-426614174002';
const phoneId = '123e4567-e89b-12d3-a456-426614174003';

function postEvent(body: unknown) {
	return {
		params: { clientId },
		request: new Request(`http://localhost/api/communications/conversations/${clientId}/sms-stop`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: {}
	} as Parameters<typeof POST>[0];
}

function getEvent() {
	return { params: { clientId }, locals: {} } as Parameters<typeof GET>[0];
}

// A table read that resolves to `result` however it is chained -- enough for these routes' `.select().eq()...`.
function table(result: { data?: unknown; error?: unknown }) {
	const obj: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'in']) obj[method] = vi.fn(() => obj);
	obj.maybeSingle = vi.fn(() => Promise.resolve(result));
	(obj as { then: unknown }).then = (...args: unknown[]) =>
		(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(...args);
	return obj;
}

describe('stopping and restarting texts to a customer', () => {
	const rpc = vi.fn();

	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { organization: { id: organizationId }, user: { id: userId } },
			access: {}
		} as never);
		vi.mocked(hasPermission).mockReturnValue(true);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		rpc.mockResolvedValue({ data: {}, error: null });
	});

	describe('POST', () => {
		beforeEach(() => {
			vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
		});

		it('requires the permission to reply to customers', async () => {
			await POST(postEvent({ contact_method_id: phoneId, action: 'stop' }));
			expect(requireOrganizationPermission).toHaveBeenCalledWith(
				expect.anything(),
				'conversations.send'
			);
		});

		it('returns the permission failure untouched', async () => {
			vi.mocked(requireOrganizationPermission).mockResolvedValue({
				response: new Response(null, { status: 403 })
			} as never);
			const response = await POST(postEvent({ contact_method_id: phoneId, action: 'stop' }));
			expect(response.status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('rejects a bad body before touching the database', async () => {
			const response = await POST(postEvent({ contact_method_id: 'nope', action: 'stop' }));
			expect(response.status).toBe(422);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('rejects an unknown action and an over-long note', async () => {
			expect((await POST(postEvent({ contact_method_id: phoneId, action: 'pause' }))).status).toBe(
				422
			);
			expect(
				(
					await POST(
						postEvent({ contact_method_id: phoneId, action: 'stop', note: 'x'.repeat(501) })
					)
				).status
			).toBe(422);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('records a stop as the signed-in member with a trimmed note', async () => {
			const response = await POST(
				postEvent({ contact_method_id: phoneId, action: 'stop', note: '  Asked by phone  ' })
			);
			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith(
				'communication_sms_staff_stop',
				expect.objectContaining({
					p_organization_id: organizationId,
					p_actor: userId,
					p_client_id: clientId,
					p_client_contact_method_id: phoneId,
					p_note: 'Asked by phone'
				})
			);
		});

		it('sends an undo to the undo command, with no note', async () => {
			const response = await POST(postEvent({ contact_method_id: phoneId, action: 'undo' }));
			expect(response.status).toBe(200);
			expect(rpc).toHaveBeenCalledWith(
				'communication_sms_staff_stop_undo',
				expect.objectContaining({ p_actor: userId, p_client_contact_method_id: phoneId })
			);
		});

		it("shows the database's plain-English refusal as a 422", async () => {
			rpc.mockResolvedValue({
				data: null,
				error: { code: 'P0001', message: 'The customer stopped these texts themselves.' }
			});
			const response = await POST(postEvent({ contact_method_id: phoneId, action: 'undo' }));
			expect(response.status).toBe(422);
			expect((await response.json()).error).toBe('The customer stopped these texts themselves.');
		});

		it('hides any other database failure behind a generic error', async () => {
			rpc.mockResolvedValue({ data: null, error: { code: 'XX000', message: 'internal detail' } });
			vi.spyOn(console, 'error').mockImplementation(() => {});
			const response = await POST(postEvent({ contact_method_id: phoneId, action: 'stop' }));
			expect(response.status).toBe(500);
			expect(JSON.stringify(await response.json())).not.toContain('internal detail');
		});

		it('is rate limited', async () => {
			vi.mocked(checkRateLimit).mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
			const response = await POST(postEvent({ contact_method_id: phoneId, action: 'stop' }));
			expect(response.status).toBe(429);
			expect(rpc).not.toHaveBeenCalled();
		});
	});

	describe('GET', () => {
		function ownerWith(options: {
			phones: unknown[];
			email?: unknown;
			marketing?: unknown;
			profiles?: unknown[];
		}) {
			const tables: Record<string, ReturnType<typeof table>> = {
				client_contact_methods: table({ data: options.email ?? null }),
				client_marketing_consent_state: table({ data: options.marketing ?? null }),
				profiles: table({ data: options.profiles ?? [] })
			};
			return {
				rpc: vi.fn(() => Promise.resolve({ data: options.phones, error: null })),
				from: vi.fn((name: string) => tables[name])
			};
		}

		it('requires customers.view', async () => {
			vi.mocked(getOwnerSupabaseClient).mockReturnValue(ownerWith({ phones: [] }) as never);
			await GET(getEvent());
			expect(requireOrganizationPermission).toHaveBeenCalledWith(
				expect.anything(),
				'customers.view'
			);
		});

		it('names who stopped a number and reports what can be undone', async () => {
			vi.mocked(getOwnerSupabaseClient).mockReturnValue(
				ownerWith({
					phones: [
						{
							contact_method_id: phoneId,
							value: '+15550000101',
							is_primary: true,
							state: 'opted_out',
							stopped_by: 'staff',
							stopped_at: '2026-09-21T10:00:00Z',
							stopped_by_user: userId,
							note: 'Asked by phone',
							can_undo: true
						}
					],
					profiles: [{ id: userId, full_name: 'Sam Office' }]
				}) as never
			);
			const body = await (await GET(getEvent())).json();
			expect(body.phones).toEqual([
				{
					contact_method_id: phoneId,
					value: '+15550000101',
					is_primary: true,
					state: 'opted_out',
					stopped_by: 'staff',
					stopped_at: '2026-09-21T10:00:00Z',
					stopped_by_name: 'Sam Office',
					note: 'Asked by phone',
					can_undo: true
				}
			]);
			expect(body.marketing_email).toBeNull();
			expect(body.can_manage).toBe(true);
		});

		it('reports a member without reply permission as unable to manage', async () => {
			vi.mocked(hasPermission).mockImplementation((_access, key) => key !== 'conversations.send');
			vi.mocked(getOwnerSupabaseClient).mockReturnValue(ownerWith({ phones: [] }) as never);
			const body = await (await GET(getEvent())).json();
			expect(body.can_manage).toBe(false);
		});

		it('reads the primary email marketing standing, defaulting to unknown', async () => {
			vi.mocked(getOwnerSupabaseClient).mockReturnValue(
				ownerWith({ phones: [], email: { id: 'e1', value: 'a@example.test' } }) as never
			);
			const body = await (await GET(getEvent())).json();
			expect(body.marketing_email).toEqual({
				email: 'a@example.test',
				state: 'unknown',
				effective_at: null
			});
		});

		it('500s when a read fails', async () => {
			vi.mocked(getOwnerSupabaseClient).mockReturnValue({
				rpc: vi.fn(() => Promise.resolve({ data: null, error: { message: 'boom' } })),
				from: vi.fn(() => table({ data: null }))
			} as never);
			expect((await GET(getEvent())).status).toBe(500);
		});
	});
});
