import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));

const organizationId = '00000000-0000-4000-8000-0000000000aa';

function sourcesEvent(result: { data: unknown; error: unknown }) {
	return {
		url: new URL('http://localhost/api/pipeline/lead-sources'),
		locals: { supabase: { rpc: vi.fn().mockResolvedValue(result) } }
	} as unknown as Parameters<typeof GET>[0];
}

describe('board lead sources', () => {
	beforeEach(() => {
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { organization: { id: organizationId } }
		} as never);
	});

	it('lists the sources the open cards carry, most used first, for this organization only', async () => {
		const event = sourcesEvent({
			data: [
				{ lead_source: 'Referral', open_count: 44 },
				{ lead_source: 'Google', open_count: 2 }
			],
			error: null
		});
		const body = await (await GET(event)).json();
		expect(body.lead_sources).toEqual(['Referral', 'Google']);
		expect(
			(event.locals as unknown as { supabase: { rpc: ReturnType<typeof vi.fn> } }).supabase.rpc
		).toHaveBeenCalledWith('pipeline_lead_sources', { target_organization_id: organizationId });
	});

	it('reports a database failure rather than an empty list', async () => {
		const response = await GET(sourcesEvent({ data: null, error: { message: 'down' } }));
		expect(response.status).toBe(500);
	});
});
