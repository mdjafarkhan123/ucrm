import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function single(data: unknown, error: null | { message: string } = null) {
	return { maybeSingle: () => Promise.resolve({ data, error }) };
}

function event(templateKey: string, body?: unknown) {
	return {
		params: { templateKey },
		request: new Request(
			'http://localhost/api/jafar/message-templates/' + templateKey + '/restore-version',
			{
				method: 'POST',
				body: body === undefined ? undefined : JSON.stringify(body),
				headers: { 'content-type': 'application/json' }
			}
		),
		url: new URL('http://localhost/api/jafar/message-templates/' + templateKey + '/restore-version'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

const originalVersion = { subject: 'Original subject', body: 'Original body {{setup_link}}' };

function clientWith(
	versionResult: { data: unknown; error: null | { message: string } },
	updateResult?: { data: unknown; error: null | { message: string } }
) {
	return {
		from: (table: string) =>
			table === 'platform_message_template_versions'
				? { select: () => ({ eq: () => ({ eq: () => single(versionResult.data, versionResult.error) }) }) }
				: {
						update: () => ({
							eq: () => ({
								select: () => single(updateResult?.data ?? null, updateResult?.error ?? null)
							})
						})
					}
	};
}

describe('platform owner message template restore-version API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event('password_setup'));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an unknown template key', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not_a_real_key'));
		expect(response.status).toBe(404);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects invalid JSON bodies', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = {
			params: { templateKey: 'password_setup' },
			request: new Request('http://localhost/x', { method: 'POST', body: 'not json' }),
			url: new URL('http://localhost/x'),
			cookies: {}
		} as Parameters<typeof POST>[0];
		const result = await POST(response);
		expect(result.status).toBe(400);
	});

	it('rejects an invalid version number', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('password_setup', { version: 0 }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the requested version does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ data: null, error: null }) as never);

		const response = await POST(event('password_setup', { version: 5 }));
		expect(response.status).toBe(404);
	});

	it('defaults to version 1 (the original default wording) when no version is given', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith(
				{ data: originalVersion, error: null },
				{
					data: {
						template_key: 'password_setup',
						subject_draft: originalVersion.subject,
						body_draft: originalVersion.body
					},
					error: null
				}
			) as never
		);

		const response = await POST(event('password_setup'));
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.template.body_draft).toBe(originalVersion.body);
	});

	it('restores an explicit historical version into the draft', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const olderVersion = { subject: 'Older subject', body: 'Older body {{setup_link}}' };
		mockedClient.mockReturnValue(
			clientWith(
				{ data: olderVersion, error: null },
				{
					data: {
						template_key: 'password_setup',
						subject_draft: olderVersion.subject,
						body_draft: olderVersion.body
					},
					error: null
				}
			) as never
		);

		const response = await POST(event('password_setup', { version: 2 }));
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.template.body_draft).toBe(olderVersion.body);
	});

	it('returns a safe server error when the update fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith(
				{ data: originalVersion, error: null },
				{ data: null, error: { message: 'internal database details' } }
			) as never
		);

		const response = await POST(event('password_setup'));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The draft could not be restored.' });
	});
});
