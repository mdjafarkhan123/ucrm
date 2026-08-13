import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

function query(data: unknown, error: null | { message: string } = null) {
	const builder = {
		select: () => builder,
		order: () => builder,
		limit: () => builder,
		eq: () => builder,
		neq: () => builder,
		maybeSingle: () => Promise.resolve({ data, error }),
		then: (resolve: (value: { data: unknown; error: null | { message: string } }) => unknown) =>
			Promise.resolve({ data, error }).then(resolve)
	};
	return builder;
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function detailEvent() {
	return {
		url: new URL('http://localhost/api/jafar/prospects/' + prospectId),
		params: { prospectId },
		cookies: {}
	} as Parameters<typeof GET>[0];
}

describe('platform owner prospect detail duplicate matches', () => {
	beforeEach(() => vi.clearAllMocks());

	it('does not query for matches when the application is not flagged as a possible duplicate', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const fromCalls: string[] = [];
		mockedClient.mockReturnValue({
			from: (table: string) => {
				fromCalls.push(table);
				return (
					{
						platform_onboarding_applications: query({
							id: prospectId,
							stage: 'new',
							business_name: 'Bright Co',
							main_contact_email: 'jamie@bright.co',
							initial_administrator_email: null,
							possible_duplicate: false
						}),
						platform_onboarding_application_submissions: query(null),
						platform_onboarding_application_corrections: query([]),
						platform_onboarding_application_setup_links: query(null)
					}[table] ?? query(null)
				);
			}
		} as never);

		const response = await GET(detailEvent());
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.duplicate_matches).toEqual([]);
		expect(fromCalls.filter((table) => table === 'platform_onboarding_applications')).toHaveLength(
			1
		);
	});

	it('returns matching records and reasons for a possible duplicate', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const matchRow = {
			id: 'other-application',
			business_name: 'Bright Co',
			main_contact_email: 'jamie@bright.co',
			initial_administrator_email: null,
			stage: 'awaiting_payment',
			submitted_at: '2026-08-01T00:00:00.000Z'
		};
		let applicationsCallCount = 0;
		mockedClient.mockReturnValue({
			from: (table: string) => {
				if (table === 'platform_onboarding_applications') {
					applicationsCallCount += 1;
					if (applicationsCallCount === 1)
						return query({
							id: prospectId,
							stage: 'new',
							business_name: 'Bright Co',
							main_contact_email: 'jamie@bright.co',
							initial_administrator_email: null,
							possible_duplicate: true
						});
					return query([matchRow]);
				}
				return (
					{
						platform_onboarding_application_submissions: query(null),
						platform_onboarding_application_corrections: query([]),
						platform_onboarding_application_setup_links: query(null)
					}[table] ?? query(null)
				);
			}
		} as never);

		const response = await GET(detailEvent());
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.duplicate_matches).toHaveLength(1);
		expect(body.duplicate_matches[0].id).toBe('other-application');
		expect(body.duplicate_matches[0].matched_on).toEqual(
			expect.arrayContaining(['Same contact email', 'Same business name'])
		);
	});

	it('returns payment confirmations, reversals, and provisioning status for visibility into needs_attention', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const confirmation = {
			id: 'confirmation-1',
			actor_owner_email: 'owner@example.com',
			amount_usd_cents: 14900,
			currency: 'USD',
			private_reference: 'ref-1',
			mismatch_reason: null,
			confirmed_at: '2026-08-10T00:00:00.000Z'
		};
		const reversal = {
			id: 'reversal-1',
			actor_owner_email: 'owner@example.com',
			reason: 'Bank confirmed the transfer was reversed.',
			reversed_amount_usd_cents: 14900,
			reversed_at: '2026-08-11T00:00:00.000Z'
		};
		const provision = {
			status: 'failed',
			last_error: 'Auth user creation timed out.',
			attempt_count: 2,
			updated_at: '2026-08-11T00:05:00.000Z'
		};
		mockedClient.mockReturnValue({
			from: (table: string) =>
				({
					platform_onboarding_applications: query({
						id: prospectId,
						stage: 'needs_attention',
						business_name: 'Bright Co',
						main_contact_email: 'jamie@bright.co',
						initial_administrator_email: null,
						possible_duplicate: false,
						payment_reversed_at: '2026-08-11T00:00:00.000Z'
					}),
					platform_onboarding_application_submissions: query(null),
					platform_onboarding_application_corrections: query([]),
					platform_onboarding_application_setup_links: query(null),
					platform_onboarding_application_payment_confirmations: query([confirmation]),
					platform_onboarding_application_payment_reversals: query([reversal]),
					platform_onboarding_application_provisions: query(provision)
				})[table] ?? query(null)
		} as never);

		const response = await GET(detailEvent());
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.payment_confirmations).toEqual([confirmation]);
		expect(body.payment_reversals).toEqual([reversal]);
		expect(body.provision).toEqual(provision);
		expect(body.prospect.payment_reversed_at).toBe('2026-08-11T00:00:00.000Z');
	});

	it('returns empty history and a null provision when none exist yet', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue({
			from: (table: string) =>
				({
					platform_onboarding_applications: query({
						id: prospectId,
						stage: 'new',
						business_name: 'Bright Co',
						main_contact_email: 'jamie@bright.co',
						initial_administrator_email: null,
						possible_duplicate: false,
						payment_reversed_at: null
					}),
					platform_onboarding_application_submissions: query(null),
					platform_onboarding_application_corrections: query([]),
					platform_onboarding_application_setup_links: query(null)
				})[table] ?? query(null)
		} as never);

		const response = await GET(detailEvent());
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.payment_confirmations).toEqual([]);
		expect(body.payment_reversals).toEqual([]);
		expect(body.provision).toBeNull();
	});
});
