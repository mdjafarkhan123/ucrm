import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as postNote } from './notes/+server';
import { POST as postSend } from './send/+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { headObject } from '$lib/server/storage/r2';

// Client onboarding E3: the client's notes on a preview, and the one send.

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationAdmin: vi.fn() };
});
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});
vi.mock('$lib/server/storage/r2', async () => {
	const actual =
		await vi.importActual<typeof import('$lib/server/storage/r2')>('$lib/server/storage/r2');
	return { ...actual, headObject: vi.fn() };
});

const ORGANIZATION_ID = 'org-1';
const rpc = vi.fn();

function call(handler: (event: never) => Response | Promise<Response>, body: unknown) {
	return handler({
		locals: { supabase: { rpc } },
		url: new URL('http://localhost/api'),
		request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) })
	} as never);
}

describe('preview notes and send', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			auth: { organization: { id: ORGANIZATION_ID, role: 'owner' }, user: { id: 'user-1' } }
		} as never);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true } as never);
		rpc.mockResolvedValue({ data: { status: 'saved' }, error: null });
	});

	it('saves a change with its note through the client command', async () => {
		const response = await call(postNote, {
			version: 1,
			card_id: 'c1',
			choice: 'needs_change',
			note: '  The phone number is wrong  '
		});
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('client_save_setup_preview_note', {
			target_organization_id: ORGANIZATION_ID,
			target_version: 1,
			target_card_id: 'c1',
			new_choice: 'needs_change',
			new_note: 'The phone number is wrong',
			new_screenshots: []
		});
	});

	it('refuses a change without saying what', async () => {
		const response = await call(postNote, { version: 1, card_id: 'c1', choice: 'needs_change' });
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it("refuses a screenshot from another business's folder", async () => {
		const response = await call(postNote, {
			version: 1,
			card_id: 'c1',
			choice: 'needs_change',
			note: 'See this',
			screenshots: [
				{ object_key: 'org-2/setup-previews/a.png', file_name: 'a.png', mime_type: 'image/png' }
			]
		});
		expect(response.status).toBe(422);
		expect(headObject).not.toHaveBeenCalled();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('measures a screenshot in storage rather than trusting the browser', async () => {
		vi.mocked(headObject).mockResolvedValue({
			contentLength: 2048,
			contentType: 'image/png'
		} as never);
		await call(postNote, {
			version: 1,
			card_id: 'c1',
			choice: 'needs_change',
			note: 'See this',
			screenshots: [
				{ object_key: 'org-1/setup-previews/a.png', file_name: 'a.png', mime_type: 'image/png' }
			]
		});
		expect(rpc.mock.calls[0][1].new_screenshots).toEqual([
			{
				object_key: 'org-1/setup-previews/a.png',
				file_name: 'a.png',
				mime_type: 'image/png',
				byte_size: 2048,
				has_thumbnail: false
			}
		]);
	});

	it('passes the database refusal on when the notes were already sent or the version is old', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'Uplift has released a newer preview. Reload to see it.' }
		});
		const response = await call(postSend, { version: 1 });
		expect(response.status).toBe(422);
		expect(rpc).toHaveBeenCalledWith('client_send_setup_preview_notes', {
			target_organization_id: ORGANIZATION_ID,
			target_version: 1
		});
	});
});
