import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const clientId = '123e4567-e89b-12d3-a456-426614174002';
const phoneId = '123e4567-e89b-12d3-a456-426614174003';
const actorId = '123e4567-e89b-12d3-a456-426614174001';

function getEvent() {
	return { params: { clientId }, locals: {} } as Parameters<typeof GET>[0];
}

// A table read that resolves to `result` however it is chained, recording the calls made on it.
function table(result: { data?: unknown; error?: unknown }) {
	const obj: Record<string, ReturnType<typeof vi.fn>> = {};
	for (const method of ['select', 'eq', 'in', 'order', 'limit']) obj[method] = vi.fn(() => obj);
	(obj as unknown as { then: unknown }).then = (...args: unknown[]) =>
		(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(...args);
	return obj;
}

describe('the text stop lines for a conversation', () => {
	const tables: Record<string, ReturnType<typeof table>> = {};

	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { organization: { id: organizationId } }
		} as never);
		for (const key of Object.keys(tables)) delete tables[key];
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: (name: string) => tables[name]
		} as never);
	});

	it('needs the permission to see customers', async () => {
		tables.client_contact_methods = table({ data: [] });
		await GET(getEvent());
		expect(requireOrganizationPermission).toHaveBeenCalledWith(expect.anything(), 'customers.view');
	});

	it('returns the permission failure untouched', async () => {
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			response: new Response(null, { status: 403 })
		} as never);
		expect((await GET(getEvent())).status).toBe(403);
	});

	it('returns no lines, without reading consent history, for a customer with no phone number', async () => {
		tables.client_contact_methods = table({ data: [] });
		tables.communication_sms_consent_events = table({ data: [] });
		const response = await GET(getEvent());
		expect(await response.json()).toEqual({ notes: [] });
		expect(tables.communication_sms_consent_events.select).not.toHaveBeenCalled();
	});

	it('reads only staff stop events on this customer’s own numbers', async () => {
		tables.client_contact_methods = table({ data: [{ id: phoneId, value: '+15550100' }] });
		tables.communication_sms_consent_events = table({ data: [] });
		tables.profiles = table({ data: [] });
		await GET(getEvent());
		const events = tables.communication_sms_consent_events;
		expect(events.eq).toHaveBeenCalledWith('organization_id', organizationId);
		expect(events.eq).toHaveBeenCalledWith('source', 'staff');
		expect(events.in).toHaveBeenCalledWith('client_contact_method_id', [phoneId]);
		expect(events.in).toHaveBeenCalledWith('evidence->>kind', ['staff_stop', 'staff_stop_undone']);
	});

	it('names who did it, which number, and any reason', async () => {
		tables.client_contact_methods = table({ data: [{ id: phoneId, value: '+15550100' }] });
		tables.communication_sms_consent_events = table({
			data: [
				{
					id: 'e2',
					client_contact_method_id: phoneId,
					occurred_at: '2026-09-21T10:05:00Z',
					created_by: actorId,
					evidence: { kind: 'staff_stop_undone' }
				},
				{
					id: 'e1',
					client_contact_method_id: phoneId,
					occurred_at: '2026-09-21T10:00:00Z',
					created_by: actorId,
					evidence: { kind: 'staff_stop', note: '  asked on the phone ' }
				}
			]
		});
		tables.profiles = table({ data: [{ id: actorId, full_name: 'Sam' }] });

		const { notes } = await (await GET(getEvent())).json();
		expect(notes).toEqual([
			{
				id: 'e2',
				kind: 'turned_on',
				phone: '+15550100',
				by_name: 'Sam',
				note: null,
				created_at: '2026-09-21T10:05:00Z'
			},
			{
				id: 'e1',
				kind: 'stopped',
				phone: '+15550100',
				by_name: 'Sam',
				note: 'asked on the phone',
				created_at: '2026-09-21T10:00:00Z'
			}
		]);
	});

	it('fails plainly when the database read fails', async () => {
		tables.client_contact_methods = table({ error: { message: 'boom' } });
		expect((await GET(getEvent())).status).toBe(500);
	});
});
