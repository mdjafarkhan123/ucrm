import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	SenderCommandError,
	loadSenderRemovalImpact,
	removeCommunicationSender
} from '$lib/server/communications/sender-commands';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));
vi.mock('$lib/server/communications/sender-commands', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/sender-commands')>()),
	loadSenderRemovalImpact: vi.fn(),
	removeCommunicationSender: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '123e4567-e89b-12d3-a456-426614174001';
const senderId = '123e4567-e89b-12d3-a456-426614174002';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174003';

function event(method: 'GET' | 'POST', body?: unknown, id = senderId) {
	return {
		params: { senderId: id },
		request: new Request(`http://localhost/api/settings/communications/senders/${id}/remove`, {
			method,
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: {}
	} as never;
}

describe('contractor sender removal API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: {
				user: { id: userId },
				organization: { id: organizationId, name: 'Ridgeway', role: 'admin' }
			},
			access: { features: {}, limits: {}, permissions: {} }
		} as never);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({} as never);
	});

	it('refuses both preview and removal without the manage-connections permission', async () => {
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		expect((await GET(event('GET'))).status).toBe(403);
		expect((await POST(event('POST', { idempotency_key: idempotencyKey }))).status).toBe(403);
		expect(loadSenderRemovalImpact).not.toHaveBeenCalled();
		expect(removeCommunicationSender).not.toHaveBeenCalled();
		expect(requireOrganizationPermission).toHaveBeenCalledWith(
			expect.anything(),
			'conversations.manage_connections'
		);
	});

	it('previews the impact for the caller organization only', async () => {
		const impact = {
			is_organization_default: true,
			assigned_member_name: 'Alex',
			queued_email_count: 2,
			other_enabled_sender_count: 0
		};
		vi.mocked(loadSenderRemovalImpact).mockResolvedValue(impact);

		const response = await GET(event('GET'));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ impact });
		expect(loadSenderRemovalImpact).toHaveBeenCalledWith(
			expect.anything(),
			organizationId,
			senderId
		);
	});

	it('reports a removed or foreign sender as not found', async () => {
		vi.mocked(loadSenderRemovalImpact).mockResolvedValue(null);
		expect((await GET(event('GET'))).status).toBe(404);
	});

	it('rejects a bad sender id or missing idempotency key before database access', async () => {
		expect((await POST(event('POST', { idempotency_key: idempotencyKey }, 'nope'))).status).toBe(
			422
		);
		expect((await POST(event('POST', {}))).status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('removes with tenant and actor identity from the authenticated context', async () => {
		vi.mocked(removeCommunicationSender).mockResolvedValue({
			sender: { id: senderId },
			replayed: false
		} as never);

		const response = await POST(event('POST', { idempotency_key: idempotencyKey }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ sender_id: senderId, removed: true, replayed: false });
		expect(removeCommunicationSender).toHaveBeenCalledWith(expect.anything(), {
			organizationId,
			actorUserId: userId,
			senderId,
			idempotencyKey
		});
	});

	it('passes a command error through with its status', async () => {
		vi.mocked(removeCommunicationSender).mockRejectedValue(
			new SenderCommandError('The sender or sending domain could not be found.', 404, 'not_found')
		);
		const response = await POST(event('POST', { idempotency_key: idempotencyKey }));
		expect(response.status).toBe(404);
	});
});
