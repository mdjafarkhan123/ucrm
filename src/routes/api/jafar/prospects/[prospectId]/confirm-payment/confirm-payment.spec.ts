import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';
const packageVersionId = '223e4567-e89b-12d3-a456-426614174000';

const validBody = {
	amount_usd_cents: 9900,
	private_reference: 'e-transfer #4821'
};

function event(id: string, body: unknown = validBody) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/confirm-payment', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/confirm-payment'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function clientWith(options: {
	applicationExists: boolean;
	packageVersionId?: string;
	priceUsdCents?: number | null;
	rpcError?: { message: string } | null;
}) {
	const rpc = vi.fn().mockResolvedValue({ error: options.rpcError ?? null });
	return {
		from: (table: string) => {
			if (table === 'platform_onboarding_applications') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () =>
								options.applicationExists
									? {
											data: { package_version_id: options.packageVersionId ?? packageVersionId },
											error: null
										}
									: { data: null, error: null }
						})
					})
				};
			}
			if (table === 'platform_package_versions') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({
								data:
									options.priceUsdCents === undefined
										? null
										: { price_usd_cents: options.priceUsdCents },
								error: null
							})
						})
					})
				};
			}
			throw new Error(`unexpected table ${table}`);
		},
		rpc,
		__rpc: rpc
	};
}

describe('platform owner prospect payment confirmation API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the request body before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event(prospectId, { ...validBody, amount_usd_cents: -1 }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ applicationExists: false }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects confirmation once the application is past the unpaid stages', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				applicationExists: true,
				rpcError: { message: 'This application can no longer be confirmed for payment.' }
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('requires a mismatch reason when the amount differs from the package price', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ applicationExists: true, priceUsdCents: 14900 }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({
			error: 'Please review the highlighted fields.',
			field_errors: { mismatch_reason: 'Enter a reason for the amount mismatch.' }
		});
	});

	it('confirms payment and moves the stage when the amount matches the package price', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({ applicationExists: true, priceUsdCents: 9900 });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith('confirm_onboarding_application_payment', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			amount_usd_cents: 9900,
			private_reference: 'e-transfer #4821',
			mismatch_reason: null
		});
	});

	it('accepts a mismatched amount with a reason and records it', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({ applicationExists: true, priceUsdCents: 14900 });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			event(prospectId, { ...validBody, mismatch_reason: 'Contractor paid the old price.' })
		);
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith(
			'confirm_onboarding_application_payment',
			expect.objectContaining({ mismatch_reason: 'Contractor paid the old price.' })
		);
	});

	it('returns a safe server error when the confirmation cannot be saved', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				applicationExists: true,
				priceUsdCents: 9900,
				rpcError: { message: 'internal database details' }
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The payment could not be confirmed.' });
	});
});
