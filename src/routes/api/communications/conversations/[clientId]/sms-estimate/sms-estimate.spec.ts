import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/access/permission', async () => ({
	hasPermission: vi.fn(),
	requireOrganizationPermission: vi.fn(),
	featureUnavailable: (
		await vi.importActual<typeof import('$lib/server/access/permission')>(
			'$lib/server/access/permission'
		)
	).featureUnavailable
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

function openRoute(overrides: Record<string, unknown> = {}) {
	return {
		data: [
			{
				recipient_country: 'US',
				sender_id: '123e4567-e89b-12d3-a456-426614174003',
				sender_country: 'US',
				sender_type: 'long_code',
				ok: true,
				code: null,
				message: null,
				mms_route: true,
				...overrides
			}
		],
		error: null
	};
}

describe('SMS reply estimate API', () => {
	const rpc = vi.fn();
	const maybeSingle = vi.fn();
	// The sender read chains .eq() calls before .maybeSingle(); each .eq() call returns the same
	// chainable stub so the mock does not have to mirror the exact chain length.
	const chain = { eq: () => chain, maybeSingle };
	const from = vi.fn(() => ({ select: () => chain }));

	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { user: { id: userId }, organization: { id: organizationId } },
			access: { features: { 'communications.inbox': true }, limits: {}, permissions: {} }
		} as never);
		vi.mocked(hasPermission).mockReturnValue(true);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc, from } as never);
		maybeSingle.mockResolvedValue({ data: { phone_number: '+15559990001' }, error: null });
		rpc.mockImplementation((name: string) => {
			if (name === 'communication_sms_reply_route_preview') return Promise.resolve(openRoute());
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
			sender_phone: '+15559990001',
			recipient_country: 'US',
			mms_eligible: true
		});
		expect(rpc).toHaveBeenCalledWith('communication_sms_reply_route_preview', {
			p_organization_id: organizationId,
			p_client_id: clientId
		});
	});

	it("prices the text at the customer's country, not the sending number's", async () => {
		rpc.mockImplementation((name: string) => {
			if (name === 'communication_sms_reply_route_preview') {
				return Promise.resolve(openRoute({ recipient_country: 'CA' }));
			}
			if (name === 'communication_sms_estimate_segments') {
				return Promise.resolve({ data: [{ encoding: 'gsm7', segment_count: 1 }], error: null });
			}
			return Promise.resolve({
				data: { retail_rate_major: 0.05, currency_code: 'USD' },
				error: null
			});
		});
		const response = await POST(event({ body: 'Hi' }));
		expect((await response.json()).recipient_country).toBe('CA');
		expect(rpc).toHaveBeenCalledWith('communication_sms_effective_retail_rate', {
			p_destination: 'CA',
			p_sender_type: 'long_code',
			p_message_unit: 'segment'
		});
	});

	it('reports not-ready when no SMS number can send', async () => {
		rpc.mockResolvedValue({
			data: [
				{
					recipient_country: 'US',
					sender_id: null,
					sender_country: null,
					sender_type: null,
					ok: false,
					code: 'no_sender',
					message: 'No ready SMS number is available to send from.',
					mms_route: false
				}
			],
			error: null
		});
		const response = await POST(event({ body: 'Hi' }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			ready: false,
			reason: 'No ready SMS number is available to send from.',
			route_code: 'no_sender',
			recipient_country: 'US',
			mms_eligible: false
		});
		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('explains a customer country that is not switched on, without pricing it', async () => {
		rpc.mockResolvedValue(
			openRoute({
				recipient_country: 'DE',
				ok: false,
				code: 'destination_off',
				message: "Texting this country isn't switched on for your business.",
				mms_route: false
			})
		);
		const response = await POST(event({ body: 'Hallo' }));
		expect(await response.json()).toEqual({
			ready: false,
			reason: "Texting this country isn't switched on for your business.",
			route_code: 'destination_off',
			recipient_country: 'DE',
			mms_eligible: false
		});
		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('reports not-ready when no retail rate is published for the destination', async () => {
		rpc.mockImplementation((name: string) => {
			if (name === 'communication_sms_reply_route_preview') return Promise.resolve(openRoute());
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
			reason: 'No SMS price is published for this destination yet.',
			route_code: 'no_price',
			recipient_country: 'US',
			mms_eligible: true
		});
	});

	// Stage 6D-2: an empty draft still resolves MMS eligibility from the route alone (so the composer's
	// attach-photo button can appear before any text is typed), but never reaches the segment/rate RPCs --
	// there's no cost to estimate for a message with no body yet.
	it('resolves MMS eligibility for an empty body without estimating a cost', async () => {
		const response = await POST(event({ body: '' }));
		expect(response.status).toBe(200);
		const result = await response.json();
		expect(result).toEqual({
			ready: false,
			reason: 'Enter a message to see its estimated cost.',
			mms_eligible: true
		});
		expect(rpc).toHaveBeenCalledTimes(1);
	});
});
