import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { POST as PUBLISH } from './publish/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const packageId = '123e4567-e89b-12d3-a456-426614174000';
const editionId = '223e4567-e89b-12d3-a456-426614174000';

function event(method: string, body: unknown) {
	return {
		params: { packageId },
		request: new Request(`http://localhost/api/jafar/packages/${packageId}`, {
			method,
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

function publishEvent(body: unknown) {
	return event('POST', body) as unknown as Parameters<typeof PUBLISH>[0];
}

function client(result: { data: unknown; error: { code: string; message: string } | null }) {
	const rpc = vi.fn(() => Promise.resolve(result));
	mockedClient.mockReturnValue({ rpc } as never);
	return rpc;
}

describe('publishing a package draft', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 's' } as never);
	});

	it('refuses anyone who is not the platform owner', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const rpc = client({ data: null, error: null });
		const response = await PUBLISH(publishEvent({ edition_id: editionId, revision: 1 }));
		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('publishes the reviewed draft and revision, returning the new edition number', async () => {
		const rpc = client({
			data: { published: true, applied: true, edition_number: 2 },
			error: null
		});
		const response = await PUBLISH(publishEvent({ edition_id: editionId, revision: 4 }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ edition_number: 2 });
		expect(rpc).toHaveBeenCalledWith('publish_package_draft', {
			target_package_id: packageId,
			draft_edition_id: editionId,
			reviewed_revision: 4,
			actor_owner_email: 'owner@example.com'
		});
	});

	it('returns the newer draft with 409 when it was saved after the review', async () => {
		client({ data: { published: false, reason: 'stale', draft: { revision: 5 } }, error: null });
		const response = await PUBLISH(publishEvent({ edition_id: editionId, revision: 4 }));
		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ reason: 'stale', draft: { revision: 5 } });
	});

	it('lists every problem when the draft cannot be sold yet', async () => {
		const problems = [{ code: 'not_sellable', key: 'website_chat', message: 'Not ready.' }];
		client({ data: { published: false, reason: 'not_ready', problems }, error: null });
		const response = await PUBLISH(publishEvent({ edition_id: editionId, revision: 4 }));
		expect(response.status).toBe(422);
		expect(await response.json()).toMatchObject({ reason: 'not_ready', problems });
	});

	it('rejects a malformed request before touching the database', async () => {
		const rpc = client({ data: null, error: null });
		const response = await PUBLISH(publishEvent({ edition_id: 'nope', revision: 0 }));
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});
});

describe('package catalog actions', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 's' } as never);
	});

	it('makes a package public', async () => {
		const rpc = client({ data: { applied: true }, error: null });
		const response = await PATCH(
			event('PATCH', { action: 'set_visibility', visibility: 'public' })
		);
		expect(await response.json()).toEqual({ applied: true });
		expect(rpc).toHaveBeenCalledWith('set_package_visibility', {
			target_package_id: packageId,
			new_visibility: 'public',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('moves a package one place', async () => {
		const rpc = client({ data: { applied: true }, error: null });
		await PATCH(event('PATCH', { action: 'move', direction: 'down' }));
		expect(rpc).toHaveBeenCalledWith(
			'move_package',
			expect.objectContaining({ direction: 'down' })
		);
	});

	it('archives and restores through one command', async () => {
		const rpc = client({ data: { applied: true }, error: null });
		await PATCH(event('PATCH', { action: 'archive' }));
		await PATCH(event('PATCH', { action: 'restore' }));
		expect(rpc).toHaveBeenNthCalledWith(
			1,
			'set_package_archived',
			expect.objectContaining({ archived: true })
		);
		expect(rpc).toHaveBeenNthCalledWith(
			2,
			'set_package_archived',
			expect.objectContaining({ archived: false })
		);
	});

	it('explains why a never-published package cannot be archived', async () => {
		client({
			data: null,
			error: {
				code: '23514',
				message: 'This package was never published, so there is nothing to archive.'
			}
		});
		const response = await PATCH(event('PATCH', { action: 'archive' }));
		expect(response.status).toBe(409);
		expect((await response.json()).error).toMatch(/never published/);
	});

	it('confirms the website update for the reminder Jafar saw', async () => {
		const rpc = client({ data: { confirmed: true, applied: true }, error: null });
		const pendingSince = '2026-09-30T10:00:00.123456+00:00';
		const response = await PATCH(
			event('PATCH', { action: 'confirm_website', pending_since: pendingSince })
		);
		expect(await response.json()).toEqual({ applied: true });
		expect(rpc).toHaveBeenCalledWith('confirm_package_website_update', {
			target_package_id: packageId,
			seen_pending_since: pendingSince,
			actor_owner_email: 'owner@example.com'
		});
	});

	it('keeps the reminder open when the package changed again since Jafar saw it', async () => {
		client({ data: { confirmed: false, reason: 'stale' }, error: null });
		const response = await PATCH(
			event('PATCH', { action: 'confirm_website', pending_since: '2026-09-30T10:00:00Z' })
		);
		expect(response.status).toBe(409);
	});

	it('rejects an unknown action', async () => {
		const rpc = client({ data: null, error: null });
		const response = await PATCH(event('PATCH', { action: 'delete_everything' }));
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});
});
