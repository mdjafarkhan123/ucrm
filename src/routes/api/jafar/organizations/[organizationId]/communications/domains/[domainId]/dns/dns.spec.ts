import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const domainId = '123e4567-e89b-12d3-a456-426614174001';

function event() {
	return {
		params: { organizationId, domainId },
		request: new Request(
			`http://localhost/api/jafar/organizations/${organizationId}/communications/domains/${domainId}/dns`
		),
		url: new URL(
			`http://localhost/api/jafar/organizations/${organizationId}/communications/domains/${domainId}/dns`
		),
		cookies: {}
	} as Parameters<typeof GET>[0];
}

describe('owner sending-domain DNS setup boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('does not expose DNS setup without the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await GET(event());
		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('returns only the DNS fields Jafar needs to configure the domain', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
		const builder: Record<string, ReturnType<typeof vi.fn>> = {};
		builder.select = vi.fn(() => builder);
		builder.eq = vi.fn(() => builder);
		builder.neq = vi.fn(() => builder);
		builder.maybeSingle = vi.fn().mockResolvedValue({
			data: {
				domain_name: 'mail.ridgeway.example',
				last_checked_at: '2026-08-24T00:00:00.000Z',
				dns_records: [
					{
						type: 'TXT',
						host_name: 'mail',
						value: 'brevo-code:abc',
						status: true,
						provider_id: 42
					},
					{ type: 'TXT', host_name: 1, value: 'invalid', status: true }
				]
			},
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ from: vi.fn(() => builder) } as never);

		const response = await GET(event());
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			domain_name: 'mail.ridgeway.example',
			last_checked_at: '2026-08-24T00:00:00.000Z',
			dns_records: [{ type: 'TXT', host_name: 'mail', value: 'brevo-code:abc', status: true }]
		});
	});
});
