import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, PATCH, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const packageId = '123e4567-e89b-12d3-a456-426614174000';
const editionId = '223e4567-e89b-12d3-a456-426614174000';

const terms = {
	slug: 'growth',
	name: 'Growth',
	promise: 'Never miss a lead',
	highlights: ['Premium functional website'],
	included_services: [{ service_key: 'website', name: 'On-site SEO', description: '' }],
	exclusions: '',
	monthly_price_usd_cents: 24900,
	yearly_price_usd_cents: null,
	capabilities: ['website_chat', 'communications.inbox'],
	allowances: [
		{ key: 'website_chat_widgets', state: 'numeric', value: 2 },
		{ key: 'employee_seats', state: 'unlimited', value: 7 }
	]
};

function event(method: string, body?: unknown, id = packageId) {
	return {
		params: { packageId: id },
		request: new Request(`http://localhost/api/jafar/packages/${id}/draft`, {
			method,
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

function client(result: { data: unknown; error: { code: string; message: string } | null }) {
	const rpc = vi.fn(() => Promise.resolve(result));
	mockedClient.mockReturnValue({ rpc } as never);
	return rpc;
}

describe('/api/jafar/packages/[packageId]/draft', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 's' } as never);
	});

	it('refuses anyone who is not the platform owner', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const rpc = client({ data: null, error: null });
		const response = await PATCH(event('PATCH', { edition_id: editionId, revision: 1, terms }));
		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('explains invalid terms by their field before touching the database', async () => {
		const rpc = client({ data: null, error: null });
		const response = await PATCH(
			event('PATCH', {
				edition_id: editionId,
				revision: 1,
				terms: { ...terms, highlights: ['ok', 'x'] }
			})
		);
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors['highlights.1']).toMatch(/at least 2/);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('saves the whole draft naming the loaded revision, dropping values of unlimited allowances', async () => {
		const rpc = client({ data: { saved: true, draft: { revision: 3 } }, error: null });
		const response = await PATCH(event('PATCH', { edition_id: editionId, revision: 2, terms }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ draft: { revision: 3 } });
		expect(rpc).toHaveBeenCalledWith(
			'save_package_draft',
			expect.objectContaining({
				target_package_id: packageId,
				draft_edition_id: editionId,
				loaded_revision: 2,
				actor_owner_email: 'owner@example.com',
				terms: expect.objectContaining({
					allowances: [
						{ key: 'website_chat_widgets', state: 'numeric', value: 2 },
						{ key: 'employee_seats', state: 'unlimited', value: null }
					]
				})
			})
		);
	});

	it('returns the newer draft with 409 when another tab saved first', async () => {
		client({
			data: { saved: false, reason: 'stale', draft: { revision: 5, name: 'Newer' } },
			error: null
		});
		const response = await PATCH(event('PATCH', { edition_id: editionId, revision: 2, terms }));
		expect(response.status).toBe(409);
		const body = await response.json();
		expect(body.reason).toBe('stale');
		expect(body.draft).toEqual({ revision: 5, name: 'Newer' });
	});

	it('reports a taken web address as a refused change', async () => {
		client({
			data: null,
			error: { code: '23505', message: 'Another package already uses the web address "growth".' }
		});
		const response = await PATCH(event('PATCH', { edition_id: editionId, revision: 2, terms }));
		expect(response.status).toBe(409);
		expect((await response.json()).error).toMatch(/already uses/);
	});

	it('opens a draft of a published package', async () => {
		const rpc = client({ data: { applied: true, edition_id: editionId }, error: null });
		const response = await POST(event('POST'));
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('open_package_draft', {
			target_package_id: packageId,
			actor_owner_email: 'owner@example.com'
		});
	});

	it('deletes a draft and says whether the package went with it', async () => {
		client({ data: { deleted: true, package_removed: true }, error: null });
		const response = await DELETE(event('DELETE', { edition_id: editionId, revision: 1 }));
		expect(await response.json()).toEqual({ package_removed: true });
		expect(mockedClient.mock.results[0].value.rpc).toHaveBeenCalledWith(
			'delete_package_draft',
			expect.objectContaining({ actor_owner_email: 'owner@example.com' })
		);
	});

	it('refuses to delete a draft that changed in another tab', async () => {
		client({ data: { deleted: false, reason: 'stale', draft: { revision: 2 } }, error: null });
		const response = await DELETE(event('DELETE', { edition_id: editionId, revision: 1 }));
		expect(response.status).toBe(409);
	});

	it('reports a draft that is gone as not found', async () => {
		client({ data: null, error: { code: 'P0002', message: 'This draft no longer exists.' } });
		const response = await DELETE(event('DELETE', { edition_id: editionId, revision: 1 }));
		expect(response.status).toBe(404);
	});
});
