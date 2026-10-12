import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as PREVIEW, POST as APPROVE } from './approval/+server';
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

type AnyHandler = (event: never) => Promise<Response> | Response;

function call(
	handler: AnyHandler,
	options: {
		method?: string;
		body?: unknown;
		search?: string;
		result?: { data?: unknown; error?: unknown };
	} = {}
) {
	const rpc = vi.fn().mockResolvedValue({
		data: options.result?.data ?? { approved_count: 3 },
		error: options.result?.error ?? null
	});
	const url = new URL(`http://localhost/api/time-clock/timesheets/approval${options.search ?? ''}`);
	const request = new Request(url, {
		method: options.method ?? 'POST',
		headers: { 'content-type': 'application/json' },
		body: options.body === undefined ? undefined : JSON.stringify(options.body)
	});
	const event = { url, request, params: {}, locals: { supabase: { rpc } } };
	return { rpc, response: handler(event as never) };
}

function reader(permissions: Record<string, boolean>) {
	mockedAccess.mockResolvedValue({ features: {}, permissions } as never);
}

// Time clock Part 7 (docs/time-clock-behavior-contract.md § Weekly approval): only someone who manages the
// team's time previews or approves. The database repeats the refusal; the routes refuse first and validate the
// day and the people before anything reaches it.
describe('Weekly approval', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedContext.mockResolvedValue({
			user: { id: me },
			organization: { id: organizationId }
		} as never);
		mockedPlan.mockReturnValue(true);
		reader({ 'time.track_team': true });
	});

	it('needs a signed-in member', async () => {
		mockedContext.mockResolvedValue(null);
		const { rpc, response } = call(APPROVE, { body: { cutoff: '2026-10-10', user_ids: [me] } });
		expect((await response).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	for (const [label, permissions] of [
		['their own hours', { 'time.track_own': true }],
		['timers only', { 'time.timers_own': true }]
	] as const) {
		it(`refuses someone limited to ${label}`, async () => {
			reader(permissions);
			const preview = call(PREVIEW, { method: 'GET', search: '?date=2026-10-10' });
			const approve = call(APPROVE, { body: { cutoff: '2026-10-10', user_ids: [me] } });
			for (const { rpc, response } of [preview, approve]) {
				const result = await response;
				expect(result.status).toBe(403);
				expect((await result.json()).reason).toBe('permission_denied');
				expect(rpc).not.toHaveBeenCalled();
			}
		});
	}

	it('previews what approving up to a day covers', async () => {
		const { rpc, response } = call(PREVIEW, { method: 'GET', search: '?date=2026-10-10' });
		expect((await response).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('timesheet_approval', {
			target_organization_id: organizationId,
			cutoff: '2026-10-10'
		});
	});

	it('needs a day to preview', async () => {
		const { rpc, response } = call(PREVIEW, { method: 'GET', search: '?date=yesterday' });
		expect((await response).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('approves the chosen people up to the day, each once', async () => {
		const { rpc, response } = call(APPROVE, {
			body: { cutoff: '2026-10-10', user_ids: [me, teammate, me] }
		});
		expect((await response).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('approve_time_entries', {
			target_organization_id: organizationId,
			cutoff: '2026-10-10',
			target_user_ids: [me, teammate]
		});
	});

	it('refuses an approval with nobody chosen, or anything extra', async () => {
		for (const body of [
			{ cutoff: '2026-10-10', user_ids: [] },
			{ cutoff: '2026-10-10', user_ids: ['someone'] },
			{ user_ids: [me] },
			{ cutoff: '2026-10-10', user_ids: [me], approved_by: teammate }
		]) {
			const { rpc, response } = call(APPROVE, { body });
			expect((await response).status).toBe(422);
			expect(rpc).not.toHaveBeenCalled();
		}
	});

	it('passes on the database’s sentence for a day after today', async () => {
		const { response } = call(APPROVE, {
			body: { cutoff: '2026-12-31', user_ids: [me] },
			result: { error: { code: '22023', message: 'Choose today or an earlier day.' } }
		});
		const result = await response;
		expect(result.status).toBe(422);
		expect(JSON.stringify(await result.json())).toContain('Choose today or an earlier day.');
	});
});
