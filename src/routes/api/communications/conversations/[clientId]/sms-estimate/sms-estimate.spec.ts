import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/access/permission', () => ({
	hasPermission: vi.fn(),
	requireOrganizationPermission: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '123e4567-e89b-12d3-a456-426614174001';
const clientId = '123e4567-e89b-12d3-a456-426614174002';

function event(body: unknown) {
	return {
		params: { clientId },
		request: new Request(
			`http://localhost/api/communications/conversations/${clientId}/sms-estimate`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		locals: {}
	} as Parameters<typeof POST>[0];
}

describe('SMS reply estimate API', () => {
	const rpc = vi.fn();
	const maybeSingle = vi.fn();
	// The route chains four .eq() calls before .maybeSingle(); each .eq() call returns the same
	// chainable stub so the mock does not have to mirror the exact chain length.
	const chain = { eq: () => chain, maybeSingle };
	const from = vi.fn(() => ({ select: () => chain }));

	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { user: { id: userId }, organization: { id: organizationId } },
			access: { features: {}, limits: {}, permissions: {} }
		} as never);
		vi.mocked(hasPermission).mockReturnValue(true);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc, from } as never);
		maybeSingle.mockResolvedValue({
			data: { phone_number: '+15559990001', country_code: 'US', sender_type: 'long_code' },
			error: null
		});
		rpc.mockImplementation((name: string) => {
			if (name === 'communication_sms_estimate_segments') {
				return Promise.resolve({ data: [{ encoding: 'gsm7', segment_count: 1 }], error: null });
			}
			if (name === 'communication_sms_effective_retail_rate') {
				return Promise.resolve({
					data: { retail_rate_major: 0.05, currency_code: 'USD' },
					error: null
				});
			}
			throw new Error(`unexpected rpc ${name}`);
		});
	});

	it('stops before reading anything when the caller cannot send conversations', async () => {
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});
		const response = await POST(event({ body: 'Hi' }));
		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('does not let sending permission bypass customer visibility', async () => {
		vi.mocked(hasPermission).mockReturnValue(false);
		const response = await POST(event({ body: 'Hi' }));
		expect(response.status).toBe(403);
	});

	it('returns the segment count and estimated cost for a ready organization', async () => {
		const response = await POST(event({ body: 'On our way over.' }));
		expect(response.status).toBe(200);
		const result = await response.json();
		expect(result).toEqual({
			ready: true,
			encoding: 'gsm7',
			segment_count: 1,
			cost_minor: 5,
			currency: 'USD',
			sender_phone: '+15559990001'
		});
	});

	it('reports not-ready when no default SMS sender exists', async () => {
		maybeSingle.mockResolvedValue({ data: null, error: null });
		const response = await POST(event({ body: 'Hi' }));
		expect(response.status).toBe(200);
		const result = await response.json();
		expect(result).toEqual({
			ready: false,
			reason: 'No ready SMS number is available to send from.'
		});
		expect(rpc).not.toHaveBeenCalled();
	});

	it('reports not-ready when no retail rate is published for the destination', async () => {
		rpc.mockImplementation((name: string) => {
			if (name === 'communication_sms_estimate_segments') {
				return Promise.resolve({ data: [{ encoding: 'gsm7', segment_count: 1 }], error: null });
			}
			return Promise.resolve({ data: null, error: null });
		});
		const response = await POST(event({ body: 'Hi' }));
		expect(response.status).toBe(200);
		const result = await response.json();
		expect(result).toEqual({
			ready: false,
			reason: 'No SMS price is published for this destination yet.'
		});
	});

	it('rejects an empty body without reading anything', async () => {
		const response = await POST(event({ body: '' }));
		expect(response.status).toBe(200);
		const result = await response.json();
		expect(result).toEqual({ ready: false, reason: 'Enter a message to see its estimated cost.' });
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});
});
