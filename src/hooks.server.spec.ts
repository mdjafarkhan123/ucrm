import { createHmac } from 'node:crypto';
import { readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { isRedirect, type RequestEvent } from '@sveltejs/kit';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { handle } from './hooks.server';

const SECRET = 'test-session-secret';
const OWNER_EMAIL = 'owner@example.com';
const LIVE_SESSION_ID = '11111111-1111-4111-8111-111111111111';
const UNKNOWN_SESSION_ID = '22222222-2222-4222-8222-222222222222';
const REVOKED_SESSION_ID = '33333333-3333-4333-8333-333333333333';

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

const registry: Record<
	string,
	{ owner_email: string; expires_at: string; revoked_at: string | null }
> = {
	[LIVE_SESSION_ID]: {
		owner_email: OWNER_EMAIL,
		expires_at: new Date(Date.now() + 3_600_000).toISOString(),
		revoked_at: null
	},
	[REVOKED_SESSION_ID]: {
		owner_email: OWNER_EMAIL,
		expires_at: new Date(Date.now() + 3_600_000).toISOString(),
		revoked_at: new Date().toISOString()
	}
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

const OPEN_ROUTES = new Set(['/jafar/login', '/api/jafar/session']);
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

async function visit(pathname: string, sessionCookie?: string) {
	const event = {
		url: new URL(`https://app.example.com${pathname}`),
		request: new Request(`https://app.example.com${pathname}`),
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
		['a signed-out session', signedCookie(REVOKED_SESSION_ID)]
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
				sessionId: LIVE_SESSION_ID
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
				'/jafar/login'
			].sort()
		);
		for (const { pathname } of open) {
			expect((await visit(pathname)).routeRan, pathname).toBe(true);
		}
	});

	it('does not touch the contractor app', async () => {
		for (const pathname of ['/dashboard', '/api/clients', '/jafarish', '/api/jafarish']) {
			expect((await visit(pathname)).routeRan, pathname).toBe(true);
		}
		expect(registryLookups).not.toHaveBeenCalled();
	});
});
