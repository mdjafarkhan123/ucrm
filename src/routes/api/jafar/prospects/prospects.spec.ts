import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as list } from './+server';
import { GET as detail } from './[prospectId]/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
let capturedSearchFilter: string | undefined;

function query(data: unknown, error: null | { message: string } = null) {
	const builder = {
		select: () => builder,
		order: () => builder,
		limit: () => builder,
		eq: () => builder,
		or: (value: string) => {
			capturedSearchFilter = value;
			return builder;
		},
		maybeSingle: () => Promise.resolve({ data, error }),
		then: (resolve: (value: { data: unknown; error: null | { message: string } }) => unknown) =>
			Promise.resolve({ data, error }).then(resolve)
	};
	return builder;
}

function event(url = 'http://localhost/api/jafar/prospects') {
	return { url: new URL(url), params: {}, cookies: {} } as Parameters<typeof list>[0];
}

describe('platform owner prospect read API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		capturedSearchFilter = undefined;
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await list(event());
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns filtered prospect summaries', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: () => query([{ id: 'prospect-1', stage: 'new', business_name: 'Bright Co' }])
		} as never);

		const response = await list(
			event('http://localhost/api/jafar/prospects?stage=new&search=Bright')
		);
		expect(response.status).toBe(200);
		expect((await response.json()).prospects[0].business_name).toBe('Bright Co');
	});

	it('escapes search syntax before building the database filter', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({ from: () => query([]) } as never);

		const response = await list(
			event('http://localhost/api/jafar/prospects?search=%25%2C%28Bright%29')
		);

		expect(response.status).toBe(200);
		expect(capturedSearchFilter).toContain('\\%');
		expect(capturedSearchFilter).not.toContain('%(Bright)');
		expect(capturedSearchFilter?.split(',')).toHaveLength(3);
	});

	it('returns a safe server error when the prospect list query fails', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: () => query([], { message: 'internal database details' })
		} as never);

		const response = await list(event());

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Prospects could not be loaded.' });
	});

	it('returns the application and immutable history', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: (table: string) =>
				({
					platform_onboarding_applications: query({ id: 'prospect-1', stage: 'new' }),
					platform_onboarding_application_submissions: query({ application_id: 'prospect-1' }),
					platform_onboarding_application_corrections: query([{ id: 'correction-1' }]),
					platform_onboarding_application_setup_links: query(null)
				})[table] as never
		} as never);

		const detailEvent = {
			...event(),
			params: { prospectId: '123e4567-e89b-12d3-a456-426614174000' }
		} as unknown as Parameters<typeof detail>[0];
		const response = await detail(detailEvent);
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.original_submission.application_id).toBe('prospect-1');
		expect(body.corrections).toHaveLength(1);
		expect(body.setup_link).toBeNull();
	});

	it('rejects an invalid prospect identifier', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		const response = await detail({
			...event(),
			params: { prospectId: 'not-a-uuid' }
		} as unknown as Parameters<typeof detail>[0]);
		expect(response.status).toBe(422);
	});
});
