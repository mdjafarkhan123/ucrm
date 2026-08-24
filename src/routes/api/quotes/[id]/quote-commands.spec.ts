import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH as patchDraft } from './draft/+server';
import { PATCH as patchLines } from './lines/+server';
import { POST as archive } from './archive/+server';
import { POST as restore } from './restore/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

// The cost guard has its own reads; the commands under test only care that it hands the lines on.
vi.mock('$lib/server/quotes/catalog-cost', () => ({
	withCatalogCost: vi.fn((_supabase, _org, _user, lines) => Promise.resolve(lines))
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const quoteId = '00000000-0000-4000-8000-000000000081';

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

function commandEvent(body: unknown, rpcResult: unknown = { data: { revision: 3 }, error: null }) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: quoteId },
		request: new Request(`http://localhost/api/quotes/${quoteId}`, {
			method: 'POST',
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
		// Four routes share this fake event, and each one's generated type names its own route id, so the
		// shape is handed over untyped rather than pretending to be one of them.
	} as unknown as Parameters<typeof patchDraft>[0] &
		Parameters<typeof patchLines>[0] &
		Parameters<typeof archive>[0] &
		Parameters<typeof restore>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const line = {
	name: 'Consumer unit',
	category: 'product',
	quantity: 1,
	unit_price_minor: 45000,
	unit_cost_minor: 20000
};

const stale = {
	data: null,
	error: {
		code: 'P0409',
		message: 'Someone else changed this quote while you were editing. Reload and try again.'
	}
};

describe('quote draft command', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.edit': true }));
	});

	it('refuses to run at all without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = commandEvent({ expected_revision: 1, title: 'Panel upgrade' });

		expect((await patchDraft(target)).status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('will not save without the revision it was shown', async () => {
		const target = commandEvent({ title: 'Panel upgrade' });

		expect((await patchDraft(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('sends the title and disclaimer through the one draft command', async () => {
		const target = commandEvent({
			expected_revision: 2,
			title: '  Panel upgrade  ',
			contract_disclaimer: null
		});

		await patchDraft(target);

		expect(target.__rpc).toHaveBeenCalledWith('update_quote_draft', {
			target_quote_id: quoteId,
			expected_revision: 2,
			new_title: 'Panel upgrade',
			new_disclaimer: null
		});
	});

	it('answers a stale save with a conflict the browser can reload on', async () => {
		const response = await patchDraft(
			commandEvent({ expected_revision: 1, title: 'Panel upgrade' }, stale)
		);
		const body = await response.json();

		expect(response.status).toBe(409);
		expect(body.reason).toBe('stale');
	});
});

describe('quote lines command', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.edit': true }));
	});

	it('replaces the whole set through the one command that owns the money', async () => {
		const target = commandEvent({ expected_revision: 4, lines: [line] });

		await patchLines(target);
		const [name, args] = target.__rpc.mock.calls[0] as [string, Record<string, unknown>];

		expect(name).toBe('replace_quote_version_lines');
		expect(args.expected_revision).toBe(4);
		expect((args.new_lines as unknown[]).length).toBe(1);
	});

	it('refuses a line with no quantity before the database sees it', async () => {
		const target = commandEvent({
			expected_revision: 4,
			lines: [{ ...line, quantity: 0 }]
		});

		expect((await patchLines(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('answers a stale save with a conflict', async () => {
		const response = await patchLines(commandEvent({ expected_revision: 1, lines: [] }, stale));

		expect(response.status).toBe(409);
	});
});

describe('quote archive and restore', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.edit': true }));
	});

	it('archives with no body at all', async () => {
		const target = commandEvent(undefined, {
			data: { applied: true, status: 'archived' },
			error: null
		});

		const response = await archive(target);

		expect(response.status).toBe(200);
		expect(target.__rpc).toHaveBeenCalledWith('archive_quote', {
			target_quote_id: quoteId,
			reason: null
		});
	});

	it('passes a reason on when one is given', async () => {
		const target = commandEvent(
			{ reason: 'Customer went with another contractor.' },
			{ data: { applied: true, status: 'archived' }, error: null }
		);

		await archive(target);

		expect(target.__rpc.mock.calls[0][1]).toMatchObject({
			reason: 'Customer went with another contractor.'
		});
	});

	it('turns a missing reason on an approved quote into something a person can read', async () => {
		const target = commandEvent(undefined, {
			data: null,
			error: { code: '23514', message: 'Give a reason for archiving an approved quote.' }
		});
		const response = await archive(target);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('reason');
	});

	it('restores without asking for anything', async () => {
		const target = commandEvent(undefined, {
			data: { applied: true, status: 'draft' },
			error: null
		});

		const response = await restore(target);

		expect(response.status).toBe(200);
		expect(target.__rpc).toHaveBeenCalledWith('restore_quote', { target_quote_id: quoteId });
	});
});
