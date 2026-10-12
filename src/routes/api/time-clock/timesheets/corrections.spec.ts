import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as ADD } from './entries/+server';
import { DELETE as REMOVE, PATCH as CHANGE } from './entries/[entryId=uuid]/+server';
import { GET as HISTORY } from './entries/[entryId=uuid]/history/+server';
import { PATCH as CHANGE_RUNNING } from './running/[userId=uuid]/+server';
import { POST as STOP } from './running/[userId=uuid]/stop/+server';
import { POST as CLOCK_IN } from './running/[userId=uuid]/clock-in/+server';
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
const entryId = '00000000-0000-4000-8000-0000000000e1';
const jobId = '00000000-0000-4000-8000-0000000000b1';

type AnyHandler = (event: never) => Promise<Response> | Response;

function call(
	handler: AnyHandler,
	options: {
		method?: string;
		body?: unknown;
		params?: Record<string, string>;
		result?: { data?: unknown; error?: unknown };
	} = {}
) {
	const rpc = vi.fn().mockResolvedValue({
		data: options.result?.data ?? { id: entryId },
		error: options.result?.error ?? null
	});
	const url = new URL('http://localhost/api/time-clock/timesheets');
	const request = new Request(url, {
		method: options.method ?? 'POST',
		headers: { 'content-type': 'application/json' },
		body: options.body === undefined ? undefined : JSON.stringify(options.body)
	});
	const event = { url, request, params: options.params ?? {}, locals: { supabase: { rpc } } };
	return { rpc, response: handler(event as never) };
}

function reader(permissions: Record<string, boolean>) {
	mockedAccess.mockResolvedValue({ features: {}, permissions } as never);
}

const entry = {
	user_id: me,
	job_id: null,
	day: '2026-10-05',
	start_time: '22:00',
	end_time: '02:00',
	notes: ' Yard '
};

// Time clock Part 5 (docs/time-clock-behavior-contract.md § Timesheets page, § Forgotten timers): entries are
// added, corrected and removed from Timesheets; a manager clocks people in and stops forgotten timers. The
// database decides who may change which hours; the routes validate first and refuse the obvious early.
describe('Timesheets corrections', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedContext.mockResolvedValue({
			user: { id: me },
			organization: { id: organizationId }
		} as never);
		mockedPlan.mockReturnValue(true);
		reader({ 'time.track_own': true });
	});

	it('needs a signed-in member', async () => {
		mockedContext.mockResolvedValue(null);
		const { rpc, response } = call(ADD, { body: entry });
		expect((await response).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a member who records no hours', async () => {
		reader({});
		const { rpc, response } = call(ADD, { body: entry });
		expect((await response).status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	// Time clock Part 6 (§ Permissions): someone who only starts and stops their own timers reads their own
	// hours but is refused every change, on screen and here, before the database refuses the same.
	describe('timers only', () => {
		beforeEach(() => reader({ 'time.timers_own': true }));

		const writes: Array<[string, () => ReturnType<typeof call>]> = [
			['adding an entry', () => call(ADD, { body: entry })],
			[
				'correcting an entry',
				() => call(CHANGE, { method: 'PATCH', body: entry, params: { entryId } })
			],
			['deleting an entry', () => call(REMOVE, { method: 'DELETE', params: { entryId } })],
			[
				'changing their running timer',
				() =>
					call(CHANGE_RUNNING, {
						method: 'PATCH',
						body: { day: '2026-10-05', start_time: '08:00' },
						params: { userId: me }
					})
			],
			[
				'stopping their timer at a chosen time',
				() => call(STOP, { body: { day: '2026-10-05', time: '17:30' }, params: { userId: me } })
			]
		];

		for (const [name, send] of writes) {
			it(`refuses ${name} and tells them to ask a manager`, async () => {
				const { rpc, response } = send();
				const answer = await response;
				expect(answer.status).toBe(403);
				expect(await answer.json()).toMatchObject({
					error: 'Ask a manager to change your hours.',
					reason: 'permission_denied'
				});
				expect(rpc).not.toHaveBeenCalled();
			});
		}

		it('still reads their own edit history', async () => {
			const { rpc, response } = call(HISTORY, { method: 'GET', params: { entryId } });
			expect((await response).status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('time_entry_history', expect.anything());
		});
	});

	describe('adding an entry', () => {
		it('sends General time on the business clock, notes trimmed', async () => {
			const { rpc, response } = call(ADD, { body: entry });
			expect((await response).status).toBe(201);
			expect(rpc).toHaveBeenCalledWith('add_time_entry', {
				target_organization_id: organizationId,
				target_user_id: me,
				target_job_id: null,
				target_visit_id: null,
				work_day: '2026-10-05',
				start_time: '22:00',
				end_time: '02:00',
				notes: 'Yard'
			});
		});

		it('refuses a teammate’s hours for someone limited to their own, before the database', async () => {
			const { rpc, response } = call(ADD, { body: { ...entry, user_id: teammate } });
			expect((await response).status).toBe(403);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('lets a manager add a teammate’s hours', async () => {
			reader({ 'time.track_team': true });
			const { rpc, response } = call(ADD, { body: { ...entry, user_id: teammate } });
			expect((await response).status).toBe(201);
			expect(rpc).toHaveBeenCalledWith(
				'add_time_entry',
				expect.objectContaining({ target_user_id: teammate })
			);
		});

		for (const [name, body, field] of [
			['a time that is not a clock time', { ...entry, start_time: '8am' }, 'start_time'],
			['the same start and end', { ...entry, end_time: '22:00' }, 'end_time'],
			['a visit on General time', { ...entry, visit_id: entryId }, 'visit_id'],
			['hours put on an assessment by hand', { ...entry, request_id: entryId }, 'request_id'],
			['a field the form does not have', { ...entry, minutes: 30 }, 'form']
		] as const) {
			it(`refuses ${name}`, async () => {
				const { rpc, response } = call(ADD, { body });
				const result = await response;
				expect(result.status).toBe(422);
				const payload = await result.json();
				expect(Object.keys(payload.field_errors)).toContain(field);
				expect(rpc).not.toHaveBeenCalled();
			});
		}

		it('turns a database rule about the times into a form error', async () => {
			const { response } = call(ADD, {
				body: { ...entry, job_id: jobId },
				result: {
					error: { code: '22023', message: 'A single entry cannot be longer than 24 hours.' }
				}
			});
			const result = await response;
			expect(result.status).toBe(422);
			expect((await result.json()).field_errors.form).toBe(
				'A single entry cannot be longer than 24 hours.'
			);
		});
	});

	describe('changing and removing an entry', () => {
		it('sends the correction for the entry in the address', async () => {
			const { rpc, response } = call(CHANGE, {
				method: 'PATCH',
				body: { ...entry, job_id: jobId },
				params: { entryId }
			});
			expect((await response).status).toBe(200);
			expect(rpc).toHaveBeenCalledWith(
				'update_time_entry',
				expect.objectContaining({ target_entry_id: entryId, target_job_id: jobId })
			);
		});

		it('keeps assessment hours on their own request', async () => {
			const requestId = '00000000-0000-4000-8000-000000000009';
			const { rpc, response } = call(CHANGE, {
				method: 'PATCH',
				body: { ...entry, request_id: requestId },
				params: { entryId }
			});
			expect((await response).status).toBe(200);
			expect(rpc).toHaveBeenCalledWith(
				'update_time_entry',
				expect.objectContaining({ target_job_id: null, target_request_id: requestId })
			);
		});

		it('refuses hours on a job and an assessment at once', async () => {
			const { rpc, response } = call(CHANGE, {
				method: 'PATCH',
				body: { ...entry, job_id: jobId, request_id: entryId },
				params: { entryId }
			});
			const result = await response;
			expect(result.status).toBe(422);
			expect(Object.keys((await result.json()).field_errors)).toContain('request_id');
			expect(rpc).not.toHaveBeenCalled();
		});

		it('says a running timer cannot be changed like an entry', async () => {
			const { response } = call(CHANGE, {
				method: 'PATCH',
				body: entry,
				params: { entryId },
				result: {
					error: {
						code: 'P0410',
						message: 'This timer is still running. Only its start time and notes can be changed.'
					}
				}
			});
			const result = await response;
			expect(result.status).toBe(409);
			expect(await result.json()).toMatchObject({ reason: 'locked' });
		});

		it('says plainly when the database refuses access', async () => {
			const { response } = call(REMOVE, {
				method: 'DELETE',
				params: { entryId },
				result: {
					error: { code: '42501', message: 'You do not have access to change these hours.' }
				}
			});
			const result = await response;
			expect(result.status).toBe(403);
			expect((await result.json()).error).toBe('You do not have access to change these hours.');
		});

		it('reads the history of the entry in the address', async () => {
			const { rpc, response } = call(HISTORY, { method: 'GET', params: { entryId } });
			expect((await response).status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('time_entry_history', {
				target_organization_id: organizationId,
				target_entry_id: entryId
			});
		});
	});

	describe('running timers', () => {
		it('changes only the start and notes', async () => {
			const { rpc, response } = call(CHANGE_RUNNING, {
				method: 'PATCH',
				body: { day: '2026-10-05', start_time: '07:30', notes: null },
				params: { userId: me }
			});
			expect((await response).status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('update_running_timer', {
				target_organization_id: organizationId,
				target_user_id: me,
				work_day: '2026-10-05',
				start_time: '07:30',
				notes: undefined
			});

			const refused = call(CHANGE_RUNNING, {
				method: 'PATCH',
				body: { day: '2026-10-05', start_time: '07:30', end_time: '09:00' },
				params: { userId: me }
			});
			expect((await refused.response).status).toBe(422);
		});

		it('stops now when nothing is sent', async () => {
			const { rpc, response } = call(STOP, { params: { userId: teammate } });
			expect((await response).status).toBe(200);
			expect(rpc).toHaveBeenCalledWith('stop_timer_at', {
				target_organization_id: organizationId,
				target_user_id: teammate,
				end_day: undefined,
				end_time: undefined
			});
		});

		it('stops at the time work really ended, and needs both the day and the time', async () => {
			const { rpc, response } = call(STOP, {
				body: { day: '2026-10-04', time: '17:30' },
				params: { userId: teammate }
			});
			expect((await response).status).toBe(200);
			expect(rpc).toHaveBeenCalledWith(
				'stop_timer_at',
				expect.objectContaining({ end_day: '2026-10-04', end_time: '17:30' })
			);

			const halfChosen = call(STOP, { body: { day: '2026-10-04' }, params: { userId: teammate } });
			expect((await halfChosen.response).status).toBe(422);
		});

		it('lets only a manager clock someone in', async () => {
			const crew = call(CLOCK_IN, { params: { userId: teammate } });
			expect((await crew.response).status).toBe(403);
			expect(crew.rpc).not.toHaveBeenCalled();

			reader({ 'time.track_team': true });
			const manager = call(CLOCK_IN, { params: { userId: teammate } });
			expect((await manager.response).status).toBe(200);
			expect(manager.rpc).toHaveBeenCalledWith('clock_in_member', {
				target_organization_id: organizationId,
				target_user_id: teammate
			});
		});
	});
});
