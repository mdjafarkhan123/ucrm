import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as postDraft } from './+server';
import { POST as postRelease } from './release/+server';
import { POST as postSort } from './sort/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { sendPreviewReadyEmails } from '$lib/server/setup/preview';

// Client onboarding E3: Jafar writes, releases and sorts a client's preview.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$env/dynamic/private', () => ({ env: {} }));
vi.mock('$lib/server/setup/preview', () => ({
	readOwnerPreviews: vi.fn(),
	sendPreviewReadyEmails: vi.fn()
}));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();

function call(handler: typeof postDraft, body: unknown) {
	return handler({
		params: { organizationId: ORGANIZATION_ID },
		url: new URL('http://localhost/api'),
		request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) })
	} as never);
}

const card = {
	id: 'c1',
	title: 'Website',
	summary: 'Five pages',
	link: 'https://preview.example.com'
};

describe("Jafar's preview", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
		rpc.mockResolvedValue({ data: { status: 'saved', version: 1 }, error: null });
		vi.mocked(sendPreviewReadyEmails).mockResolvedValue(1);
	});

	it('needs the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		expect((await call(postDraft, { cards: [card] })).status).toBe(401);
		expect((await call(postRelease, { version: 1 })).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('saves the draft whole, and refuses a link that is not https', async () => {
		expect((await call(postDraft, { cards: [card] })).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_save_setup_preview', {
			target_organization_id: ORGANIZATION_ID,
			new_cards: [{ ...card, screenshots: [] }],
			actor_email: 'owner@example.com'
		});

		rpc.mockClear();
		const bad = await call(postDraft, { cards: [{ ...card, link: 'http://example.com' }] });
		expect(bad.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('emails the client on release, and says when that email failed', async () => {
		rpc.mockResolvedValue({ data: { status: 'released', version: 1 }, error: null });
		expect(await (await call(postRelease, { version: 1 })).json()).toMatchObject({
			status: 'released',
			emailed: true
		});
		expect(sendPreviewReadyEmails).toHaveBeenCalledWith(expect.anything(), {
			organizationId: ORGANIZATION_ID,
			version: 1,
			origin: 'http://localhost'
		});

		vi.mocked(sendPreviewReadyEmails).mockRejectedValueOnce(new Error('outbox down'));
		expect(await (await call(postRelease, { version: 1 })).json()).toMatchObject({
			emailed: false
		});
	});

	it('sorts a note with one of the three labels only', async () => {
		expect((await call(postSort, { version: 1, card_id: 'c1', kind: 'urgent' })).status).toBe(422);
		await call(postSort, { version: 1, card_id: 'c1', kind: 'uplift_error' });
		expect(rpc).toHaveBeenCalledWith('owner_sort_setup_preview_note', {
			target_organization_id: ORGANIZATION_ID,
			target_version: 1,
			target_card_id: 'c1',
			new_kind: 'uplift_error',
			actor_email: 'owner@example.com'
		});
	});
});
