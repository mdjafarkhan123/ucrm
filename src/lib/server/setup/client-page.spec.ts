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
function fakeSupabase(rows: { submissions: ReturnType<typeof submission>[]; reminders: unknown }) {
	const rpc = vi.fn(async () => ({ data: SETUP_VERSION_1, error: null }));
	const from = (table: string) => {
		const filters: Record<string, unknown> = {};
		const result = () => {
			if (table === 'organization_setup_reminders') return rows.reminders;
			return rows.submissions
				.filter((row) =>
					'submission_number' in filters
						? row.submission_number === filters.submission_number
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
			sent: null
		});
	});

	it('shows reminders and no send before the client has sent anything', async () => {
		const { client } = fakeSupabase({ submissions: [], reminders: REMINDERS });
		const view = await readClientSetupView(client, ORG, null);
		expect(view).toEqual({ sends: [], send: null, unsent_changes: 0, reminders: REMINDERS });
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
			sent: null
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

		expect(await readClientSetupView(client, ORG, 7)).toBeNull();
	});
});
