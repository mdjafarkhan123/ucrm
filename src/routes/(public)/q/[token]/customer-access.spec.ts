import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// The page awaits the document RPC directly; the file route asks for one row of the file RPC.
const documentRpc = vi.fn();
const fileLookup = vi.fn();
const rpc = vi.fn((name: string, args: unknown) =>
	name === 'resolve_quote_access_file' ? { maybeSingle: () => fileLookup(args) } : documentRpc(name, args)
);
const from = vi.fn();
const getObjectStream = vi.fn();

vi.mock('$lib/server/db/owner-supabase', () => ({
	getOwnerSupabaseClient: () => ({ rpc, from })
}));
vi.mock('$lib/server/storage/r2', () => ({ getObjectStream }));

const { load } = await import('./+page.server');
const { GET: readFile } = await import('./files/[attachmentId=uuid]/+server');

const token = 'a'.repeat(43);
const tokenHash = `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;

const document = {
	quote: { quote_number: 41, status: 'awaiting_response' },
	recipient: { name: 'Dana', email: 'dana@example.com' },
	business: { name: 'Northside Roofing' },
	document: { version_number: 2, show_totals: true },
	lines: [{ id: 'line-1', image_file_id: 'photo-1' }],
	attachments: [{ id: 'file-1', name: 'Scope.pdf', mime_type: 'application/pdf' }],
	totals: { total_minor: 120000 }
};

function pageEvent(pathToken: string) {
	return {
		params: { token: pathToken },
		setHeaders: vi.fn()
	} as unknown as Parameters<typeof load>[0] & { setHeaders: ReturnType<typeof vi.fn> };
}

function fileEvent(pathToken: string, attachmentId: string, search = '') {
	return {
		params: { token: pathToken, attachmentId },
		url: new URL(`https://app.example.com/q/${pathToken}/files/${attachmentId}${search}`)
	} as unknown as Parameters<typeof readFile>[0];
}

// `load` is declared with SvelteKit's own return type, which allows returning nothing. This test always
// gets the object back, so it says so once here rather than at every call.
async function open(pathToken: string) {
	const event = pageEvent(pathToken);
	const answer = (await load(event)) as { document: unknown };
	return { answer, event };
}

describe('opening a customer link', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		documentRpc.mockResolvedValue({ data: document, error: null });
	});

	it('hashes the token and never sends the token itself', async () => {
		await open(token);
		expect(rpc).toHaveBeenCalledWith('resolve_quote_access_link', {
			supplied_token_hash: tokenHash
		});
		expect(JSON.stringify(rpc.mock.calls[0])).not.toContain(token);
	});

	it('keeps the page out of caches, search results and referrers', async () => {
		const { event } = await open(token);
		const headers = event.setHeaders.mock.calls[0][0] as Record<string, string>;
		expect(headers['cache-control']).toBe('no-store');
		expect(headers['referrer-policy']).toBe('no-referrer');
		expect(headers['x-robots-tag']).toContain('noindex');
	});

	it('does not go near the database for a token of the wrong shape', async () => {
		for (const bad of ['', 'short', `${token}extra`, '../../etc/passwd', 'a'.repeat(42) + '!']) {
			const { answer } = await open(bad);
			expect(answer.document).toBeNull();
		}
		expect(rpc).not.toHaveBeenCalled();
	});

	it('gives the same empty answer for unknown, revoked and superseded links', async () => {
		documentRpc.mockResolvedValue({ data: null, error: null });
		expect((await open(token)).answer.document).toBeNull();

		documentRpc.mockResolvedValue({ data: null, error: { message: 'boom' } });
		expect((await open(token)).answer.document).toBeNull();
	});

	it('passes the document through exactly as the database shaped it', async () => {
		const { answer } = await open(token);
		expect(answer.document).toBe(document);
	});
});

describe('files on a customer link', () => {
	const fileId = '11111111-1111-4111-8111-111111111111';
	const photoId = '22222222-2222-4222-8222-222222222222';

	beforeEach(() => {
		vi.clearAllMocks();
		fileLookup.mockResolvedValue({
			data: {
				object_key: 'org/quote/file-1.pdf',
				thumbnail_object_key: null,
				mime_type: 'application/pdf',
				display_name: 'Scope.pdf'
			},
			error: null
		});
		getObjectStream.mockResolvedValue({ body: null, contentType: null, contentLength: 12 });
	});

	it('asks for this one file by token hash, never building the whole document', async () => {
		const response = await readFile(fileEvent(token, fileId));
		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toContain('private');
		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith('resolve_quote_access_file', {
			supplied_token_hash: tokenHash,
			target_file_id: fileId
		});
		expect(documentRpc).not.toHaveBeenCalled();
		expect(JSON.stringify(rpc.mock.calls[0])).not.toContain(token);
	});

	it('hands over anything that is not a photo as a download, never inline', async () => {
		const response = await readFile(fileEvent(token, fileId));
		expect(response.headers.get('content-disposition')).toBe('attachment; filename="Scope.pdf"');
		expect(response.headers.get('x-content-type-options')).toBe('nosniff');
	});

	it('shows a line photo on the page', async () => {
		fileLookup.mockResolvedValue({
			data: {
				object_key: 'org/quote/photo-1.jpg',
				thumbnail_object_key: 'org/quote/photo-1-thumb.jpg',
				mime_type: 'image/jpeg',
				display_name: 'photo.jpg'
			},
			error: null
		});
		const response = await readFile(fileEvent(token, photoId, '?size=thumb'));
		expect(response.headers.get('content-disposition')).toBe('inline');
		expect(getObjectStream).toHaveBeenCalledWith('org/quote/photo-1-thumb.jpg');
	});

	it('refuses a file the link does not name, or any file once the link stops resolving', async () => {
		fileLookup.mockResolvedValue({ data: null, error: null });
		await expect(readFile(fileEvent(token, fileId))).rejects.toMatchObject({ status: 404 });

		fileLookup.mockResolvedValue({ data: null, error: { message: 'boom' } });
		await expect(readFile(fileEvent(token, fileId))).rejects.toMatchObject({ status: 404 });
		expect(getObjectStream).not.toHaveBeenCalled();
	});

	it('does not go near the database for a token of the wrong shape', async () => {
		await expect(readFile(fileEvent('short', fileId))).rejects.toMatchObject({ status: 404 });
		expect(rpc).not.toHaveBeenCalled();
	});

	it('answers a broken storage read the same way as a missing file', async () => {
		getObjectStream.mockRejectedValue(new Error('r2 is down'));
		await expect(readFile(fileEvent(token, fileId))).rejects.toMatchObject({ status: 404 });
	});
});
