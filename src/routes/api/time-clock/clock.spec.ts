import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as CLOCK_IN } from './clock-in/+server';
import { POST as CLOCK_OUT } from './clock-out/+server';
import { getOrganizationContext } from '$lib/server/auth/organization';

vi.mock('$lib/server/auth/organization', () => ({
	getOrganizationContext: vi.fn()
}));

const mockedContext = vi.mocked(getOrganizationContext);
const organizationId = '00000000-0000-4000-8000-0000000000aa';
const base = 'http://localhost/api/time-clock';

type AnyEvent = Parameters<typeof CLOCK_IN>[0] & Parameters<typeof CLOCK_OUT>[0];

function event(path: string, body?: string, result: { data?: unknown; error?: unknown } = {}) {
	const rpc = vi.fn().mockResolvedValue({ data: result.data ?? null, error: result.error ?? null });
	const url = `${base}/${path}`;
	const request = new Request(url, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body
	});
	return { url: new URL(url), request, locals: { supabase: { rpc } } } as unknown as AnyEvent;
}

// Time clock Part 3 (docs/time-clock-behavior-contract.md § Timers): Clock in and Clock out always mean the
// signed-in person's own day, so nothing in the request can name anyone else.
describe('the day clock', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedContext.mockResolvedValue({
			user: { id: 'user-1' },
			organization: { id: organizationId }
		} as never);
	});

	for (const [name, route, path, command] of [
		['Clock in', CLOCK_IN, 'clock-in', 'clock_in'],
		['Clock out', CLOCK_OUT, 'clock-out', 'clock_out']
	] as const) {
		describe(name, () => {
			it('needs a signed-in member', async () => {
				mockedContext.mockResolvedValue(null);
				const request = event(path, '{}');
				expect((await route(request)).status).toBe(401);
				expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
			});

			it('refuses a body that is not JSON or tries to name a person', async () => {
				const broken = event(path, '{nope');
				const named = event(path, JSON.stringify({ user_id: 'someone-else' }));
				expect((await route(broken)).status).toBe(422);
				expect((await route(named)).status).toBe(422);
				expect(named.locals.supabase.rpc).not.toHaveBeenCalled();
			});

			it('acts on the caller’s own day in their business and never caches the answer', async () => {
				const answer = { clocked_in: true };
				for (const body of ['{}', undefined]) {
					const request = event(path, body, { data: answer });
					const response = await route(request);
					expect(response.status).toBe(200);
					expect(await response.json()).toEqual(answer);
					expect(request.locals.supabase.rpc).toHaveBeenCalledWith(command, {
						target_organization_id: organizationId
					});
					expect(response.headers.get('cache-control')).toBe('no-store');
				}
			});

			it('passes on a timer over 24 hours as a rule the person can read', async () => {
				const message =
					'This timer has run for more than 24 hours, so it cannot be stopped as it is.';
				const response = await route(event(path, '{}', { error: { code: 'P0410', message } }));
				expect(response.status).toBe(409);
				expect(await response.json()).toEqual({ error: message, reason: 'locked' });
			});

			it('maps a database failure to a safe response', async () => {
				const response = await route(event(path, '{}', { error: { code: '08000' } }));
				expect(response.status).toBe(500);
			});
		});
	}

	it('tells someone who may not time their work that they cannot clock in', async () => {
		const response = await CLOCK_IN(event('clock-in', '{}', { error: { code: '42501' } }));
		expect(response.status).toBe(403);
		expect(await response.json()).toEqual({
			error: 'You do not have access to clock in.',
			reason: 'forbidden'
		});
	});
});
