import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000051';
const organizationId = '00000000-0000-4000-8000-000000000052';
const requestId = '00000000-0000-4000-8000-000000000053';
const quoteId = '00000000-0000-4000-8000-000000000054';
const idempotencyKey = '00000000-0000-4000-8000-000000000055';

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;

function gateResult(overrides: Record<string, unknown> = {}) {
	return {
		organization_id: organizationId,
		request_id: requestId,
		quote_id: null,
		from_stage: 'new_request',
		...overrides
	};
}

// One chain stands in for a full `.from(...).x().y().maybeSingle()` call. Every method just returns the
// same object so any combination the route calls resolves; awaiting the chain directly (no `.maybeSingle`
// in the way) and calling `.maybeSingle()`/`.single()` both settle to the same queued result.
function chain(result: { data?: unknown; error?: unknown } = { data: null, error: null }) {
	const obj: Record<string, unknown> = {};
	for (const method of ['upsert', 'update', 'select', 'eq', 'in', 'delete']) {
		obj[method] = vi.fn(() => obj);
	}
	obj.maybeSingle = vi.fn(() => Promise.resolve(result));
	obj.single = vi.fn(() => Promise.resolve(result));
	(obj as { then: unknown }).then = (...args: unknown[]) =>
		(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(...args);
	return obj;
}

// Each `.from(table)` call pops the next queued result in order, so a test can describe exactly what each
// call in sequence answers with.
function fromQueue(results: Array<{ data?: unknown; error?: unknown }>) {
	const queue = [...results];
	return vi.fn(() => chain(queue.shift() ?? { data: null, error: null }));
}

function event(
	body: unknown,
	options: {
		rpc?: ReturnType<typeof vi.fn>;
		from?: ReturnType<typeof vi.fn>;
	} = {}
) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/move`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: {
			supabase: {
				rpc: options.rpc ?? vi.fn(),
				from: options.from ?? vi.fn(() => chain())
			}
		}
	} as unknown as Parameters<typeof POST>[0];
}

describe('drag an opportunity', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(event({ to_stage: 'assessment_unscheduled' }, { rpc }));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON', async () => {
		const rpc = vi.fn();
		const response = await POST(event('not json', { rpc }));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a to_stage outside the known stage vocabulary', async () => {
		const rpc = vi.fn();
		const response = await POST(event({ to_stage: 'made_up_stage' }, { rpc }));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('turns a refusal from the drag gate into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await POST(event({ to_stage: 'assessment_unscheduled' }, { rpc }));

		expect(response.status).toBe(404);
	});

	it('turns a disallowed transition from the drag gate into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'That card cannot be moved there.' }
		});

		const response = await POST(event({ to_stage: 'assessment_completed' }, { rpc }));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('cannot be moved');
	});

	it('turns any other error from the drag gate into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '08000' } });
		const response = await POST(event({ to_stage: 'assessment_unscheduled' }, { rpc }));
		expect(response.status).toBe(500);
	});

	it('turns on an assessment for a new request dragged onto Assessment unscheduled', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: gateResult(), error: null });
		const from = fromQueue([
			{ data: null, error: null },
			{ data: null, error: null }
		]);

		const response = await POST(event({ to_stage: 'assessment_unscheduled' }, { rpc, from }));

		expect(from).toHaveBeenNthCalledWith(1, 'assessments');
		expect(from).toHaveBeenNthCalledWith(2, 'requests');
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			id: opportunityId,
			from_stage: 'new_request',
			to_stage: 'assessment_unscheduled'
		});
	});

	it('requires a start and end time before scheduling an assessment', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: gateResult(), error: null });
		const from = vi.fn(() => chain());

		const response = await POST(event({ to_stage: 'assessment_scheduled' }, { rpc, from }));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.starts_at).toBeDefined();
		expect(from).not.toHaveBeenCalled();
	});

	it('schedules the assessment when a start and end time are given', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: gateResult(), error: null });
		const upsertChain = chain({ data: null, error: null });
		const from = vi.fn(() => upsertChain);

		const response = await POST(
			event(
				{
					to_stage: 'assessment_scheduled',
					starts_at: '2026-09-01T09:00:00.000Z',
					ends_at: '2026-09-01T10:00:00.000Z'
				},
				{ rpc, from }
			)
		);

		expect(upsertChain.upsert).toHaveBeenCalledWith(
			expect.objectContaining({
				starts_at: '2026-09-01T09:00:00.000Z',
				ends_at: '2026-09-01T10:00:00.000Z'
			}),
			{ onConflict: 'request_id' }
		);
		expect(response.status).toBe(200);
	});

	it('completes an existing assessment when dragged onto Assessment completed', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: gateResult({ from_stage: 'assessment_scheduled' }),
			error: null
		});
		const from = fromQueue([
			{ data: { id: 'assessment-1' }, error: null },
			{ data: null, error: null }
		]);

		const response = await POST(event({ to_stage: 'assessment_completed' }, { rpc, from }));

		expect(response.status).toBe(200);
	});

	it('answers not-found when there is no assessment left to complete', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: gateResult({ from_stage: 'assessment_scheduled' }),
			error: null
		});
		const from = fromQueue([{ data: null, error: null }]);

		const response = await POST(event({ to_stage: 'assessment_completed' }, { rpc, from }));

		expect(response.status).toBe(404);
	});

	it('sends the current draft when a quote is dragged onto Awaiting response', async () => {
		const rpc = vi.fn();
		rpc.mockResolvedValueOnce({
			data: gateResult({ request_id: null, quote_id: quoteId, from_stage: 'quote_draft' }),
			error: null
		});
		rpc.mockResolvedValueOnce({
			data: { quote_id: quoteId, status: 'awaiting_response' },
			error: null
		});
		const from = fromQueue([{ data: { revision: 3 }, error: null }]);

		const response = await POST(event({ to_stage: 'quote_awaiting_response' }, { rpc, from }));

		expect(rpc).toHaveBeenNthCalledWith(2, 'publish_quote', {
			target_quote_id: quoteId,
			expected_revision: 3
		});
		expect(response.status).toBe(200);
	});

	it('answers not-found when the quote has no draft to send', async () => {
		const rpc = vi.fn().mockResolvedValueOnce({
			data: gateResult({ request_id: null, quote_id: quoteId, from_stage: 'quote_draft' }),
			error: null
		});
		const from = fromQueue([{ data: null, error: null }]);

		const response = await POST(event({ to_stage: 'quote_awaiting_response' }, { rpc, from }));

		expect(response.status).toBe(404);
	});

	it('turns a publish_quote refusal into a form error', async () => {
		const rpc = vi.fn();
		rpc.mockResolvedValueOnce({
			data: gateResult({ request_id: null, quote_id: quoteId, from_stage: 'quote_draft' }),
			error: null
		});
		rpc.mockResolvedValueOnce({
			data: null,
			error: { code: '23514', message: 'Only a draft quote can be sent.' }
		});
		const from = fromQueue([{ data: { revision: 1 }, error: null }]);

		const response = await POST(event({ to_stage: 'quote_awaiting_response' }, { rpc, from }));

		expect(response.status).toBe(422);
	});

	it('converts a request dragged onto Draft, with a fingerprint of its own', async () => {
		const rpc = vi.fn();
		rpc.mockResolvedValueOnce({ data: gateResult(), error: null });
		rpc.mockResolvedValueOnce({
			data: { applied: true, quote_id: quoteId, quote_number: 1042, status: 'draft' },
			error: null
		});

		const response = await POST(
			event({ to_stage: 'quote_draft', idempotency_key: idempotencyKey }, { rpc })
		);

		expect(rpc).toHaveBeenNthCalledWith(2, 'convert_request_to_quote', {
			target_request_id: requestId,
			idempotency_key: idempotencyKey,
			// Never the Request page's `rev-N:lines-N`: nobody was looking at pricing when they dragged.
			request_hash: `board-drag:${opportunityId}`
		});
		expect(response.status).toBe(200);
		expect((await response.json()).quote.quote_number).toBe(1042);
	});

	it('converts from Assessment completed as well', async () => {
		const rpc = vi.fn();
		rpc.mockResolvedValueOnce({
			data: gateResult({ from_stage: 'assessment_completed' }),
			error: null
		});
		rpc.mockResolvedValueOnce({
			data: { applied: true, quote_id: quoteId, quote_number: 7, status: 'draft' },
			error: null
		});

		const response = await POST(
			event({ to_stage: 'quote_draft', idempotency_key: idempotencyKey }, { rpc })
		);

		expect(response.status).toBe(200);
	});

	// The collapsed Assessment column holds convertible and non-convertible cards side by side, so Draft
	// is refused card by card. A scheduled visit has no path there at all -- the gate refuses it before
	// this route ever reaches the conversion command.
	it('refuses to convert a card whose assessment is already booked', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'That card cannot be moved there.' }
		});

		const response = await POST(
			event({ to_stage: 'quote_draft', idempotency_key: idempotencyKey }, { rpc })
		);

		expect(response.status).toBe(422);
		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('will not convert without a key it can be retried with', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: gateResult(), error: null });

		const response = await POST(event({ to_stage: 'quote_draft' }, { rpc }));

		expect(response.status).toBe(422);
		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('reports a request that already became a quote as a conflict, not a failure', async () => {
		const rpc = vi.fn();
		rpc.mockResolvedValueOnce({ data: gateResult(), error: null });
		rpc.mockResolvedValueOnce({
			data: null,
			error: { code: 'P0409', message: 'This request already has a quote.' }
		});

		const response = await POST(
			event({ to_stage: 'quote_draft', idempotency_key: idempotencyKey }, { rpc })
		);

		expect(response.status).toBe(409);
		expect((await response.json()).reason).toBe('already_converted');
	});

	it('keeps the response out of any shared cache', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: gateResult(), error: null });
		const from = fromQueue([
			{ data: null, error: null },
			{ data: null, error: null }
		]);

		const response = await POST(event({ to_stage: 'assessment_unscheduled' }, { rpc, from }));
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});
