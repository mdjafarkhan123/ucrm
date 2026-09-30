import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const editionId = '223e4567-e89b-12d3-a456-426614174000';

function event(query: string) {
	const url = new URL(
		`http://localhost/api/jafar/organizations/${organizationId}/billing/change-preview?${query}`
	);
	return {
		params: { organizationId },
		url,
		request: new Request(url),
		cookies: {}
	} as unknown as Parameters<typeof GET>[0];
}

describe('package change preview', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(event(`edition_id=${editionId}&billing_interval=month&timing=now`));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('refuses an incomplete choice before database access', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);

		const response = await GET(event(`edition_id=${editionId}&billing_interval=week`));
		const body = await response.json();

		expect(response.status).toBe(422);
		expect(body.field_errors.billing_interval).toBeTruthy();
		expect(body.field_errors.timing).toBeTruthy();
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns what the database previews', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);
		const preview = { blockers: [], money: { credit_usd_cents: 0 } };
		const rpc = vi.fn().mockResolvedValue({ data: preview, error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(
			event(`edition_id=${editionId}&billing_interval=year&timing=next_renewal`)
		);

		expect(response.status).toBe(200);
		expect((await response.json()).preview).toEqual(preview);
		expect(rpc).toHaveBeenCalledWith('owner_package_change_preview', {
			target_organization_id: organizationId,
			target_edition_id: editionId,
			billing_interval: 'year',
			timing: 'next_renewal'
		});
	});
});
