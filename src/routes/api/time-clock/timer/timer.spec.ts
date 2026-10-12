import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { POST as STOP } from './stop/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOrganizationContext } from '$lib/server/auth/organization';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));
vi.mock('$lib/server/auth/organization', () => ({
	getOrganizationContext: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedContext = vi.mocked(getOrganizationContext);
const organizationId = '00000000-0000-4000-8000-0000000000aa';
const jobId = '00000000-0000-4000-8000-000000000002';
const visitId = '00000000-0000-4000-8000-000000000004';
const base = 'http://localhost/api/time-clock/timer';

// One fake request event serves both routes, so it is typed as both.
type AnyEvent = Parameters<typeof GET>[0] & Parameters<typeof STOP>[0];

function event(url: string, body?: string, result: { data?: unknown; error?: unknown } = {}) {
	const rpc = vi.fn().mockResolvedValue({ data: result.data ?? null, error: result.error ?? null });
	const request = new Request(url, {
		method: body === undefined ? 'GET' : 'POST',
		headers: { 'content-type': 'application/json' },
		body
	});
	return { url: new URL(url), request, locals: { supabase: { rpc } } } as unknown as AnyEvent;
}

describe('the signed-in person’s timer', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedContext.mockResolvedValue({
			user: { id: 'user-1' },
			organization: { id: organizationId }
		} as never);
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
	});

	describe('reading', () => {
		it('needs a signed-in member', async () => {
			mockedContext.mockResolvedValue(null);
			const request = event(base);
			expect((await GET(request)).status).toBe(401);
			expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
		});

		it('reads only the caller’s own timer in their business and never caches it', async () => {
			const timer = { timer: null, can_time: true, server_now: '2026-10-11T09:00:00Z' };
			const request = event(base, undefined, { data: timer });
			const response = await GET(request);
			expect(response.status).toBe(200);
			expect(await response.json()).toEqual(timer);
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith('my_running_timer', {
				target_organization_id: organizationId
			});
			expect(response.headers.get('cache-control')).toBe('no-store');
		});

		it('maps a database failure to a safe response', async () => {
			const response = await GET(event(base, undefined, { error: { code: '08000' } }));
			expect(response.status).toBe(500);
		});
	});

	describe('starting', () => {
		it('requires Job access before touching the database', async () => {
			mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
			const request = event(base, JSON.stringify({ job_id: jobId, visit_id: visitId }));
			expect((await POST(request)).status).toBe(403);
			expect(mockedRequire).toHaveBeenCalledWith(request, 'jobs.view');
			expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
		});

		it('refuses a body that is not JSON, or does not name a job and visit', async () => {
			const broken = event(base, '{nope');
			const missing = event(base, JSON.stringify({ job_id: jobId }));
			expect((await POST(broken)).status).toBe(422);
			expect((await POST(missing)).status).toBe(422);
			expect(missing.locals.supabase.rpc).not.toHaveBeenCalled();
		});

		it('starts the caller’s timer on the visit, never naming anyone else', async () => {
			const request = event(base, JSON.stringify({ job_id: jobId, visit_id: visitId }), {
				data: { started_at: '2026-10-11T09:00:00Z', already_running: false }
			});
			const response = await POST(request);
			expect(response.status).toBe(200);
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith('start_visit_timer', {
				target_organization_id: organizationId,
				target_job_id: jobId,
				target_visit_id: visitId
			});
			expect(response.headers.get('cache-control')).toBe('no-store');
		});

		it('ignores a person field in the body', async () => {
			const request = event(
				base,
				JSON.stringify({ job_id: jobId, visit_id: visitId, user_id: 'someone-else' })
			);
			await POST(request);
			const args = vi.mocked(request.locals.supabase.rpc).mock.calls[0][1];
			expect(args).not.toHaveProperty('target_user_id');
		});

		it('reads a job the caller may not time as not found', async () => {
			const response = await POST(
				event(base, JSON.stringify({ job_id: jobId, visit_id: visitId }), {
					error: { code: '42501', message: 'permission denied' }
				})
			);
			expect(response.status).toBe(404);
			expect((await response.json()).error).toBe('That visit could not be found.');
		});

		it('says so when another timer is already running', async () => {
			const response = await POST(
				event(base, JSON.stringify({ job_id: jobId, visit_id: visitId }), {
					error: { code: 'P0409', message: 'You already have a timer running.' }
				})
			);
			expect(response.status).toBe(409);
			expect(await response.json()).toEqual({
				error: 'You already have a timer running.',
				reason: 'timer_running'
			});
		});

		it('carries the database’s sentence for a completed visit or a closed job', async () => {
			const response = await POST(
				event(base, JSON.stringify({ job_id: jobId, visit_id: visitId }), {
					error: { code: 'P0410', message: 'This visit is completed. Reopen it to time it.' }
				})
			);
			expect(response.status).toBe(409);
			expect(await response.json()).toEqual({
				error: 'This visit is completed. Reopen it to time it.',
				reason: 'locked'
			});
		});
	});

	describe('starting on an assessment', () => {
		const assessmentId = '00000000-0000-4000-8000-000000000006';

		it('starts the caller’s timer on the assessment, never naming anyone else', async () => {
			const request = event(base, JSON.stringify({ assessment_id: assessmentId }), {
				data: { started_at: '2026-10-11T09:00:00Z', already_running: false, day_clock_paused: true }
			});
			const response = await POST(request);
			expect(response.status).toBe(200);
			expect(mockedRequire).toHaveBeenCalledWith(request, 'jobs.view');
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith('start_assessment_timer', {
				target_organization_id: organizationId,
				target_assessment_id: assessmentId
			});
			expect(response.headers.get('cache-control')).toBe('no-store');
		});

		it('refuses a malformed assessment, or one mixed with a visit, before the database', async () => {
			const broken = event(base, JSON.stringify({ assessment_id: 'nope' }));
			const mixed = event(
				base,
				JSON.stringify({ assessment_id: assessmentId, job_id: jobId, visit_id: visitId })
			);
			expect((await POST(broken)).status).toBe(422);
			expect((await POST(mixed)).status).toBe(422);
			expect(broken.locals.supabase.rpc).not.toHaveBeenCalled();
			expect(mixed.locals.supabase.rpc).not.toHaveBeenCalled();
		});

		it('reads an assessment the caller may not time as not found', async () => {
			const response = await POST(
				event(base, JSON.stringify({ assessment_id: assessmentId }), {
					error: { code: '42501', message: 'permission denied' }
				})
			);
			expect(response.status).toBe(404);
			expect((await response.json()).error).toBe('That assessment could not be found.');
		});

		it('carries the database’s sentence for an assessment not booked for today', async () => {
			const response = await POST(
				event(base, JSON.stringify({ assessment_id: assessmentId }), {
					error: { code: 'P0410', message: 'Only an assessment booked for today can be timed.' }
				})
			);
			expect(response.status).toBe(409);
			expect(await response.json()).toEqual({
				error: 'Only an assessment booked for today can be timed.',
				reason: 'locked'
			});
		});
	});

	describe('stopping', () => {
		it('needs a signed-in member, not a timer permission', async () => {
			mockedContext.mockResolvedValue(null);
			const request = event(`${base}/stop`, '{}');
			expect((await STOP(request)).status).toBe(401);
			expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
			expect(mockedRequire).not.toHaveBeenCalled();
		});

		it('accepts an empty body and stops the caller’s own timer', async () => {
			const recorded = {
				stopped: true,
				recorded: true,
				entry_id: 'e1',
				job_id: jobId,
				minutes: 40
			};
			const request = event(`${base}/stop`, '', { data: recorded });
			const response = await STOP(request);
			expect(response.status).toBe(200);
			expect(await response.json()).toEqual(recorded);
			expect(request.locals.supabase.rpc).toHaveBeenCalledWith('stop_my_timer', {
				target_organization_id: organizationId
			});
			expect(response.headers.get('cache-control')).toBe('no-store');
		});

		it('refuses a body that tries to name a timer or is not JSON', async () => {
			const naming = event(`${base}/stop`, JSON.stringify({ user_id: 'someone-else' }));
			const broken = event(`${base}/stop`, '{nope');
			expect((await STOP(naming)).status).toBe(422);
			expect((await STOP(broken)).status).toBe(422);
			expect(naming.locals.supabase.rpc).not.toHaveBeenCalled();
		});

		it('passes a second Stop through as already stopped, not an error', async () => {
			const already = { stopped: false, already_stopped: true, recorded: false };
			const response = await STOP(event(`${base}/stop`, '{}', { data: already }));
			expect(response.status).toBe(200);
			expect(await response.json()).toEqual(already);
		});

		it('carries the refusal for a timer that has run over a day', async () => {
			const response = await STOP(
				event(`${base}/stop`, '{}', {
					error: { code: 'P0410', message: 'This timer ran over 24 hours. Ask a manager.' }
				})
			);
			expect(response.status).toBe(409);
			expect((await response.json()).reason).toBe('locked');
		});

		it('maps a database failure to a safe response', async () => {
			const response = await STOP(event(`${base}/stop`, '{}', { error: { code: '08000' } }));
			expect(response.status).toBe(500);
		});
	});
});
