import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as SUMMARY } from './+server';
import { GET as ENTRIES } from './entries/+server';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { permissionIsEnabled, resolveOrganizationAccess } from '$lib/server/access/effective';

vi.mock('$lib/server/auth/organization', () => ({
	getOrganizationContext: vi.fn()
}));

vi.mock('$lib/server/access/effective', () => ({
	resolveOrganizationAccess: vi.fn(),
	permissionIsEnabled: vi.fn()
}));

const mockedContext = vi.mocked(getOrganizationContext);
const mockedAccess = vi.mocked(resolveOrganizationAccess);
const mockedPlan = vi.mocked(permissionIsEnabled);

const organizationId = '00000000-0000-4000-8000-0000000000aa';
const me = '00000000-0000-4000-8000-000000000001';
const teammate = '00000000-0000-4000-8000-000000000002';

type AnyEvent = Parameters<typeof SUMMARY>[0] & Parameters<typeof ENTRIES>[0];

function event(path: string, result: { data?: unknown; error?: unknown } = {}) {
	const rpc = vi.fn().mockResolvedValue({ data: result.data ?? null, error: result.error ?? null });
	const url = new URL(`http://localhost/api/time-clock/${path}`);
	return { url, request: new Request(url), locals: { supabase: { rpc } } } as unknown as AnyEvent;
}

function reader(permissions: Record<string, boolean>) {
	mockedAccess.mockResolvedValue({ features: {}, permissions } as never);
}

// Time clock Part 4 (docs/time-clock-behavior-contract.md § Timesheets page): people limited to their own time
// see only themselves; people who manage the team's time see everyone. The database repeats the rule.
describe('Timesheets reads', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedContext.mockResolvedValue({
			user: { id: me },
			organization: { id: organizationId }
		} as never);
		mockedPlan.mockReturnValue(true);
		reader({ 'time.track_own': true });
	});

	for (const [name, route, path] of [
		['the summary', SUMMARY, 'timesheets'],
		[
			'one person’s entries',
			ENTRIES,
			`timesheets/entries?user_id=${me}&from=2026-10-11&to=2026-10-17`
		]
	] as const) {
		describe(name, () => {
			it('needs a signed-in member', async () => {
				mockedContext.mockResolvedValue(null);
				const request = event(path);
				expect((await route(request)).status).toBe(401);
				expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
			});

			it('says so when the plan has no time tracking', async () => {
				mockedPlan.mockReturnValue(false);
				const response = await route(event(path));
				expect(response.status).toBe(403);
				expect(await response.json()).toMatchObject({ reason: 'feature_unavailable' });
			});

			it('refuses a member who records no hours', async () => {
				reader({});
				const request = event(path);
				const response = await route(request);
				expect(response.status).toBe(403);
				expect(await response.json()).toMatchObject({ reason: 'permission_denied' });
				expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
			});

			it('turns the database’s refusal into a 403 and any other failure into a safe 500', async () => {
				const refused = await route(event(path, { error: { code: '42501' } }));
				expect(refused.status).toBe(403);
				const broken = await route(event(path, { error: { code: '08000' } }));
				expect(broken.status).toBe(500);
			});
		});
	}

	describe('the summary', () => {
		it('reads this week in the caller’s business when nothing is chosen, privately cached', async () => {
			const answer = { span: 'week', people: [] };
			const request = event('timesheets', { data: answer });
			const response = await SUMMARY(request);
			expect(response.status).toBe(200);
			expect(await response.json()).toEqual(answer);
			expect(response.headers.get('cache-control')).toBe('private, no-cache');
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith('timesheet_summary', {
				target_organization_id: organizationId,
				anchor_date: undefined,
				span: 'week'
			});
		});

		it('passes a chosen day and view', async () => {
			const request = event('timesheets?span=day&date=2026-10-05', { data: {} });
			expect((await SUMMARY(request)).status).toBe(200);
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith('timesheet_summary', {
				target_organization_id: organizationId,
				anchor_date: '2026-10-05',
				span: 'day'
			});
		});

		it('refuses a view or day it does not know', async () => {
			for (const query of ['span=month', 'date=2026-02-30', 'date=yesterday']) {
				const request = event(`timesheets?${query}`);
				expect((await SUMMARY(request)).status).toBe(422);
				expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
			}
		});
	});

	describe('one person’s entries', () => {
		const week = 'from=2026-10-11&to=2026-10-17';

		it('gives someone limited to their own time their own entries', async () => {
			const request = event(`timesheets/entries?user_id=${me}&${week}`, { data: { entries: [] } });
			const response = await ENTRIES(request);
			expect(response.status).toBe(200);
			expect(response.headers.get('cache-control')).toBe('private, no-cache');
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith('timesheet_entries', {
				target_organization_id: organizationId,
				target_user_id: me,
				range_from: '2026-10-11',
				range_to: '2026-10-17'
			});
		});

		it('refuses them a teammate’s before asking the database', async () => {
			const request = event(`timesheets/entries?user_id=${teammate}&${week}`);
			const response = await ENTRIES(request);
			expect(response.status).toBe(403);
			expect(await response.json()).toEqual({
				error: 'You do not have access to these hours.',
				reason: 'permission_denied'
			});
			expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
		});

		it('lets someone who manages the team’s time read anyone', async () => {
			reader({ 'time.track_team': true });
			const request = event(`timesheets/entries?user_id=${teammate}&${week}`, {
				data: { entries: [] }
			});
			expect((await ENTRIES(request)).status).toBe(200);
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith(
				'timesheet_entries',
				expect.objectContaining({ target_user_id: teammate })
			);
		});

		it('reads at most a week, forwards, for a real person', async () => {
			for (const query of [
				`from=2026-10-11&to=2026-10-17`,
				`user_id=nobody&${week}`,
				`user_id=${me}&from=2026-10-17&to=2026-10-11`,
				`user_id=${me}&from=2026-10-01&to=2026-10-17`
			]) {
				const request = event(`timesheets/entries?${query}`);
				expect((await ENTRIES(request)).status).toBe(422);
				expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
			}
		});
	});
});
