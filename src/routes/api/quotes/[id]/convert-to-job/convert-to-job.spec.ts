import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganization } from '$lib/server/auth/organization';

vi.mock('$lib/server/auth/organization', () => ({
	requireOrganization: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganization);
const quoteId = '00000000-0000-4000-8000-000000000061';
const idempotencyKey = '00000000-0000-4000-8000-000000000062';

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: quoteId },
		request: new Request(`http://localhost/api/quotes/${quoteId}/convert-to-job`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

const validBody = { idempotency_key: idempotencyKey, quote_hash: 'v2:total-27300' };

describe('convert quote to job API', () => {
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
		const response = await POST(event({ quote_hash: 'v2' }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.idempotency_key).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects an empty quote fingerprint', async () => {
		const rpc = vi.fn();
		const response = await POST(event({ idempotency_key: idempotencyKey, quote_hash: '  ' }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.quote_hash).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a one-off job priced per visit before the database has to', async () => {
		const rpc = vi.fn();
		const response = await POST(
			event({ ...validBody, job_type: 'one_off', price_basis: 'per_visit' }, rpc)
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.price_basis).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses an as-needed one-off job', async () => {
		const rpc = vi.fn();
		const response = await POST(
			event({ ...validBody, job_type: 'one_off', is_as_needed: true }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('hands the whole command to the database and answers 201', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { applied: true, job_id: 'job-1', job_number: 7, line_count: 4 },
			error: null
		});

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('convert_quote_to_job', {
			target_quote_id: quoteId,
			idempotency_key: idempotencyKey,
			request_hash: 'v2:total-27300',
			new_job_type: 'one_off',
			new_price_basis: null,
			new_title: null,
			new_billing_timing: 'on_closure',
			new_is_as_needed: false,
			new_instructions: null
		});
		await expect(response.json()).resolves.toMatchObject({ job_number: 7 });
	});

	it('reports a quote that already has a job as a conflict', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0409', message: 'This quote already has a job.' }
		});

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({ reason: 'already_converted' });
	});

	it('turns a refused conversion into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'This quote is not ready for a job yet.' }
		});

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.form).toBe('This quote is not ready for a job yet.');
	});

	it('answers a quote it cannot see the same way as one that does not exist', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });

		const response = await POST(event(validBody, rpc));

		expect(response.status).toBe(404);
	});
});
