import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const templateRow = {
	template_key: 'password_setup',
	subject_draft: 'Set up your {{business_name}} account',
	body_draft: 'Click {{setup_link}} to continue.',
	subject_published: 'Set up your {{business_name}} account',
	body_published: 'Click {{setup_link}} to continue.',
	published_version: 1,
	published_at: '2026-08-12T00:00:00Z',
	published_by_owner_email: 'system'
};

function single(data: unknown, error: null | { message: string } = null) {
	return { maybeSingle: () => Promise.resolve({ data, error }) };
}

function readEvent(templateKey = 'password_setup') {
	return {
		params: { templateKey },
		url: new URL('http://localhost/api/jafar/message-templates/' + templateKey),
		cookies: {}
	} as Parameters<typeof GET>[0];
}

function patchEvent(templateKey: string, body: unknown) {
	return {
		params: { templateKey },
		request: new Request('http://localhost/api/jafar/message-templates/' + templateKey, {
			method: 'PATCH',
			body: typeof body === 'string' ? body : JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/message-templates/' + templateKey),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

describe('platform owner single message template API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	describe('GET', () => {
		it('rejects callers without the separate owner session', async () => {
			mockedOwnerSession.mockReturnValue(null);
			const response = await GET(readEvent());
			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('rejects an unknown template key', async () => {
			mockedOwnerSession.mockReturnValue(session());
			const response = await GET(readEvent('not_a_real_key'));
			expect(response.status).toBe(404);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('returns 404 when the template row does not exist', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedClient.mockReturnValue({
				from: (table: string) =>
					table === 'platform_message_templates'
						? { select: () => ({ eq: () => single(null) }) }
						: { select: () => ({ eq: () => ({ order: () => Promise.resolve({ data: [], error: null }) }) }) }
			} as never);

			const response = await GET(readEvent());
			expect(response.status).toBe(404);
		});

		it('returns the template, its version history, and its placeholder catalog', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedClient.mockReturnValue({
				from: (table: string) =>
					table === 'platform_message_templates'
						? { select: () => ({ eq: () => single(templateRow) }) }
						: {
								select: () => ({
									eq: () => ({
										order: () =>
											Promise.resolve({
												data: [
													{
														version: 1,
														subject: templateRow.subject_published,
														body: templateRow.body_published,
														published_at: templateRow.published_at,
														published_by_owner_email: 'system'
													}
												],
												error: null
											})
									})
								})
							}
			} as never);

			const response = await GET(readEvent());
			expect(response.status).toBe(200);
			const body = await response.json();
			expect(body.template.template_key).toBe('password_setup');
			expect(body.versions).toHaveLength(1);
			expect(body.placeholders).toEqual(
				expect.arrayContaining([expect.objectContaining({ key: 'setup_link' })])
			);
		});

		it('returns a safe server error when the template read fails', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedClient.mockReturnValue({
				from: (table: string) =>
					table === 'platform_message_templates'
						? { select: () => ({ eq: () => single(null, { message: 'internal database details' }) }) }
						: { select: () => ({ eq: () => ({ order: () => Promise.resolve({ data: [], error: null }) }) }) }
			} as never);

			const response = await GET(readEvent());
			expect(response.status).toBe(500);
			expect(await response.json()).toEqual({ error: 'The message template could not be loaded.' });
		});
	});

	describe('PATCH', () => {
		it('rejects callers without the separate owner session', async () => {
			mockedOwnerSession.mockReturnValue(null);
			const response = await PATCH(patchEvent('password_setup', { body_draft: 'x' }));
			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('rejects an unknown template key', async () => {
			mockedOwnerSession.mockReturnValue(session());
			const response = await PATCH(patchEvent('not_a_real_key', { body_draft: 'x' }));
			expect(response.status).toBe(404);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('rejects invalid JSON bodies', async () => {
			mockedOwnerSession.mockReturnValue(session());
			const response = await PATCH(patchEvent('password_setup', 'not json'));
			expect(response.status).toBe(400);
		});

		it('rejects a draft body that is too long', async () => {
			mockedOwnerSession.mockReturnValue(session());
			const response = await PATCH(
				patchEvent('password_setup', { body_draft: 'x'.repeat(20001) })
			);
			expect(response.status).toBe(422);
			const body = await response.json();
			expect(body.field_errors.body_draft).toBeDefined();
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('saves the draft and returns the updated row', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedClient.mockReturnValue({
				from: () => ({
					update: (values: unknown) => ({
						eq: () => ({
							select: () => single({ ...templateRow, ...(values as Record<string, unknown>) })
						})
					})
				})
			} as never);

			const response = await PATCH(
				patchEvent('password_setup', { subject_draft: 'New subject', body_draft: 'New body {{setup_link}}' })
			);
			expect(response.status).toBe(200);
			const body = await response.json();
			expect(body.template.body_draft).toBe('New body {{setup_link}}');
		});

		it('returns a safe server error when the update fails', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedClient.mockReturnValue({
				from: () => ({
					update: () => ({
						eq: () => ({ select: () => single(null, { message: 'internal database details' }) })
					})
				})
			} as never);

			const response = await PATCH(patchEvent('password_setup', { body_draft: 'x' }));
			expect(response.status).toBe(500);
			expect(await response.json()).toEqual({ error: 'The draft could not be saved.' });
		});
	});
});
