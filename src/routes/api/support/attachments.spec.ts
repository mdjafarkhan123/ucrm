import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as postMessage } from './messages/+server';
import { POST as startChat } from './threads/+server';
import { POST as presign } from './attachments/presign-upload/+server';
import { GET as getFile } from './attachments/[id]/+server';
import { requireSupportMember } from '$lib/server/support/access';
import { unauthorized } from '$lib/server/api/errors';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	createPresignedDownloadUrl,
	createPresignedUploadUrl,
	getObjectStream,
	headObject
} from '$lib/server/storage/r2';

// Who counts as a support member is the database's answer (support_member_context, tested in
// access.spec.ts); these tests start from that answer.
vi.mock('$lib/server/support/access', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/support/access')>(
		'$lib/server/support/access'
	);
	return { ...actual, requireSupportMember: vi.fn() };
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
	return {
		...actual,
		createPresignedDownloadUrl: vi.fn(),
		createPresignedUploadUrl: vi.fn(),
		getObjectStream: vi.fn(),
		headObject: vi.fn()
	};
});

const mockedAccess = vi.mocked(requireSupportMember);
const mockedContext = {
	mockResolvedValue: (context: unknown) =>
		mockedAccess.mockResolvedValue(
			context ? { auth: context as never } : { response: unauthorized() }
		)
};
const mockedRateLimit = vi.mocked(checkRateLimit);
const mockedHead = vi.mocked(headObject);
const mockedUploadUrl = vi.mocked(createPresignedUploadUrl);
const mockedDownloadUrl = vi.mocked(createPresignedDownloadUrl);
const mockedStream = vi.mocked(getObjectStream);

const CLIENT_MESSAGE_ID = '123e4567-e89b-12d3-a456-426614174000';
const THREAD_ID = '223e4567-e89b-12d3-a456-426614174000';
const FILE_ID = '323e4567-e89b-12d3-a456-426614174000';
const MB = 1024 * 1024;

function supabase(attachment: unknown = null) {
	const eq = vi.fn();
	const chain = {
		select: () => chain,
		eq: (...args: unknown[]) => {
			eq(...args);
			return chain;
		},
		maybeSingle: () => Promise.resolve({ data: attachment, error: null })
	};
	return {
		from: vi.fn(() => chain),
		rpc: vi.fn().mockResolvedValue({ data: { id: 'message-1' }, error: null }),
		eq
	};
}

function event(
	client: ReturnType<typeof supabase>,
	options: { body?: unknown; query?: string; id?: string } = {}
) {
	return {
		locals: { supabase: client },
		params: { id: options.id ?? FILE_ID },
		url: new URL(`http://localhost/api/support/attachments/x${options.query ?? ''}`),
		request: new Request('http://localhost/api/support', {
			method: 'POST',
			body: options.body === undefined ? undefined : JSON.stringify(options.body)
		})
	} as never;
}

const upload = (name: string, extra: Record<string, unknown> = {}) => ({
	object_key: `org-1/support-attachments/abc-${name}`,
	file_name: name,
	mime_type: 'application/pdf',
	...extra
});

const message = (attachments: unknown[], body = '') => ({
	body,
	client_message_id: CLIENT_MESSAGE_ID,
	thread_id: THREAD_ID,
	attachments
});

beforeEach(() => {
	vi.clearAllMocks();
	mockedContext.mockResolvedValue({
		organization: {
			id: 'org-1',
			name: 'Bright Spark Electrical',
			slug: 'bright-spark',
			role: 'field'
		},
		user: { id: 'user-1', email: 'sam@example.com' }
	} as never);
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	mockedHead.mockResolvedValue({ contentLength: 2 * MB, contentType: 'application/pdf' });
	mockedUploadUrl.mockImplementation(async (key) => `https://storage.example/${key}`);
	mockedDownloadUrl.mockResolvedValue('https://storage.example/signed-download');
});

describe('sending files to Uplift', () => {
	it('sends files with no words, using the size storage reports rather than the browser', async () => {
		const client = supabase();
		const response = await postMessage(
			event(client, { body: message([upload('quote.pdf', { byte_size: 1 })]) })
		);
		expect(response.status).toBe(201);
		expect(client.rpc).toHaveBeenCalledWith('send_support_message', {
			target_organization_id: 'org-1',
			target_thread_id: THREAD_ID,
			message_body: '',
			message_client_id: CLIENT_MESSAGE_ID,
			message_attachments: [
				{
					object_key: 'org-1/support-attachments/abc-quote.pdf',
					file_name: 'quote.pdf',
					mime_type: 'application/pdf',
					byte_size: 2 * MB,
					has_thumbnail: false
				}
			]
		});
	});

	it('keeps a photo’s small copy only when storage really holds one', async () => {
		mockedHead.mockImplementation(async (key) => {
			if (key.endsWith('missing.jpg.thumb.jpg')) throw new Error('not found');
			return key.endsWith('.thumb.jpg')
				? { contentLength: 30_000, contentType: 'image/jpeg' }
				: { contentLength: MB, contentType: 'image/jpeg' };
		});
		const client = supabase();
		await postMessage(
			event(client, {
				body: message([
					upload('roof.jpg', { mime_type: 'image/jpeg', has_thumbnail: true }),
					upload('missing.jpg', { mime_type: 'image/jpeg', has_thumbnail: true })
				])
			})
		);
		const sent = client.rpc.mock.calls[0][1].message_attachments;
		expect(sent.map((file: { has_thumbnail: boolean }) => file.has_thumbnail)).toEqual([
			true,
			false
		]);
	});

	it('carries files with the first message of a new chat', async () => {
		const client = supabase();
		const response = await startChat(
			event(client, {
				body: {
					body: 'See attached',
					client_message_id: CLIENT_MESSAGE_ID,
					attachments: [upload('a.pdf')]
				}
			})
		);
		expect(response.status).toBe(201);
		expect(client.rpc).toHaveBeenCalledWith(
			'start_support_thread',
			expect.objectContaining({
				message_attachments: [expect.objectContaining({ file_name: 'a.pdf', byte_size: 2 * MB })]
			})
		);
	});

	it.each([
		['a program file', message([upload('setup.exe')])],
		['more than 5 files', message(['a', 'b', 'c', 'd', 'e', 'f'].map((n) => upload(`${n}.pdf`)))],
		['a message with neither words nor files', message([])]
	])('rejects %s before storage or the database', async (_name, body) => {
		const client = supabase();
		const response = await postMessage(event(client, { body }));
		expect(response.status).toBe(422);
		expect(mockedHead).not.toHaveBeenCalled();
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses a file uploaded under another organization', async () => {
		const client = supabase();
		const response = await postMessage(
			event(client, {
				body: message([upload('a.pdf', { object_key: 'org-2/support-attachments/abc-a.pdf' })])
			})
		);
		expect(response.status).toBe(422);
		expect(mockedHead).not.toHaveBeenCalled();
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses files that total more than 20 MB', async () => {
		mockedHead.mockResolvedValue({ contentLength: 11 * MB, contentType: 'application/pdf' });
		const client = supabase();
		const response = await postMessage(
			event(client, { body: message([upload('a.pdf'), upload('b.pdf')]) })
		);
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.attachments).toBe(
			'Attachments must total 20 MB or less.'
		);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses a file whose upload never finished', async () => {
		mockedHead.mockRejectedValue(new Error('not found'));
		const client = supabase();
		const response = await postMessage(event(client, { body: message([upload('a.pdf')]) }));
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});
});

describe('POST /api/support/attachments/presign-upload', () => {
	const claim = (name: string, type: string, size = MB) => ({
		file_name: name,
		mime_type: type,
		size_bytes: size
	});

	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const response = await presign(event(supabase(), { body: claim('a.pdf', 'application/pdf') }));
		expect(response.status).toBe(401);
		expect(mockedUploadUrl).not.toHaveBeenCalled();
	});

	it('issues a key under the caller’s own organization, with no small copy for a document', async () => {
		const response = await presign(
			event(supabase(), { body: claim('a b.pdf', 'application/pdf') })
		);
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.object_key).toMatch(/^org-1\/support-attachments\/[0-9a-f-]{36}-a_b\.pdf$/);
		expect(body.thumbnail_upload_url).toBeNull();
	});

	it('also issues somewhere for a photo’s small copy', async () => {
		const response = await presign(event(supabase(), { body: claim('roof.jpg', 'image/jpeg') }));
		const body = await response.json();
		expect(body.thumbnail_upload_url).toBe(`https://storage.example/${body.object_key}.thumb.jpg`);
	});

	it.each([
		['a program file', claim('setup.exe', 'application/octet-stream')],
		['a file over 20 MB', claim('big.pdf', 'application/pdf', 21 * MB)],
		['an empty file', claim('empty.pdf', 'application/pdf', 0)]
	])('rejects %s', async (_name, body) => {
		const response = await presign(event(supabase(), { body }));
		expect(response.status).toBe(422);
		expect(mockedUploadUrl).not.toHaveBeenCalled();
	});

	it('stops a flood of uploads', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const response = await presign(event(supabase(), { body: claim('a.pdf', 'application/pdf') }));
		expect(response.status).toBe(429);
	});
});

describe('GET /api/support/attachments/[id]', () => {
	const pdf = {
		object_key: 'org-1/support-attachments/abc-quote.pdf',
		file_name: 'quote.pdf',
		mime_type: 'application/pdf',
		has_thumbnail: false
	};
	const photo = {
		object_key: 'org-1/support-attachments/abc-roof.jpg',
		file_name: 'roof.jpg',
		mime_type: 'image/jpeg',
		has_thumbnail: true
	};

	it('answers 404 for a file row level security hides, and reads only the caller’s organization', async () => {
		const client = supabase(null);
		const response = await getFile(event(client));
		expect(response.status).toBe(404);
		expect(client.eq).toHaveBeenCalledWith('organization_id', 'org-1');
	});

	it('answers 404 for an id that is not an id, without asking the database', async () => {
		const client = supabase(pdf);
		const response = await getFile(event(client, { id: 'nope' }));
		expect(response.status).toBe(404);
		expect(client.from).not.toHaveBeenCalled();
	});

	it('hands a document over as a download', async () => {
		const response = await getFile(event(supabase(pdf), { query: '?download=1' }));
		expect(response.status).toBe(302);
		expect(response.headers.get('location')).toBe('https://storage.example/signed-download');
		expect(mockedDownloadUrl).toHaveBeenCalledWith(pdf.object_key, 'quote.pdf');
	});

	it('never shows a document on the page', async () => {
		const response = await getFile(event(supabase(pdf)));
		expect(response.status).toBe(415);
		expect(mockedStream).not.toHaveBeenCalled();
	});

	it('shows a photo with the stored picture type, and its small copy when asked', async () => {
		mockedStream.mockResolvedValue({
			body: new ReadableStream(),
			contentType: 'text/html',
			contentLength: 10
		});
		const full = await getFile(event(supabase(photo)));
		expect(full.status).toBe(200);
		expect(full.headers.get('content-type')).toBe('image/jpeg');
		expect(full.headers.get('x-content-type-options')).toBe('nosniff');
		expect(mockedStream).toHaveBeenLastCalledWith(photo.object_key);

		await getFile(event(supabase(photo), { query: '?size=thumb' }));
		expect(mockedStream).toHaveBeenLastCalledWith(`${photo.object_key}.thumb.jpg`);
	});
});
