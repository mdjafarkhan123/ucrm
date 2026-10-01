import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { PATCH } from './[key]/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));
vi.mock('$lib/server/security/rate-limit', () => ({
	checkRateLimit: vi.fn(),
	rateLimitedResponse: () => new Response(null, { status: 429 })
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedLimit = vi.mocked(checkRateLimit);
const organizationId = '00000000-0000-4000-8000-000000000001';

function request(method: string, body: unknown) {
	return new Request('http://localhost/api/settings/pipeline/lost-reasons', {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
}

function addEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: {},
		request: request('POST', body),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

function retireEvent(key: string, body: unknown, rpc = vi.fn()) {
	return {
		params: { key },
		request: request('PATCH', body),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof PATCH>[0];
}

const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
	access: {}
} as never;

describe('Settings → Pipeline → Lost reasons', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedLimit.mockResolvedValue({ allowed: true } as never);
	});

	it('lets only owners and administrators change the list', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		expect((await POST(addEvent({ label: 'Out of service area' }, rpc))).status).toBe(403);
		expect((await PATCH(retireEvent('no_response', { retired: true }, rpc))).status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'settings.business.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('adds a reason with its spacing tidied', async () => {
		const added = {
			key: 'custom_0a1b2c',
			label: 'Out of service area',
			is_built_in: false,
			retired_at: null
		};
		const rpc = vi.fn().mockResolvedValue({ data: added, error: null });

		const response = await POST(addEvent({ label: '  Out of   service area ' }, rpc));

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('pipeline_add_lost_reason', {
			target_organization_id: organizationId,
			new_label: 'Out of service area'
		});
		expect((await response.json()).reason).toEqual(added);
	});

	it('refuses a blank name before asking the database', async () => {
		const rpc = vi.fn();
		const response = await POST(addEvent({ label: '   ' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it("shows the database's sentence for a name already on the list", async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: {
				code: '23505',
				message: '“No response” is one of your retired reasons. Bring it back instead.'
			}
		});

		const response = await POST(addEvent({ label: 'No Response' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.label).toBe(
			'“No response” is one of your retired reasons. Bring it back instead.'
		);
	});

	it('retires a reason by its key', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { key: 'no_response' }, error: null });

		const response = await PATCH(retireEvent('no_response', { retired: true }, rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('pipeline_set_lost_reason_retired', {
			target_organization_id: organizationId,
			target_key: 'no_response',
			retired: true
		});
	});

	it('answers a malformed key as not found', async () => {
		const rpc = vi.fn();
		const response = await PATCH(retireEvent('../other', { retired: true }, rpc));

		expect(response.status).toBe(404);
		expect(rpc).not.toHaveBeenCalled();
	});
});
