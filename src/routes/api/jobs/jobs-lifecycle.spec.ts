import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as COMPLETE } from './[id]/visits/[visitId]/complete/+server';
import { POST as UNCOMPLETE } from './[id]/visits/[visitId]/uncomplete/+server';
import { POST as CLOSE } from './[id]/close/+server';
import { POST as REOPEN } from './[id]/reopen/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.jobs': true } }
	} as never;
}

function visitEvent(rpc = vi.fn()) {
	return {
		params: { id: 'job-1', visitId: 'visit-1' },
		locals: { supabase: { rpc } }
	} as unknown as never;
}

function lifecycleEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: 'job-1' },
		request: new Request('http://localhost/api/jobs/job-1/close', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as never;
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(context({ 'jobs.view': true, 'jobs.complete': true }));
});

describe('complete visit API', () => {
	it('marks the visit complete through the one command', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: { id: 'visit-1', is_completed: true }, error: null });

		const response = await COMPLETE(visitEvent(rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('complete_job_visit', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			target_visit_id: 'visit-1'
		});
		await expect(response.json()).resolves.toMatchObject({ id: 'visit-1', is_completed: true });
	});

	it('surfaces final_visit so the browser can open the Finish job dialog', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { id: 'visit-1', is_completed: true, final_visit: true },
			error: null
		});

		const response = await COMPLETE(visitEvent(rpc));

		await expect(response.json()).resolves.toMatchObject({ final_visit: true });
	});

	it('turns a member without jobs.complete into a not-found, telling a stranger nothing', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '42501', message: 'no access' } });

		const response = await COMPLETE(visitEvent(rpc));

		expect(response.status).toBe(404);
	});

	it('turns a missing visit into a not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0404', message: 'That visit could not be found.' }
		});

		const response = await COMPLETE(visitEvent(rpc));

		expect(response.status).toBe(404);
	});

	it('turns a closed job into a locked conflict', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0410', message: 'That visit can no longer be changed.' }
		});

		const response = await COMPLETE(visitEvent(rpc));

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({ reason: 'locked' });
	});
});

describe('uncomplete visit API', () => {
	it('clears the visit through the one command', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: { id: 'visit-1', is_completed: false }, error: null });

		const response = await UNCOMPLETE(visitEvent(rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('uncomplete_job_visit', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			target_visit_id: 'visit-1'
		});
	});

	it('turns a member without jobs.complete into a not-found', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '42501', message: 'no access' } });

		const response = await UNCOMPLETE(visitEvent(rpc));

		expect(response.status).toBe(404);
	});
});

describe('close job API', () => {
	it('rejects a missing expected_revision before touching the database', async () => {
		const rpc = vi.fn();

		const response = await CLOSE(lifecycleEvent({}, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON before touching the database', async () => {
		const rpc = vi.fn();

		const response = await CLOSE(lifecycleEvent('not json', rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('finishes the job through the one command', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { id: 'job-1', status: 'closed' }, error: null });

		const response = await CLOSE(lifecycleEvent({ expected_revision: 3 }, rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('close_job', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			expected_revision: 3
		});
		await expect(response.json()).resolves.toMatchObject({ status: 'closed' });
	});

	it('turns a member without jobs.close into a not-found', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '42501', message: 'no access' } });

		const response = await CLOSE(lifecycleEvent({ expected_revision: 3 }, rpc));

		expect(response.status).toBe(404);
	});

	it('turns a stale revision into a reload conflict', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0409', message: 'Someone else changed this job. Reload to see the latest.' }
		});

		const response = await CLOSE(lifecycleEvent({ expected_revision: 3 }, rpc));

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
	});

	it('turns incomplete visits still open into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: {
				code: '23514',
				message: 'Complete or remove the remaining visits before finishing this job.'
			}
		});

		const response = await CLOSE(lifecycleEvent({ expected_revision: 3 }, rpc));

		expect(response.status).toBe(422);
		await expect(response.json()).resolves.toMatchObject({
			field_errors: { form: 'Complete or remove the remaining visits before finishing this job.' }
		});
	});
});

describe('reopen job API', () => {
	it('reopens the job through the one command', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { id: 'job-1', status: 'active' }, error: null });

		const response = await REOPEN(lifecycleEvent({ expected_revision: 4 }, rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('reopen_job', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			expected_revision: 4
		});
		await expect(response.json()).resolves.toMatchObject({ status: 'active' });
	});

	it('rejects a missing expected_revision before touching the database', async () => {
		const rpc = vi.fn();

		const response = await REOPEN(lifecycleEvent({}, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('turns a stale revision into a reload conflict', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0409', message: 'Someone else changed this job. Reload to see the latest.' }
		});

		const response = await REOPEN(lifecycleEvent({ expected_revision: 4 }, rpc));

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({ reason: 'stale' });
	});
});
