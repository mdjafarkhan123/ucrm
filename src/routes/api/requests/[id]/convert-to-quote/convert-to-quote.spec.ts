import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganization } from '$lib/server/auth/organization';

vi.mock('$lib/server/auth/organization', () => ({
	requireOrganization: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganization);
const requestId = '00000000-0000-4000-8000-000000000051';
const idempotencyKey = '00000000-0000-4000-8000-000000000052';

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: requestId },
		request: new Request(`http://localhost/api/requests/${requestId}/convert-to-quote`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

const validBody = { idempotency_key: idempotencyKey, request_hash: 'rev-3:lines-2' };

describe('convert request to quote API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			organization: { id: 'org-1' },
			user: { id: 'user-1' }
		} as never);
	});

	it('refuses a signed-out caller before touching the database', async () => {
		mockedRequire.mockResolvedValue(null as never);
		const rpc = vi.fn();

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a missing idempotency key', async () => {
		const rpc = vi.fn();
		const response = await POST(event({ request_hash: 'rev-3' }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.idempotency_key).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects an empty request fingerprint', async () => {
		const rpc = vi.fn();
		const response = await POST(
			event({ idempotency_key: idempotencyKey, request_hash: '   ' }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('creates the quote and answers 201', async () => {
		const created = {
			applied: true,
			quote_id: 'quote-1',
			quote_number: 7,
			quote_version_id: 'version-1',
			status: 'draft',
			line_count: 2,
			subtotal_minor: 45000
		};
		const rpc = vi.fn().mockResolvedValue({ data: created, error: null });

		const response = await POST(event(validBody, rpc));

		expect(rpc).toHaveBeenCalledWith('convert_request_to_quote', {
			target_request_id: requestId,
			idempotency_key: idempotencyKey,
			request_hash: 'rev-3:lines-2'
		});
		expect(response.status).toBe(201);
		expect(await response.json()).toEqual(created);
	});

	it('returns the first quote again when the same click arrives twice', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: {
				applied: false,
				quote_id: 'quote-1',
				quote_number: 7,
				quote_version_id: 'version-1',
				status: 'draft'
			},
			error: null
		});

		const response = await POST(event(validBody, rpc));
		const body = await response.json();

		expect(response.status).toBe(201);
		expect(body.applied).toBe(false);
		expect(body.quote_id).toBe('quote-1');
	});

	it('turns a replay with changed contents into a conflict', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0409', message: 'This request already has a quote.' }
		});

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(409);
		expect((await response.json()).reason).toBe('already_converted');
	});

	it('turns an ineligible status into a field error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'This request cannot be turned into a quote right now.' }
		});

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(
			'This request cannot be turned into a quote right now.'
		);
	});

	it('turns a missing quotes.create permission into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(404);
	});

	it('turns any other database error into a generic failure', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '08000', message: 'connection failure' } });

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(500);
	});
});
