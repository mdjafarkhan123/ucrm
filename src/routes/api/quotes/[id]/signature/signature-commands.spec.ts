import { beforeEach, describe, expect, it, vi } from 'vitest';
import { requireOrganizationPermission } from '$lib/server/access/permission';

// The staff pad: collecting a signature in person. It approves the quote, so it is guarded by the
// permission to answer one, and a stored picture never outlives a refused command.

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const putObject = vi.fn(() => Promise.resolve());
const deleteObject = vi.fn(() => Promise.resolve());
vi.mock('$lib/server/storage/r2', async () => {
	const actual =
		await vi.importActual<typeof import('$lib/server/storage/r2')>('$lib/server/storage/r2');
	return { ...actual, putObject, deleteObject };
});

const { POST: collect } = await import('./+server');

const mockedRequire = vi.mocked(requireOrganizationPermission);
const quoteId = '00000000-0000-4000-8000-000000000091';

const PNG =
	'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

function commandEvent(
	body: unknown,
	rpcResult: unknown = { data: { status: 'approved', signed: true }, error: null }
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: quoteId },
		request: new Request(`http://localhost/api/quotes/${quoteId}/signature`, {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof collect>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(context({ 'quotes.record_decision': true }));
});

describe('collecting a signature in person', () => {
	it('asks for the permission to answer a quote', async () => {
		await collect(commandEvent({ name: 'Dana Reed', method: 'in_person', image: PNG }));

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.record_decision');
	});

	it('stores the drawing under the quote and sends only its key on', async () => {
		const event = commandEvent({ name: 'Dana Reed', method: 'in_person', image: PNG });
		await collect(event);

		const [key] = putObject.mock.calls[0] as unknown as [string];
		expect(key).toContain(`org-1/quote-signatures/${quoteId}/`);

		const [, args] = event.__rpc.mock.calls[0] as unknown as [string, Record<string, unknown>];
		expect(args.signer_name).toBe('Dana Reed');
		expect(args.signature_object_key).toBe(key);
		expect(JSON.stringify(args)).not.toContain('base64');
	});

	it('refuses a picture that is not a PNG before storing anything', async () => {
		const event = commandEvent({
			name: 'Dana Reed',
			method: 'in_person',
			image: 'data:image/png;base64,QUJDREVGR0hJSktMTU5PUFFSU1Q='
		});
		const response = await collect(event);

		expect(response.status).toBe(422);
		expect(putObject).not.toHaveBeenCalled();
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('refuses an in-person signature with nothing drawn', async () => {
		const response = await collect(commandEvent({ name: 'Dana Reed', method: 'in_person' }));

		expect(response.status).toBe(422);
		expect(putObject).not.toHaveBeenCalled();
	});

	it('deletes the picture when the quote cannot be answered', async () => {
		const event = commandEvent(
			{ name: 'Dana Reed', method: 'in_person', image: PNG },
			{
				data: null,
				error: { code: 'P0409', message: 'This quote is not waiting for an answer.' }
			}
		);

		const response = await collect(event);

		expect(response.status).toBe(409);
		expect(deleteObject).toHaveBeenCalledTimes(1);
	});

	it('turns a member without the permission away without touching storage', async () => {
		mockedRequire.mockResolvedValue({
			response: new Response(null, { status: 403 })
		} as never);

		const response = await collect(
			commandEvent({ name: 'Dana Reed', method: 'in_person', image: PNG })
		);

		expect(response.status).toBe(403);
		expect(putObject).not.toHaveBeenCalled();
	});
});
