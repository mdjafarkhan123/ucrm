import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { SETUP_CATALOGUE_1 } from '$lib/setup/catalogue.fixture';
import {
	onboardingNextActionLabel,
	onboardingStage,
	type OnboardingClient
} from '$lib/setup/onboarding-list';

vi.mock('$lib/server/setup/catalogue', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/setup/catalogue')>(
		'$lib/server/setup/catalogue'
	);
	const { SETUP_CATALOGUE_1 } = await import('$lib/setup/catalogue.fixture');
	return {
		...actual,
		readSetupCatalogue: vi.fn(async () => SETUP_CATALOGUE_1),
		readSetupSectionTitles: vi.fn(
			async () => new Map(SETUP_CATALOGUE_1.sections.map((section) => [section.key, section.title]))
		)
	};
});

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function event(url = 'http://localhost/api/jafar/onboarding') {
	return { url: new URL(url), params: {}, cookies: {} } as Parameters<typeof GET>[0];
}

function listResult(overrides: Record<string, unknown> = {}) {
	return {
		clients: [],
		next_cursor: null,
		totals: { all: 0, uplift: 0, client: 0, quiet: 0, matching: 0 },
		...overrides
	};
}

function mockRpc(data: unknown, error: unknown = null) {
	const rpc = vi.fn().mockResolvedValue({ data, error });
	mockedClient.mockReturnValue({ rpc } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

function client(overrides: Partial<OnboardingClient> = {}): OnboardingClient {
	return {
		id: 'org-1',
		name: 'Raad LTD',
		lifecycle_status: 'active',
		package_name: 'Starter',
		account_created_at: '2026-10-01T10:00:00Z',
		payment_reversed: false,
		welcome_seen: true,
		sections_done: 0,
		sections_total: 1,
		facts_total: 24,
		facts_answered: 3,
		help_count: 0,
		unread_support: 0,
		next_section_key: 'business',
		next_section_title: 'Your business',
		sent_number: null,
		sent_at: null,
		returned_count: 0,
		ready_at: null,
		target_from: null,
		target_to: null,
		provider_waits_open: 0,
		provider_waits_action: 0,
		preview_version: null,
		preview_released_at: null,
		preview_sent_at: null,
		preview_unsorted: 0,
		approval_status: null,
		approval_version: null,
		approval_requested_at: null,
		approval_not_yet_at: null,
		approved_at: null,
		project_state: 'complete_setup',
		waiting_on: 'client',
		next_action: 'finish_section',
		last_activity_at: '2026-10-01T10:00:00Z',
		quiet: false,
		...overrides
	};
}

describe('client onboarding list GET', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 'session-id' });
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an unknown filter before reaching the database', async () => {
		const response = await GET(event('http://localhost/api/jafar/onboarding?waiting_on=everyone'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a cursor it did not issue', async () => {
		const response = await GET(event('http://localhost/api/jafar/onboarding?cursor=not-a-cursor'));

		expect(response.status).toBe(422);
	});

	it("counts against today's task list and passes the filter through", async () => {
		const rpc = mockRpc(listResult());

		const response = await GET(
			event('http://localhost/api/jafar/onboarding?waiting_on=quiet&search=%20raad%20')
		);

		expect(response.status).toBe(200);
		const [name, args] = rpc.mock.calls[0];
		expect(name).toBe('owner_client_onboarding_list');
		expect(args.waiting_filter).toBe('quiet');
		expect(args.search_term).toBe('raad');
		expect(args.setup_catalogue.map((section: { key: string }) => section.key)).toEqual(
			SETUP_CATALOGUE_1.sections.map((section) => section.key)
		);
		const business = args.setup_catalogue[0];
		expect(business.required).toContain('business.public_name');
		expect(business.required).not.toContain('business.legal_name');
		expect(business.facts).toContain('business.legal_name');
	});

	it('names the next section as the published setup version titles it', async () => {
		const { next_section_title: _, ...row } = client();
		mockRpc(listResult({ clients: [row, { ...row, id: 'org-2', next_section_key: null }] }));

		const page = await (await GET(event())).json();

		expect(page.clients.map((entry: OnboardingClient) => entry.next_section_title)).toEqual([
			'Your business',
			null
		]);
	});

	it('shows Ready as Building from the client’s first business day after it (E1)', async () => {
		const { next_section_title: _, project_state: __, ...row } = client();
		const ready = {
			...row,
			sent_number: 1,
			sent_at: '2026-09-28T10:00:00Z',
			ready_at: '2026-09-29T10:00:00Z',
			target_from: '2026-10-08',
			target_to: '2026-10-13'
		};
		const rpc = vi.fn().mockResolvedValue({
			data: listResult({ clients: [ready, { ...row, id: 'org-2' }] }),
			error: null
		});
		const inIds = vi.fn().mockResolvedValue({
			data: [
				{
					organization_id: 'org-1',
					submission_number: 1,
					start_date: '2026-09-29',
					time_zone: 'Europe/London'
				}
			],
			error: null
		});
		const from = vi.fn(() => ({ select: () => ({ in: inIds }) }));
		mockedClient.mockReturnValue({ rpc, from } as unknown as ReturnType<
			typeof getOwnerSupabaseClient
		>);

		const page = await (await GET(event())).json();

		expect(from).toHaveBeenCalledWith('organization_setup_ready');
		expect(inIds).toHaveBeenCalledWith('organization_id', ['org-1']);
		expect(page.clients.map((entry: OnboardingClient) => entry.project_state)).toEqual([
			'building',
			'complete_setup'
		]);
		expect(onboardingStage(page.clients[0]).label).toBe('Building their system');
	});

	it('hands back an opaque cursor that round-trips into the next page', async () => {
		const rpc = mockRpc(
			listResult({ next_cursor: { account_created_at: '2026-10-01T10:00:00Z', id: 'org-1' } })
		);

		const first = await (await GET(event())).json();
		await GET(event(`http://localhost/api/jafar/onboarding?cursor=${first.next_cursor}`));

		expect(rpc.mock.calls[1][1]).toMatchObject({
			cursor_account_created_at: '2026-10-01T10:00:00Z',
			cursor_id: 'org-1'
		});
	});

	it('reports a database failure without leaking it', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => {});
		mockRpc(null, { message: 'boom' });

		const response = await GET(event());

		expect(response.status).toBe(500);
		expect((await response.json()).error).toBe('The client list could not be loaded.');
	});
});

describe('next step wording', () => {
	it('names the section to finish and counts what Uplift owes', () => {
		expect(onboardingNextActionLabel(client())).toBe('Finish Your business');
		expect(
			onboardingNextActionLabel(client({ next_action: 'reply_to_support', unread_support: 1 }))
		).toBe('Reply to 1 support chat');
		expect(
			onboardingNextActionLabel(client({ next_action: 'help_with_answers', help_count: 2 }))
		).toBe('Help with 2 answers');
	});

	it('puts a sent setup in Uplift’s hands and says when it was sent again', () => {
		const sent = client({
			next_action: 'review_setup',
			waiting_on: 'uplift',
			sent_number: 1,
			project_state: 'uplift_reviewing'
		});
		expect(onboardingNextActionLabel(sent)).toBe('Review their setup');
		expect(onboardingStage(sent).label).toBe('Uplift is reviewing');
		expect(onboardingNextActionLabel({ ...sent, sent_number: 2 })).toBe(
			'Review their changed setup'
		);
	});
});
