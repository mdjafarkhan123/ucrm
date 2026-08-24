import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { createCommunicationSender } from '$lib/server/communications/sender-commands';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));
vi.mock('$lib/server/communications/sender-commands', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/sender-commands')>()),
	createCommunicationSender: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '123e4567-e89b-12d3-a456-426614174001';
const domainId = '123e4567-e89b-12d3-a456-426614174002';

function event(body: unknown) {
	return {
		request: new Request('http://localhost/api/settings/communications/senders', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: {}
	} as Parameters<typeof POST>[0];
}

const validBody = {
	domain_id: domainId,
	email_address: 'alex@mail.ridgeway.example',
	display_name: 'Alex | Ridgeway',
	assigned_user_id: userId,
	is_organization_default: true,
	allows_manual: true,
	allows_automated: false,
	idempotency_key: '123e4567-e89b-12d3-a456-426614174003'
};

describe('contractor communication senders API', () => {
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

	it('stops before validation and provider work when permission is denied', async () => {
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		const response = await POST(event(validBody));
		expect(response.status).toBe(403);
		expect(createCommunicationSender).not.toHaveBeenCalled();
	});

	it('validates sender eligibility fields before service-role access', async () => {
		const response = await POST(event({ ...validBody, allows_manual: false }));
		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('passes tenant and actor identity from the authenticated context', async () => {
		vi.mocked(createCommunicationSender).mockResolvedValue({
			sender: { id: 'sender-1' },
			replayed: false
		} as never);

		const response = await POST(event(validBody));
		expect(response.status).toBe(201);
		expect(createCommunicationSender).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({ organizationId, actorUserId: userId, domainId })
		);
		expect(response.headers.get('Cache-Control')).toBe('no-store');
	});
});
