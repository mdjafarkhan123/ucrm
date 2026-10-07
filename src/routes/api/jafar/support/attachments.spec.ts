import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as postReply } from './threads/[threadId]/messages/+server';
import { POST as presign } from './threads/[threadId]/attachments/presign-upload/+server';
import { GET as getFile } from './attachments/[id]/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	createPresignedDownloadUrl,
	createPresignedUploadUrl,
	headObject
} from '$lib/server/storage/r2';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/storage/r2', async () => {
	const actual =
		await vi.importActual<typeof import('$lib/server/storage/r2')>('$lib/server/storage/r2');
	return {
		...actual,
		createPresignedDownloadUrl: vi.fn(),
		createPresignedUploadUrl: vi.fn(),
		headObject: vi.fn()
	};
});

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedHead = vi.mocked(headObject);
const mockedUploadUrl = vi.mocked(createPresignedUploadUrl);
const mockedDownloadUrl = vi.mocked(createPresignedDownloadUrl);

const THREAD_ID = '123e4567-e89b-12d3-a456-426614174000';
const CLIENT_MESSAGE_ID = '223e4567-e89b-12d3-a456-426614174000';
const FILE_ID = '323e4567-e89b-12d3-a456-426614174000';

function use(rows: { support_threads?: unknown; support_message_attachments?: unknown }) {
	const rpc = vi.fn().mockResolvedValue({ data: { id: 'message-1' }, error: null });
	const from = vi.fn((table: string) => {
		const chain = {
			select: () => chain,
			eq: () => chain,
			maybeSingle: () =>
				Promise.resolve({ data: rows[table as keyof typeof rows] ?? null, error: null })
		};
		return chain;
	});
	const value = { from, rpc };
	mockedClient.mockReturnValue(value as never);
	return value;
}

function event(options: { body?: unknown; query?: string } = {}) {
	return {
		params: { threadId: THREAD_ID, id: FILE_ID },
		url: new URL(`http://localhost/api/jafar/support/x${options.query ?? ''}`),
		request: new Request('http://localhost/api/jafar/support', {
			method: 'POST',
			body: options.body === undefined ? undefined : JSON.stringify(options.body)
		}),
		cookies: {}
	} as never;
}

const claim = { file_name: 'guide.pdf', mime_type: 'application/pdf', size_bytes: 1024 };
const reply = (objectKey: string) => ({
	body: '',
	client_message_id: CLIENT_MESSAGE_ID,
	attachments: [{ object_key: objectKey, file_name: 'guide.pdf', mime_type: 'application/pdf' }]
});

beforeEach(() => {
	vi.clearAllMocks();
	mockedOwnerSession.mockResolvedValue({
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		memberId: null,
		name: null
	});
	mockedHead.mockResolvedValue({ contentLength: 1024, contentType: 'application/pdf' });
	mockedUploadUrl.mockImplementation(async (key) => `https://storage.example/${key}`);
	mockedDownloadUrl.mockResolvedValue('https://storage.example/signed-download');
});

describe('Support Inbox files', () => {
	it.each([
		['an upload link', () => presign(event({ body: claim }))],
		['a file', () => getFile(event())]
	])('refuses %s without the platform owner session', async (_name, call) => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await call();
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('uploads Uplift’s file under the contractor’s own organization', async () => {
		use({ support_threads: { organization_id: 'org-7' } });
		const response = await presign(event({ body: claim }));
		expect(response.status).toBe(200);
		expect((await response.json()).object_key).toMatch(/^org-7\/support-attachments\//);
	});

	it('refuses an upload link for a chat that no longer exists, and for a program file', async () => {
		use({});
		expect((await presign(event({ body: claim }))).status).toBe(404);
		expect((await presign(event({ body: { ...claim, file_name: 'tool.exe' } }))).status).toBe(422);
		expect(mockedUploadUrl).not.toHaveBeenCalled();
	});

	it('replies with a file alone, measured in storage', async () => {
		const value = use({ support_threads: { organization_id: 'org-7' } });
		const response = await postReply(
			event({ body: reply('org-7/support-attachments/abc-guide.pdf') })
		);
		expect(response.status).toBe(201);
		expect(value.rpc).toHaveBeenCalledWith(
			'reply_to_support_thread',
			expect.objectContaining({
				message_body: '',
				message_attachments: [expect.objectContaining({ file_name: 'guide.pdf', byte_size: 1024 })]
			})
		);
	});

	it('refuses a reply whose file sits under a different organization than the chat', async () => {
		const value = use({ support_threads: { organization_id: 'org-7' } });
		const response = await postReply(
			event({ body: reply('org-8/support-attachments/abc-guide.pdf') })
		);
		expect(response.status).toBe(422);
		expect(value.rpc).not.toHaveBeenCalled();
	});

	it('downloads a file from any contractor’s chat', async () => {
		use({
			support_message_attachments: {
				object_key: 'org-7/support-attachments/abc-guide.pdf',
				file_name: 'guide.pdf',
				mime_type: 'application/pdf',
				has_thumbnail: false
			}
		});
		const response = await getFile(event({ query: '?download=1' }));
		expect(response.status).toBe(302);
		expect(response.headers.get('location')).toBe('https://storage.example/signed-download');
	});
});
