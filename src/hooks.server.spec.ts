import { createHmac } from 'node:crypto';
import { readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { isRedirect, type RequestEvent } from '@sveltejs/kit';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { canUseJafarPath } from '$lib/jafar/team-access';
import { handle } from './hooks.server';

const SECRET = 'test-session-secret';
const OWNER_EMAIL = 'owner@example.com';
const LIVE_SESSION_ID = '11111111-1111-4111-8111-111111111111';
const UNKNOWN_SESSION_ID = '22222222-2222-4222-8222-222222222222';
const REVOKED_SESSION_ID = '33333333-3333-4333-8333-333333333333';
const SALES_SESSION_ID = '44444444-4444-4444-8444-444444444444';
const SUPPORT_SESSION_ID = '55555555-5555-4555-8555-555555555555';
const REMOVED_TEAMMATE_SESSION_ID = '66666666-6666-4666-8666-666666666666';
const SALES_MEMBER_ID = '77777777-7777-4777-8777-777777777777';
const SALES_EMAIL = 'sam@uplift.example';
const ADJUSTED_SALES_SESSION_ID = '88888888-8888-4888-8888-888888888888';

vi.mock('@supabase/ssr', () => ({
	createServerClient: () => ({ auth: { getClaims: async () => ({ data: null }) } })
}));
vi.mock('$lib/config/public', () => ({ getPublicEnv: () => ({}) }));
vi.mock('$lib/server/security/rate-limit', () => ({ enforceApiRateLimit: async () => null }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/env', () => ({
	getServerEnv: () => ({
		SUPER_ADMIN_EMAIL: 'owner@example.com',
		SUPER_ADMIN_PASSWORD_HASH: 'hash',
		SESSION_SECRET: 'test-session-secret'
	})
}));

type RegistryRow = {
	owner_email: string;
	expires_at: string;
	revoked_at: string | null;
	team_member_id: string | null;
	platform_team_members: {
		email: string;
		role: string;
		status: string;
		full_name: string | null;
		area_adjustments: unknown;
		action_grants: string[];
	} | null;
};
const inAnHour = new Date(Date.now() + 3_600_000).toISOString();
const ownerRow = { team_member_id: null, platform_team_members: null };
const teammateRow = (
	email: string,
	role: string,
	status: string,
	memberId = SALES_MEMBER_ID,
	adjustments: { area_adjustments?: unknown; action_grants?: string[] } = {}
) => ({
	owner_email: email,
	expires_at: inAnHour,
	revoked_at: null,
	team_member_id: memberId,
	platform_team_members: {
		email,
		role,
		status,
		full_name: 'Sam Seller',
		area_adjustments: adjustments.area_adjustments ?? {},
		action_grants: adjustments.action_grants ?? []
	}
});

const registry: Record<string, RegistryRow> = {
	[LIVE_SESSION_ID]: {
		owner_email: OWNER_EMAIL,
		expires_at: inAnHour,
		revoked_at: null,
		...ownerRow
	},
	[REVOKED_SESSION_ID]: {
		owner_email: OWNER_EMAIL,
		expires_at: inAnHour,
		revoked_at: new Date().toISOString(),
		...ownerRow
	},
	[SALES_SESSION_ID]: teammateRow(SALES_EMAIL, 'sales', 'active'),
	[SUPPORT_SESSION_ID]: teammateRow('sue@uplift.example', 'support', 'active'),
	// Jafar let this Sales teammate confirm payments and closed Leads for them.
	[ADJUSTED_SALES_SESSION_ID]: teammateRow(
		'pat@uplift.example',
		'sales',
		'active',
		'99999999-9999-4999-8999-999999999999',
		{ area_adjustments: { leads: 'none' }, action_grants: ['payments'] }
	),
	// Removed a moment ago: the session row is not revoked yet, but the teammate is no longer active.
	[REMOVED_TEAMMATE_SESSION_ID]: teammateRow('rem@uplift.example', 'sales', 'removed')
};
const registryLookups = vi.fn();

function signedCookie(sessionId: string) {
	return `${sessionId}.${createHmac('sha256', SECRET).update(sessionId).digest('base64url')}`;
}

const SAMPLE_ID = '00000000-0000-4000-8000-000000000000';

/**
 * Every page and API endpoint under `/jafar` and `/api/jafar`, read from the route folders on disk, so a
 * route added later is covered without anyone remembering to add it here.
 */
function jafarRoutes() {
	const routesRoot = join(process.cwd(), 'src/routes');
	const found: { pathname: string; kind: 'page' | 'api' }[] = [];

	function walk(dir: string) {
		const entries = readdirSync(dir, { withFileTypes: true });
		const files = entries.filter((entry) => entry.isFile()).map((entry) => entry.name);
		const isPage = files.includes('+page.svelte') || files.includes('+page.server.ts');
		const isApi = files.includes('+server.ts');
		if (isPage || isApi) {
			const segments = relative(routesRoot, dir)
				.split('/')
				.filter((segment) => !/^\(.+\)$/.test(segment))
				.map((segment) =>
					segment.startsWith('[...') ? 'a/b' : segment.startsWith('[') ? SAMPLE_ID : segment
				);
			found.push({ pathname: `/${segments.join('/')}`, kind: isApi ? 'api' : 'page' });
		}
		for (const entry of entries) if (entry.isDirectory()) walk(join(dir, entry.name));
	}

	walk(join(routesRoot, 'jafar'));
	walk(join(routesRoot, 'api/jafar'));
	return found;
}

const OPEN_ROUTES = new Set([
	'/jafar/login',
	'/api/jafar/session',
	'/jafar/join',
	'/jafar/forgot-password',
	'/jafar/reset-password',
	'/api/jafar/account/join',
	'/api/jafar/account/password-reset',
	'/api/jafar/account/password-reset/complete'
]);
const isSecretAuthenticated = (pathname: string) => pathname.startsWith('/api/jafar/internal/');

function cookieJar(sessionCookie?: string) {
	const store = new Map<string, string>(sessionCookie ? [['jafar_session', sessionCookie]] : []);
	return {
		get: (name: string) => store.get(name),
		getAll: () => [...store].map(([name, value]) => ({ name, value })),
		set: (name: string, value: string) => void store.set(name, value),
		delete: (name: string) => void store.delete(name)
	};
}

async function visit(pathname: string, sessionCookie?: string, method = 'GET') {
	const event = {
		url: new URL(`https://app.example.com${pathname}`),
		request: new Request(`https://app.example.com${pathname}`, { method }),
		cookies: cookieJar(sessionCookie),
		locals: {}
	} as unknown as RequestEvent;
	const resolve = vi.fn(async () => new Response('route ran'));

	try {
		const response = await handle({ event, resolve });
		return { response, routeRan: resolve.mock.calls.length > 0, event };
	} catch (thrown) {
		if (isRedirect(thrown)) return { redirect: thrown, routeRan: false, event };
		throw thrown;
	}
}

const routes = jafarRoutes();
const guarded = routes.filter(
	({ pathname }) => !OPEN_ROUTES.has(pathname) && !isSecretAuthenticated(pathname)
);

describe('the Jafar Panel front door', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: () => ({
				select: () => ({
					eq: (_column: string, id: string) => ({
						maybeSingle: async () => {
							registryLookups(id);
							return { data: registry[id] ?? null, error: null };
						}
					})
				})
			})
		} as never);
	});

	it('finds the real route folders', () => {
		expect(guarded.filter((route) => route.kind === 'api').length).toBeGreaterThan(100);
		expect(guarded.filter((route) => route.kind === 'page').length).toBeGreaterThan(10);
		expect(guarded.some((route) => route.pathname === '/jafar')).toBe(true);
	});

	const visitors = [
		['a logged-out visitor', undefined],
		['a forged session cookie', `${LIVE_SESSION_ID}.not-the-real-signature`],
		['a signed cookie for a session that does not exist', signedCookie(UNKNOWN_SESSION_ID)],
		['a signed-out session', signedCookie(REVOKED_SESSION_ID)],
		['a removed teammate', signedCookie(REMOVED_TEAMMATE_SESSION_ID)]
	] as const;

	describe.each(visitors)('%s', (_label, cookie) => {
		it.each(guarded.filter((route) => route.kind === 'api').map((route) => route.pathname))(
			'is refused by %s',
			async (pathname) => {
				const result = await visit(pathname, cookie);
				expect(result.routeRan).toBe(false);
				expect(result.response?.status).toBe(401);
			}
		);

		it.each(guarded.filter((route) => route.kind === 'page').map((route) => route.pathname))(
			'is sent to sign in from %s',
			async (pathname) => {
				const result = await visit(pathname, cookie);
				expect(result.routeRan).toBe(false);
				expect(result.redirect?.status).toBe(303);
				expect(result.redirect?.location).toBe('/jafar/login');
			}
		);
	});

	it('lets the signed-in owner through, checking the session registry only once per request', async () => {
		for (const { pathname } of guarded) {
			registryLookups.mockClear();
			const result = await visit(pathname, signedCookie(LIVE_SESSION_ID));
			expect(result.routeRan, pathname).toBe(true);
			expect(await result.event.locals.ownerSession).toEqual({
				email: OWNER_EMAIL,
				sessionId: LIVE_SESSION_ID,
				role: null,
				access: null,
				memberId: null,
				name: null
			});
			expect(registryLookups).toHaveBeenCalledTimes(1);
		}
	});

	it('leaves sign-in and the database-triggered jobs to their own checks', async () => {
		const open = routes.filter(
			({ pathname }) => OPEN_ROUTES.has(pathname) || isSecretAuthenticated(pathname)
		);
		expect(open.map((route) => route.pathname).sort()).toEqual(
			[
				'/api/jafar/internal/closure-cron',
				'/api/jafar/internal/sms-price-reconciliation-cron',
				'/api/jafar/internal/sms-usage-reconciliation-cron',
				'/api/jafar/internal/trust-hub-status-cron',
				'/api/jafar/session',
				'/jafar/login',
				'/jafar/join',
				'/jafar/forgot-password',
				'/jafar/reset-password',
				'/api/jafar/account/join',
				'/api/jafar/account/password-reset',
				'/api/jafar/account/password-reset/complete'
			].sort()
		);
		for (const { pathname } of open) {
			expect((await visit(pathname)).routeRan, pathname).toBe(true);
		}
	});

	describe('a Sales teammate', () => {
		const cookie = signedCookie(SALES_SESSION_ID);

		it('is known by name and role', async () => {
			const result = await visit('/jafar/prospects', cookie);
			expect(result.routeRan).toBe(true);
			expect(await result.event.locals.ownerSession).toEqual({
				email: SALES_EMAIL,
				sessionId: SALES_SESSION_ID,
				role: 'sales',
				access: { areas: { leads: 'work', applications: 'look' }, actions: [] },
				memberId: SALES_MEMBER_ID,
				name: 'Sam Seller'
			});
		});

		it('reaches exactly the routes its role opens, for reading', async () => {
			for (const { pathname, kind } of guarded) {
				const result = await visit(pathname, cookie);
				const allowed = canUseJafarPath({ role: 'sales' }, pathname, 'GET');
				expect(result.routeRan, pathname).toBe(allowed);
				if (allowed) continue;
				if (kind === 'api') expect(result.response?.status, pathname).toBe(403);
				else expect(result.redirect?.location, pathname).toBe('/jafar/leads');
			}
		});

		it('only looks at Applications: confirming a payment is refused', async () => {
			const result = await visit(
				`/api/jafar/prospects/${SAMPLE_ID}/confirm-payment`,
				cookie,
				'POST'
			);
			expect(result.routeRan).toBe(false);
			expect(result.response?.status).toBe(403);
		});

		it('cannot manage the team or step up as the owner', async () => {
			for (const [pathname, method] of [
				['/api/jafar/team', 'GET'],
				['/api/jafar/team', 'POST'],
				[`/api/jafar/team/${SAMPLE_ID}`, 'DELETE'],
				['/api/jafar/reconfirm', 'POST']
			] as const) {
				const result = await visit(pathname, cookie, method);
				expect(result.routeRan, `${method} ${pathname}`).toBe(false);
				expect(result.response?.status).toBe(403);
			}
		});

		it('lands on Leads from the Overview and from Settings', async () => {
			for (const pathname of ['/jafar', '/jafar/settings', '/jafar/settings/team']) {
				expect((await visit(pathname, cookie)).redirect?.location, pathname).toBe('/jafar/leads');
			}
		});
	});

	describe('a Sales teammate with individual access', () => {
		const cookie = signedCookie(ADJUSTED_SALES_SESSION_ID);

		it('confirms a payment Jafar allowed, but still cannot set up the account', async () => {
			const confirm = await visit(`/api/jafar/prospects/${SAMPLE_ID}/confirm-payment`, cookie, 'POST');
			expect(confirm.routeRan).toBe(true);
			const provision = await visit(`/api/jafar/prospects/${SAMPLE_ID}/provision`, cookie, 'POST');
			expect(provision.routeRan).toBe(false);
			expect(provision.response?.status).toBe(403);
		});

		it('loses the payment action on the next request once Jafar turns it off', async () => {
			const row = registry[ADJUSTED_SALES_SESSION_ID].platform_team_members!;
			const granted = row.action_grants;
			row.action_grants = [];
			try {
				const result = await visit(
					`/api/jafar/prospects/${SAMPLE_ID}/confirm-payment`,
					cookie,
					'POST'
				);
				expect(result.routeRan).toBe(false);
				expect(result.response?.status).toBe(403);
			} finally {
				row.action_grants = granted;
			}
		});

		it('no longer reaches the Leads Jafar closed, and lands on Applications', async () => {
			const api = await visit('/api/jafar/leads', cookie);
			expect(api.routeRan).toBe(false);
			expect(api.response?.status).toBe(403);
			expect((await visit('/jafar/leads', cookie)).redirect?.location).toBe('/jafar/prospects');
		});
	});

	describe('a Support teammate', () => {
		const cookie = signedCookie(SUPPORT_SESSION_ID);

		it('replies in the Support inbox', async () => {
			const result = await visit(
				`/api/jafar/support/threads/${SAMPLE_ID}/messages`,
				cookie,
				'POST'
			);
			expect(result.routeRan).toBe(true);
		});

		it('cannot change who Support replies appear from', async () => {
			const result = await visit('/api/jafar/support/settings', cookie, 'PATCH');
			expect(result.routeRan).toBe(false);
			expect(result.response?.status).toBe(403);
		});
	});

	it('does not touch the contractor app', async () => {
		for (const pathname of ['/dashboard', '/api/clients', '/jafarish', '/api/jafarish']) {
			expect((await visit(pathname)).routeRan, pathname).toBe(true);
		}
		expect(registryLookups).not.toHaveBeenCalled();
	});
});
