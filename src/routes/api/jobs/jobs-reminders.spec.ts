import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as ADD } from './[id]/reminders/+server';
import { PATCH as DISMISS, DELETE as REMOVE } from './[id]/reminders/[reminderId]/+server';
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

const REMINDER_ID = '00000000-0000-4000-8000-0000000000r1';

function addEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: 'job-1' },
		request: new Request('http://localhost/api/jobs/job-1/reminders', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as never;
}

function idEvent(method: 'PATCH' | 'DELETE', rpc = vi.fn()) {
	return {
		params: { id: 'job-1', reminderId: REMINDER_ID },
		request: new Request(`http://localhost/api/jobs/job-1/reminders/${REMINDER_ID}`, { method }),
		locals: { supabase: { rpc } }
	} as unknown as never;
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(context({ 'jobs.view': true, 'jobs.edit': true }));
});

describe('add invoice reminder API', () => {
	it('hands the date and note to the one command that raises a reminder', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { id: REMINDER_ID }, error: null });

		const response = await ADD(
			addEvent({ due_on: '2026-09-30', note: 'bill with the March statement' }, rpc)
		);

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('add_job_invoice_reminder', {
			target_organization_id: 'org-1',
			target_job_id: 'job-1',
			new_due_on: '2026-09-30',
			new_note: 'bill with the March statement'
		});
		await expect(response.json()).resolves.toMatchObject({ id: REMINDER_ID });
	});

	it('sends a missing note through as null rather than an empty string', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { id: REMINDER_ID }, error: null });

		await ADD(addEvent({ due_on: '2026-09-30' }, rpc));

		expect(rpc.mock.calls[0][1].new_note).toBeNull();
	});

	it('rejects a missing date before touching the database', async () => {
		const rpc = vi.fn();

		const response = await ADD(addEvent({ note: 'no date here' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a malformed date without asking the database', async () => {
		const rpc = vi.fn();

		const response = await ADD(addEvent({ due_on: '30-09-2026' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses an over-long note without asking the database', async () => {
		const rpc = vi.fn();

		const response = await ADD(addEvent({ due_on: '2026-09-30', note: 'x'.repeat(201) }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('turns a member without jobs.edit into a not-found, telling a stranger nothing', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '42501', message: 'no access' } });

		const response = await ADD(addEvent({ due_on: '2026-09-30' }, rpc));

		expect(response.status).toBe(404);
	});
});

describe('dismiss invoice reminder API', () => {
	it('marks the reminder handled through the dismiss command', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: { id: REMINDER_ID, status: 'resolved' }, error: null });

		const response = await DISMISS(idEvent('PATCH', rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('dismiss_job_invoice_reminder', {
			target_organization_id: 'org-1',
			target_reminder_id: REMINDER_ID
		});
		await expect(response.json()).resolves.toMatchObject({ status: 'resolved' });
	});

	it('turns an already-handled reminder into a not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0404', message: 'That reminder was already handled or does not exist.' }
		});

		const response = await DISMISS(idEvent('PATCH', rpc));

		expect(response.status).toBe(404);
	});
});

describe('delete invoice reminder API', () => {
	it('deletes through the delete command', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: { id: REMINDER_ID, deleted: true }, error: null });

		const response = await REMOVE(idEvent('DELETE', rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('delete_job_invoice_reminder', {
			target_organization_id: 'org-1',
			target_reminder_id: REMINDER_ID
		});
		await expect(response.json()).resolves.toMatchObject({ deleted: true });
	});

	it('turns the "only a custom date can be deleted" rule into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: {
				code: '23514',
				message: 'Only a custom-date reminder can be deleted. Dismiss the others instead.'
			}
		});

		const response = await REMOVE(idEvent('DELETE', rpc));

		expect(response.status).toBe(422);
		await expect(response.json()).resolves.toMatchObject({
			field_errors: {
				form: 'Only a custom-date reminder can be deleted. Dismiss the others instead.'
			}
		});
	});
});
