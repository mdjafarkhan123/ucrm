import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const quoteId = '00000000-0000-4000-8000-000000000061';
const versionId = '00000000-0000-4000-8000-000000000062';
const publishedVersionId = '00000000-0000-4000-8000-000000000064';

// PostgREST's builder is a chain that resolves either on await or on maybeSingle(), so the stub answers
// the same result whichever way the route finishes the call.
function builder(result: unknown) {
	const selects: string[] = [];
	const chain: Record<string | symbol, unknown> = new Proxy(
		{},
		{
			get(_target, property) {
				if (property === '__selects') return selects;
				if (property === 'maybeSingle' || property === 'single')
					return () => Promise.resolve(result);
				if (property === 'then')
					return (...args: unknown[]) =>
						(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(
							...args
						);
				return (...args: unknown[]) => {
					if (property === 'select') selects.push(String(args[0]));
					return chain;
				};
			}
		}
	);
	return chain;
}

const quote = {
	id: quoteId,
	quote_number: 7,
	title: 'Gutter clearing',
	status: 'draft',
	currency_code: 'USD',
	draft_version_id: versionId,
	current_published_version_id: null,
	client_id: '00000000-0000-4000-8000-000000000063',
	client: {
		id: '00000000-0000-4000-8000-000000000063',
		display_name: 'Alex Smith',
		company_name: null
	}
};
const version = { id: versionId, version_number: 0, status: 'draft', subtotal_minor: 45000 };
const publishedVersion = {
	id: publishedVersionId,
	version_number: 2,
	status: 'published',
	subtotal_minor: 39000
};
const lines = [
	{
		id: 'line-1',
		position: 0,
		name: 'Gutter clearing',
		quantity: 2,
		unit_price_minor: 12500,
		unit_cost_minor: 4000,
		line_total_minor: 25000,
		line_cost_total_minor: 8000
	}
];

function event(tables: Record<string, unknown> = {}) {
	const built: Record<string, { __selects: string[] }> = {};
	const from = vi.fn((table: string) => {
		const result =
			table === 'quotes'
				? (tables.quotes ?? { data: quote, error: null })
				: table === 'quote_versions'
					? (tables.quote_versions ?? { data: [version, publishedVersion], error: null })
					: table === 'quote_version_lines'
						? (tables.quote_version_lines ?? { data: lines, error: null })
						: (tables.client_contact_methods ?? {
								data: [
									{ kind: 'email', value: 'hello@example.com', is_primary: true },
									{ kind: 'phone', value: '+15555550100', is_primary: true }
								],
								error: null
							});
		const chain = builder(result);
		built[table] = chain as unknown as { __selects: string[] };
		return chain;
	});
	return {
		params: { id: quoteId },
		locals: {
			supabase: {
				from,
				rpc: vi.fn().mockResolvedValue({ data: false, error: null })
			}
		},
		__built: built
	} as unknown as Parameters<typeof GET>[0] & {
		__built: Record<string, { __selects: string[] }>;
	};
}

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

describe('quote detail API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(
			context({
				'quotes.view': true,
				'quotes.view_price': true,
				'quotes.view_cost': true,
				'quotes.edit': true,
				'quotes.send': true,
				'conversations.send': true
			})
		);
	});

	it('returns the permission check response without reading anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = event();

		const response = await GET(target);

		expect(response.status).toBe(403);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('returns the quote, its draft, and its lines with every number for a full-access member', async () => {
		const response = await GET(event());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.quote.quote_number).toBe(7);
		expect(body.version.subtotal_minor).toBe(45000);
		expect(body.lines[0].unit_price_minor).toBe(12500);
		expect(body.lines[0].unit_cost_minor).toBe(4000);
		expect(body.can_see_price).toBe(true);
		expect(body.can_see_cost).toBe(true);
		expect(body.can_edit).toBe(true);
		expect(body.can_send).toBe(true);
		expect(body.can_send_email).toBe(true);
		expect(body.quote.client.email).toBe('hello@example.com');
	});

	it('withholds email sending when the member cannot send customer conversations', async () => {
		mockedRequire.mockResolvedValue(
			context({
				'quotes.view': true,
				'quotes.send': true,
				'conversations.send': false
			})
		);

		const body = await (await GET(event())).json();

		expect(body.can_send).toBe(true);
		expect(body.can_send_email).toBe(false);
	});

	it('leaves money off the rows and asks the gated reader for it instead', async () => {
		mockedRequire.mockResolvedValue(
			context({ 'quotes.view': true, 'quotes.view_price': true, 'quotes.view_cost': false })
		);
		const target = event();

		const body = await (await GET(target)).json();
		const lineSelect = target.__built.quote_version_lines.__selects[0];

		expect(lineSelect).not.toContain('unit_price_minor');
		expect(lineSelect).not.toContain('unit_cost_minor');
		expect(lineSelect).not.toContain('line_cost_total_minor');
		expect(target.__built.quote_versions.__selects[0]).not.toContain('subtotal_minor');
		// Cost is withheld by the reader itself, so the route asks the same question either way.
		expect(target.locals.supabase.rpc).toHaveBeenCalledWith('quote_line_money', {
			target_version_id: versionId
		});
		expect(body.can_see_cost).toBe(false);
	});

	it('does not even ask the money readers when the member may not see money at all', async () => {
		mockedRequire.mockResolvedValue(
			context({ 'quotes.view': true, 'quotes.view_price': false, 'quotes.view_cost': false })
		);
		const target = event();

		await GET(target);
		const lineSelect = target.__built.quote_version_lines.__selects[0];
		const asked = (target.locals.supabase.rpc as ReturnType<typeof vi.fn>).mock.calls.map(
			(call) => call[0]
		);

		expect(lineSelect).toContain('name');
		expect(asked).not.toContain('quote_version_money');
		expect(asked).not.toContain('quote_line_money');
	});

	it('answers not-found for a quote in another organization', async () => {
		const response = await GET(event({ quotes: { data: null, error: null } }));

		expect(response.status).toBe(404);
	});

	it('answers with a null version when the quote has no draft yet', async () => {
		const response = await GET(
			event({ quotes: { data: { ...quote, draft_version_id: null }, error: null } })
		);
		const body = await response.json();

		expect(body.version).toBeNull();
		expect(body.published_version_number).toBeNull();
		expect(body.lines).toEqual([]);
	});

	it('reads the published version once the draft has been frozen away', async () => {
		const response = await GET(
			event({
				quotes: {
					data: {
						...quote,
						status: 'sent',
						draft_version_id: null,
						current_published_version_id: publishedVersionId
					},
					error: null
				}
			})
		);
		const body = await response.json();

		expect(body.version.id).toBe(publishedVersionId);
		expect(body.version.status).toBe('published');
		expect(body.published_version_number).toBe(2);
		expect(body.lines).toHaveLength(1);
	});

	it('shows the draft, not the published version, while both exist', async () => {
		const response = await GET(
			event({
				quotes: {
					data: { ...quote, current_published_version_id: publishedVersionId },
					error: null
				}
			})
		);
		const body = await response.json();

		expect(body.version.id).toBe(versionId);
		expect(body.version.status).toBe('draft');
		expect(body.published_version_number).toBe(2);
	});

	it('turns a read failure into a generic failure', async () => {
		const response = await GET(
			event({ quotes: { data: null, error: { code: '08000', message: 'connection failure' } } })
		);

		expect(response.status).toBe(500);
	});
});
