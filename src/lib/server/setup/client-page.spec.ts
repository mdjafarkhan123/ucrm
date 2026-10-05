import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SETUP_CATALOGUE_1, SETUP_VERSION_1 } from '$lib/setup/catalogue.fixture';
import { readClientSetupView } from '$lib/server/setup/client-page';
import { readSetupState } from '$lib/server/setup/read';

vi.mock('$lib/server/setup/catalogue', () => ({
	readSetupCatalogue: vi.fn(async () => SETUP_CATALOGUE_1),
	readSetupServiceKeys: vi.fn(async () => new Set<string>())
}));
vi.mock('$lib/server/setup/files', () => ({ readSetupFiles: vi.fn(async () => []) }));
vi.mock('$lib/server/setup/read', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/setup/read')>()),
	readSetupState: vi.fn()
}));

const ORG = '11111111-1111-4111-8111-111111111111';
const have = (value: string) => ({ availability: 'have', value, note: null });

function submission(number: number, answers: Record<string, unknown>) {
	return {
		submission_number: number,
		setup_version_id: 'old-version',
		service_keys: [],
		answers,
		confirmations: [{ key: 'accurate', wording: 'The information is accurate.' }],
		confirmations_version: '2026-10-04',
		submitted_by_name: 'Sam Owner',
		submitted_by_email: 'sam@example.com',
		submitted_at: `2026-10-0${number}T10:00:00Z`
	};
}

/** A stand-in for the service-role client: each table answers from `rows`, filtered by `eq`. */
function fakeSupabase(rows: {
	submissions: ReturnType<typeof submission>[];
	reminders: unknown;
	reviews?: unknown[];
	help?: unknown[];
	ready?: unknown;
	lifecycle?: string;
	paymentReversed?: boolean;
}) {
	const rpc = vi.fn(async () => ({ data: SETUP_VERSION_1, error: null }));
	const from = (table: string) => {
		const filters: Record<string, unknown> = {};
		const result = () => {
			if (table === 'organization_setup_reminders') return rows.reminders;
			if (table === 'organization_setup_section_reviews') return rows.reviews ?? [];
			if (table === 'organization_setup_help_answers') return rows.help ?? [];
			if (table === 'organization_setup_ready') return rows.ready ?? null;
			if (table === 'organization_setup_settings_copies') return [];
			if (table === 'organizations') return { lifecycle_status: rows.lifecycle ?? 'active' };
			if (table === 'organization_settings') return { timezone: 'Europe/London' };
			if (table === 'platform_onboarding_application_provisions')
				return [
					{
						platform_onboarding_applications: {
							payment_reversed_at: rows.paymentReversed ? '2026-10-03T10:00:00Z' : null
						}
					}
				];
			return rows.submissions
				.filter((row) =>
					'submission_number' in filters
						? Array.isArray(filters.submission_number)
							? filters.submission_number.includes(row.submission_number)
							: row.submission_number === filters.submission_number
						: true
				)
				.sort((a, b) => b.submission_number - a.submission_number);
		};
		const builder = {
			select: () => builder,
			order: () => builder,
			eq: (column: string, value: unknown) => {
				filters[column] = value;
				return builder;
			},
			in: (column: string, values: unknown[]) => {
				filters[column] = values;
				return builder;
			},
			maybeSingle: async () => {
				const found = result();
				return { data: Array.isArray(found) ? (found[0] ?? null) : found, error: null };
			},
			then: (resolve: (value: unknown) => void) => resolve({ data: result(), error: null })
		};
		return builder;
	};
	return { client: { from, rpc } as never, rpc };
}

const REMINDERS = {
	paused_at: null,
	next_due_at: null,
	reminders_sent: 0,
	last_sent_at: null
};

describe('readClientSetupView', () => {
	beforeEach(() => {
		vi.mocked(readSetupState).mockResolvedValue({
			welcomeSeen: true,
			answers: {
				'business.public_name': { availability: 'have', value: 'Acme Roofing Ltd', note: null }
			},
			doneSections: new Set(['business']),
			sent: null,
			ready: null
		});
	});

	it('shows reminders and no send before the client has sent anything', async () => {
		const { client } = fakeSupabase({ submissions: [], reminders: REMINDERS });
		const view = await readClientSetupView(client, ORG, null);
		expect(view).toEqual({
			sends: [],
			send: null,
			reviews: null,
			help: null,
			help_units: { country: null, currency: null },
			unsent_changes: 0,
			reminders: REMINDERS,
			ready: null,
			ready_blockers: [{ kind: 'not_sent' }],
			time_zone: 'Europe/London',
			settings_copies: []
		});
	});

	it('names every task not accepted on the newest send, and the account, as blockers to Ready', async () => {
		const { client } = fakeSupabase({
			submissions: [submission(1, { 'business.public_name': have('Acme Roofing') })],
			reminders: REMINDERS,
			lifecycle: 'suspended',
			paymentReversed: true
		});
		const view = await readClientSetupView(client, ORG, null);
		expect(view?.ready_blockers).toEqual([
			{ kind: 'account_paused' },
			{ kind: 'payment_reversed' },
			...view!.send!.sections.map((section) => ({
				kind: 'task',
				section_key: section.key,
				section_title: section.title,
				state: 'to_review'
			}))
		]);
	});

	it('has no blockers once every task of the newest send is accepted, and reads a recorded Ready', async () => {
		const ready = {
			submission_number: 1,
			ready_at: '2026-10-05T09:00:00Z',
			ready_by_email: 'jafar@example.com',
			time_zone: 'Europe/London',
			start_date: '2026-10-05',
			target_from: '2026-10-14',
			target_to: '2026-10-19'
		};
		const first = fakeSupabase({
			submissions: [submission(1, { 'business.public_name': have('Acme Roofing') })],
			reminders: REMINDERS
		});
		const sections = (await readClientSetupView(first.client, ORG, null))!.send!.sections;
		const { client } = fakeSupabase({
			submissions: [submission(1, { 'business.public_name': have('Acme Roofing') })],
			reminders: REMINDERS,
			reviews: sections.map((section) => ({
				section_key: section.key,
				decision: 'accepted',
				submission_number: 1,
				note: null,
				question_keys: [],
				reviewed_by_email: 'jafar@example.com',
				reviewed_at: '2026-10-05T08:00:00Z'
			})),
			ready
		});
		const view = await readClientSetupView(client, ORG, null);
		expect(view?.ready_blockers).toEqual([]);
		expect(view?.ready).toEqual(ready);
	});

	it('reads the newest send against its own version and marks what changed since the one before', async () => {
		const { client, rpc } = fakeSupabase({
			submissions: [
				submission(1, { 'business.public_name': have('Acme Roofing') }),
				submission(2, { 'business.public_name': have('Acme Roofing Ltd') })
			],
			reminders: REMINDERS
		});

		const view = await readClientSetupView(client, ORG, null);

		expect(rpc).toHaveBeenCalledWith('owner_setup_version_catalogue', {
			target_version_id: 'old-version'
		});
		expect(view?.sends.map((send) => send.number)).toEqual([2, 1]);
		expect(view?.send?.number).toBe(2);
		expect(view?.send?.compared_with).toBe(1);
		expect(view?.send?.changed_count).toBe(1);
		const name = view?.send?.sections[0].items.find((item) => item.key === 'business.public_name');
		expect(name).toMatchObject({ state: 'answered', lines: ['Acme Roofing Ltd'], changed: true });
		// The draft still matches the newest send.
		expect(view?.unsent_changes).toBe(0);
	});

	it('counts draft changes the client has not sent yet', async () => {
		vi.mocked(readSetupState).mockResolvedValue({
			welcomeSeen: true,
			answers: { 'business.public_name': have('Acme Roofing & Sons') } as never,
			doneSections: new Set(['business']),
			sent: null,
			ready: null
		});
		const { client } = fakeSupabase({
			submissions: [submission(1, { 'business.public_name': have('Acme Roofing') })],
			reminders: REMINDERS
		});

		const view = await readClientSetupView(client, ORG, null);
		expect(view?.send?.compared_with).toBeNull();
		expect(view?.send?.changed_count).toBe(0);
		expect(view?.unsent_changes).toBe(1);
	});

	it('shows an earlier send when asked, and refuses one that does not exist', async () => {
		const { client } = fakeSupabase({
			submissions: [
				submission(1, { 'business.public_name': have('Acme Roofing') }),
				submission(2, { 'business.public_name': have('Acme Roofing Ltd') })
			],
			reminders: null
		});

		const first = await readClientSetupView(client, ORG, 1);
		expect(first?.send?.number).toBe(1);
		expect(first?.send?.sections[0].items[0]).toMatchObject({ lines: ['Acme Roofing'] });
		expect(first?.reminders).toBeNull();
		// Decisions are made on the newest send only.
		expect(first?.reviews).toBeNull();

		expect(await readClientSetupView(client, ORG, 7)).toBeNull();
	});

	describe('Uplift’s review of each section (C3)', () => {
		const decision = (number: number, kind: 'accepted' | 'returned') => ({
			section_key: 'business',
			decision: kind,
			submission_number: number,
			note: kind === 'returned' ? 'Use your trading name.' : null,
			question_keys: kind === 'returned' ? ['business.public_name'] : [],
			reviewed_by_email: 'jafar@example.com',
			reviewed_at: '2026-10-05T10:00:00Z'
		});
		const twoSends = (second: string) => [
			submission(1, { 'business.public_name': have('Acme Roofing') }),
			submission(2, { 'business.public_name': have(second) })
		];

		it('starts every section as to review', async () => {
			const { client } = fakeSupabase({ submissions: twoSends('Acme Roofing'), reminders: null });
			const view = await readClientSetupView(client, ORG, null);
			expect(view?.reviews?.business).toEqual({ state: 'to_review', decision: null });
		});

		it('keeps an earlier acceptance while the section is unchanged', async () => {
			const { client } = fakeSupabase({
				submissions: twoSends('Acme Roofing'),
				reminders: null,
				reviews: [decision(1, 'accepted')]
			});
			const view = await readClientSetupView(client, ORG, null);
			expect(view?.reviews?.business.state).toBe('accepted');
		});

		it('puts an accepted section back for review once the client sends a change to it', async () => {
			const { client } = fakeSupabase({
				submissions: twoSends('Acme Roofing Ltd'),
				reminders: null,
				reviews: [decision(1, 'accepted')]
			});
			const view = await readClientSetupView(client, ORG, null);
			expect(view?.reviews?.business.state).toBe('changed');
		});

		it('waits on the client after a return, and on Uplift again once they send', async () => {
			const returnedNow = fakeSupabase({
				submissions: twoSends('Acme Roofing'),
				reminders: null,
				reviews: [decision(2, 'returned')]
			});
			const now = await readClientSetupView(returnedNow.client, ORG, null);
			expect(now?.reviews?.business).toMatchObject({
				state: 'returned',
				decision: { note: 'Use your trading name.', question_keys: ['business.public_name'] }
			});

			const returnedBefore = fakeSupabase({
				submissions: twoSends('Acme Roofing Ltd'),
				reminders: null,
				reviews: [decision(1, 'returned')]
			});
			const later = await readClientSetupView(returnedBefore.client, ORG, null);
			expect(later?.reviews?.business.state).toBe('resent');
		});
	});
	describe('Uplift’s to-do (C3c)', () => {
		const needHelp = (note: string | null) => ({ availability: 'need_help', value: null, note });
		const send = submission(1, {
			'business.public_name': have('Acme Roofing'),
			'business.public_phone': needHelp('We need a number'),
			'business.public_email': needHelp(null)
		});

		it('lists each help request, open ones first, with the answer Uplift recorded', async () => {
			const { client } = fakeSupabase({
				submissions: [send],
				reminders: null,
				help: [
					{
						fact_key: 'business.public_phone',
						value: '+44 20 7946 0000',
						note: null,
						recorded_by_email: 'jafar@example.com',
						recorded_at: '2026-10-05T10:00:00Z'
					}
				]
			});
			const view = await readClientSetupView(client, ORG, null);
			expect(view?.help?.map((item) => [item.fact_key, item.answer?.lines ?? null])).toEqual([
				['business.public_email', null],
				['business.public_phone', ['+44 20 7946 0000']]
			]);
			expect(view?.help?.[1]).toMatchObject({ client_note: 'We need a number', form: 'box' });
		});

		it('ignores an answer to a question the client has since answered themselves', async () => {
			const { client } = fakeSupabase({
				submissions: [submission(1, { 'business.public_phone': have('+44 20 7946 1111') })],
				reminders: null,
				help: [
					{
						fact_key: 'business.public_phone',
						value: '+44 20 7946 0000',
						note: null,
						recorded_by_email: 'jafar@example.com',
						recorded_at: '2026-10-05T10:00:00Z'
					}
				]
			});
			expect((await readClientSetupView(client, ORG, null))?.help).toEqual([]);
		});
	});
});
