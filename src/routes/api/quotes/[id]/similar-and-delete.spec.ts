import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as createSimilar } from './similar/+server';
import { DELETE as deleteQuote } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const quoteId = '00000000-0000-4000-8000-000000000081';

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

function commandEvent(rpcResult: unknown) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: quoteId },
		locals: { supabase: { rpc } },
		__rpc: rpc
		// Both routes share this fake event and each names its own generated route id, so the shape is
		// handed over untyped rather than pretending to be one of them.
	} as unknown as Parameters<typeof createSimilar>[0] &
		Parameters<typeof deleteQuote>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

describe('create similar quote', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.edit': true }));
	});

	it('refuses to run at all without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = commandEvent({ data: null, error: null });

		expect((await createSimilar(target)).status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('calls the one command with no body of its own', async () => {
		const target = commandEvent({
			data: { id: 'new-quote-id', quote_number: 35 },
			error: null
		});

		const response = await createSimilar(target);

		expect(target.__rpc).toHaveBeenCalledWith('create_similar_quote', {
			target_quote_id: quoteId
		});
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({ id: 'new-quote-id', quote_number: 35 });
	});

	it('answers a quote it may not touch the same way as one that does not exist', async () => {
		const response = await createSimilar(
			commandEvent({ data: null, error: { code: '42501', message: 'nope' } })
		);
		expect(response.status).toBe(404);
	});
});

describe('delete quote', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.edit': true }));
	});

	it('refuses to run at all without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = commandEvent({ data: null, error: null });

		expect((await deleteQuote(target)).status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('calls the one command with no body of its own', async () => {
		const target = commandEvent({ data: { deleted: true }, error: null });

		const response = await deleteQuote(target);

		expect(target.__rpc).toHaveBeenCalledWith('delete_quote', { target_quote_id: quoteId });
		expect(response.status).toBe(200);
	});

	it('turns a refusal on a non-draft, request-linked, or already-sent quote into a field error', async () => {
		const response = await deleteQuote(
			commandEvent({
				data: null,
				error: { code: '23514', message: 'Only an untouched draft can be deleted.' }
			})
		);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('untouched draft');
	});

	it('answers a quote it may not touch the same way as one that does not exist', async () => {
		const response = await deleteQuote(
			commandEvent({ data: null, error: { code: '42501', message: 'nope' } })
		);
		expect(response.status).toBe(404);
	});
});
