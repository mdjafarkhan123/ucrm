import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './[id]/signatures/+server';
import { GET as DOCUMENT } from './[id]/signatures/[signatureId]/document/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { putObject, deleteObject } from '$lib/server/storage/r2';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

// The storage side is the one part of collecting a signature that leaves the process. Both halves are
// stubbed so the tests can watch the order the route does things in: store the picture, then ask the
// database, then throw the picture away if the database said no.
vi.mock('$lib/server/storage/r2', async () => {
	const actual =
		await vi.importActual<typeof import('$lib/server/storage/r2')>('$lib/server/storage/r2');
	return { ...actual, putObject: vi.fn(async () => {}), deleteObject: vi.fn(async () => {}) };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedPut = vi.mocked(putObject);
const mockedDelete = vi.mocked(deleteObject);

const jobId = '00000000-0000-4000-8000-000000000091';
const signatureId = '00000000-0000-4000-8000-000000000092';
const visitId = '00000000-0000-4000-8000-000000000093';

// A real one-pixel PNG. The route checks the file's own first eight bytes, so a made-up string would be
// refused for the right reason but the wrong test.
const PNG_DATA_URL =
	'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

function context() {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions: { 'jobs.view': true }, features: { 'core.jobs': true } }
	} as never;
}

function collectEvent(
	body: unknown,
	rpcResult: unknown = { data: { id: signatureId }, error: null }
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: jobId },
		getClientAddress: () => '203.0.113.42',
		request: new Request(`http://localhost/api/jobs/${jobId}/signatures`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', 'user-agent': 'Test Browser' },
			body: JSON.stringify(body)
		}),
		locals: { supabase: { rpc, from: vi.fn() } },
		__rpc: rpc
	} as unknown as Parameters<typeof POST>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const VALID_BODY = {
	signature_type: 'work_completion',
	signer_name: 'Dana Reed',
	statement: 'I confirm the work is complete.',
	method: 'typed'
};

describe('collecting a job signature', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context());
	});

	it('returns the permission check response without touching anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = collectEvent(VALID_BODY);

		const response = await POST(target);

		expect(response.status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('answers a body of the wrong shape with the fields that were wrong', async () => {
		const target = collectEvent({ ...VALID_BODY, signer_name: '' });

		const response = await POST(target);
		const body = await response.json();

		expect(response.status).toBe(422);
		expect(body.field_errors.signer_name).toBeTruthy();
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('refuses a typed signature that arrives with a drawing', async () => {
		const target = collectEvent({ ...VALID_BODY, image: PNG_DATA_URL });

		const response = await POST(target);
		const body = await response.json();

		expect(response.status).toBe(422);
		expect(body.field_errors.image).toBeTruthy();
		expect(mockedPut).not.toHaveBeenCalled();
	});

	it('stores the drawing before the command runs, never during it', async () => {
		const target = collectEvent({ ...VALID_BODY, method: 'drawn', image: PNG_DATA_URL });

		await POST(target);
		const [key, , mime] = mockedPut.mock.calls[0];

		expect(String(key)).toContain('org-1/job-signatures/');
		expect(mime).toBe('image/png');
		expect(mockedPut.mock.invocationCallOrder[0]).toBeLessThan(
			target.__rpc.mock.invocationCallOrder[0]
		);
		expect(mockedDelete).not.toHaveBeenCalled();
	});

	it('throws the stored drawing away when the command refuses', async () => {
		const target = collectEvent(
			{ ...VALID_BODY, method: 'drawn', image: PNG_DATA_URL },
			{ data: null, error: { code: '42501', message: 'You do not have access to this job.' } }
		);

		const response = await POST(target);

		expect(response.status).toBe(404);
		expect(mockedDelete).toHaveBeenCalledWith(mockedPut.mock.calls[0][0]);
	});

	it('sends what was signed to the command, with the visit as context', async () => {
		const target = collectEvent({ ...VALID_BODY, signer_role: 'Homeowner', visit_id: visitId });

		await POST(target);
		const [name, args] = target.__rpc.mock.calls[0] as [string, Record<string, unknown>];

		expect(name).toBe('collect_job_signature');
		expect(args.target_organization_id).toBe('org-1');
		expect(args.target_job_id).toBe(jobId);
		expect(args.new_signature_type).toBe('work_completion');
		expect(args.new_signer_role).toBe('Homeowner');
		expect(args.target_visit_id).toBe(visitId);
		expect(args.new_image_object_key).toBeUndefined();
	});

	it('keeps only a truncated address and a short user agent as evidence', async () => {
		const target = collectEvent(VALID_BODY);

		await POST(target);
		const [, args] = target.__rpc.mock.calls[0] as [string, Record<string, unknown>];

		expect(args.supplied_evidence).toEqual({
			ip_prefix: '203.0.113.0',
			user_agent: 'Test Browser'
		});
	});
});

function listEvent(rpcResult: unknown, profiles: unknown = { data: [], error: null }) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	const chain = {
		select: vi.fn(() => chain),
		in: vi.fn(() => Promise.resolve(profiles))
	} as Record<string, unknown>;
	return {
		params: { id: jobId },
		locals: { supabase: { rpc, from: vi.fn(() => chain) } },
		__rpc: rpc
	} as unknown as Parameters<typeof GET>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

describe('reading a job signatures', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context());
	});

	it('returns the permission check response without reading anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = listEvent({ data: { signatures: [], can_collect: true }, error: null });

		const response = await GET(target);

		expect(response.status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('names the collector rather than showing an id', async () => {
		const target = listEvent(
			{
				data: {
					signatures: [{ id: signatureId, collected_by: 'user-9', is_stale: false }],
					can_collect: true
				},
				error: null
			},
			{ data: [{ id: 'user-9', full_name: 'Priya Nair' }], error: null }
		);

		const body = await (await GET(target)).json();

		expect(body.signatures[0].collected_by_name).toBe('Priya Nair');
		expect(body.can_collect).toBe(true);
	});

	it('shows no name when the collector has since gone', async () => {
		const target = listEvent({
			data: {
				signatures: [{ id: signatureId, collected_by: null, is_stale: true }],
				can_collect: false
			},
			error: null
		});

		const body = await (await GET(target)).json();

		expect(body.signatures[0].collected_by_name).toBeNull();
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('turns a refusal into a not-found rather than leaking which job it was', async () => {
		const target = listEvent({
			data: null,
			error: { code: '42501', message: 'You do not have access to this job.' }
		});

		expect((await GET(target)).status).toBe(404);
	});
});

function documentEvent(rpcResult: unknown) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: jobId, signatureId },
		locals: { supabase: { rpc, from: vi.fn() } },
		__rpc: rpc
	} as unknown as Parameters<typeof DOCUMENT>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

describe('reading what was signed', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context());
	});

	it('returns the frozen document the command shaped', async () => {
		const target = documentEvent({
			data: { id: signatureId, job_id: jobId, document: { lines: [] }, is_stale: false },
			error: null
		});

		const body = await (await DOCUMENT(target)).json();

		expect(body.document.lines).toEqual([]);
	});

	it('refuses a signature that belongs to a different job', async () => {
		const target = documentEvent({
			data: { id: signatureId, job_id: 'another-job', document: {} },
			error: null
		});

		expect((await DOCUMENT(target)).status).toBe(404);
	});
});
