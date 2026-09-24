import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/communications/cloudfront', () => ({ getClickDomainEnv: vi.fn(() => null) }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function event(id = organizationId) {
	const url = `http://localhost/api/jafar/organizations/${id}/communications/marketing-domain`;
	return {
		params: { organizationId: id },
		request: new Request(url),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof GET>[0];
}

// Two independent query chains run in parallel: the marketing-domain list (terminates on `order`, awaited
// directly as a thenable) and the receiving-domain root suggestion (terminates on `maybeSingle`).
function clientWith(
	listOutcome: { data: unknown; error: unknown },
	rootOutcome: { data: unknown; error: unknown }
) {
	let call = 0;
	return {
		from: vi.fn(() => {
			call += 1;
			if (call === 1) {
				const builder: Record<string, unknown> = {};
				for (const method of ['select', 'eq', 'neq']) builder[method] = vi.fn(() => builder);
				builder.order = vi.fn(() => Promise.resolve(listOutcome));
				return builder;
			}
			const builder: Record<string, unknown> = {};
			for (const method of ['select', 'eq', 'neq']) builder[method] = vi.fn(() => builder);
			builder.maybeSingle = vi.fn(async () => rootOutcome);
			return builder;
		})
	};
}

describe('owner Marketing domain list boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('refuses a request without an owner session before any database access', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('returns the domain list plus a suggested root domain from the receiving domain', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
		const domains = [
			{ id: 'domain-1', domain_name: 'news.contractor.com', lifecycle_state: 'verified' }
		];
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWith(
				{ data: domains, error: null },
				{ data: { dns_zone: 'contractor.com' }, error: null }
			) as never
		);

		const response = await GET(event());

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			domains,
			suggested_root_domain: 'contractor.com',
			branded_links_configured: false
		});
	});

	it('reports a database failure on the domain list as a 500', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			clientWith(
				{ data: null, error: { message: 'db down' } },
				{ data: null, error: null }
			) as never
		);

		const response = await GET(event());

		expect(response.status).toBe(500);
	});
});
