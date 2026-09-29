import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, PATCH } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedRateLimit = vi.mocked(checkRateLimit);

function context(permissions: Record<string, boolean>) {
	return {
		auth: {
			organization: { id: 'org-1', name: 'Bright Spark Electrical', role: 'owner' },
			user: { id: 'user-1', email: 'owner@example.com' }
		},
		access: { permissions, features: {} }
	} as never;
}

function readEvent(settings: Record<string, unknown>) {
	const from = vi.fn((table: string) => {
		const row = table === 'profiles' ? { full_name: 'Dana Admin' } : settings;
		const builder: Record<string, unknown> = {
			select: () => builder,
			eq: () => builder,
			maybeSingle: () => Promise.resolve({ data: row, error: null })
		};
		return builder;
	});
	return {
		request: new Request('http://localhost/api/settings/contact-matching'),
		locals: { supabase: { from } }
	} as unknown as Parameters<typeof GET>[0];
}

function writeEvent(
	body: unknown,
	rpcResult: unknown = { data: { status: 'saved' }, error: null }
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		request: new Request('http://localhost/api/settings/contact-matching', {
			method: 'PATCH',
			body: JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof PATCH>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(
		context({ 'settings.business.view': true, 'settings.business.edit': true })
	);
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
});

describe('reading contact matching', () => {
	it('returns the choice, its own revision, and who last changed it', async () => {
		const response = await GET(
			readEvent({
				contact_match_priority: 'phone',
				contact_match_revision: 3,
				contact_match_updated_by: 'user-9',
				contact_match_updated_at: '2026-09-29T10:00:00Z'
			})
		);
		const body = await response.json();

		expect(body.contact_matching).toEqual({
			priority: 'phone',
			revision: 3,
			last_editor: { name: 'Dana Admin', at: '2026-09-29T10:00:00Z' }
		});
		expect(body.permissions).toEqual({ view: true, edit: true });
	});

	it('marks a viewer without the edit permission as read-only', async () => {
		mockedRequire.mockResolvedValue(context({ 'settings.business.view': true }));
		const response = await GET(
			readEvent({
				contact_match_priority: 'email',
				contact_match_revision: 1,
				contact_match_updated_by: null,
				contact_match_updated_at: null
			})
		);
		const body = await response.json();

		expect(body.permissions.edit).toBe(false);
		expect(body.contact_matching.last_editor).toBeNull();
	});
});

describe('saving contact matching', () => {
	it('sends the choice with the revision the person started from', async () => {
		const event = writeEvent({ expected_revision: 2, priority: 'phone' });
		const response = await PATCH(event);

		expect(response.status).toBe(200);
		expect(event.__rpc).toHaveBeenCalledWith('save_contact_match_priority', {
			target_organization_id: 'org-1',
			expected_revision: 2,
			new_priority: 'phone'
		});
	});

	it('refuses anything other than email or phone before touching the database', async () => {
		const event = writeEvent({ expected_revision: 2, priority: 'name' });
		const response = await PATCH(event);

		expect(response.status).toBe(422);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('refuses to run at all without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await PATCH(writeEvent({ expected_revision: 2, priority: 'email' }));

		expect(response.status).toBe(403);
	});

	it('turns a stale save into a conflict that names the other person', async () => {
		const response = await PATCH(
			writeEvent(
				{ expected_revision: 2, priority: 'email' },
				{
					data: { status: 'stale', editor_name: 'Dana Admin', edited_at: '2026-09-29T10:00:00Z' },
					error: null
				}
			)
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ reason: 'stale', editor_name: 'Dana Admin' });
	});

	it('waits its turn when the organization is saving too often', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const response = await PATCH(writeEvent({ expected_revision: 2, priority: 'email' }));

		expect(response.status).toBe(429);
	});
});
