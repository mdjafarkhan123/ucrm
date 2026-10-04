import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as listDocuments } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSetupCatalogue } from '$lib/server/setup/catalogue';
import { buildSetupCatalogue, type SetupCatalogueRow } from '$lib/setup/catalogue';
import { SETUP_VERSION_1 } from '$lib/setup/catalogue.fixture';

// Client onboarding B9b: Jafar's list of one client's protected setup documents.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/setup/catalogue', () => ({ readSetupCatalogue: vi.fn() }));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const HELD_ID = '22222222-2222-4222-8222-222222222222';
const LOOSE_ID = '33333333-3333-4333-8333-333333333333';

const CATALOGUE_ROW: SetupCatalogueRow = {
	...SETUP_VERSION_1,
	stages: [
		{
			...SETUP_VERSION_1.stages[0],
			items: [
				...SETUP_VERSION_1.stages[0].items,
				{
					type: 'question',
					fact_key: 'business.port_bill',
					label: 'Upload a recent phone bill.',
					hint: null,
					built_in: false,
					required: false,
					can_defer: false,
					kind: 'protected_file',
					options: null,
					max_files: 5,
					max_length: null
				}
			]
		}
	]
};

const row = (id: string, factKey: string) => ({
	id,
	fact_key: factKey,
	display_name: 'bill.pdf',
	size_bytes: 2048,
	state: 'ready',
	problem: null,
	upload_completed_at: '2026-10-04T10:00:00Z',
	delete_after: null,
	deleted_at: null
});

/** A query that resolves to `result` however it is narrowed, and records what it was asked. */
function query(result: unknown, calls: unknown[][]) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'in', 'order', 'limit'])
		builder[method] = (...args: unknown[]) => {
			calls.push([method, ...args]);
			return builder;
		};
	builder.then = (resolve: (value: unknown) => void) => resolve(result);
	return builder;
}

function request(organizationId = ORGANIZATION_ID) {
	return { params: { organizationId } } as unknown as Parameters<typeof listDocuments>[0];
}

describe('Jafar’s list of a client’s protected documents', () => {
	let documentCalls: unknown[][];
	let answerCalls: unknown[][];

	beforeEach(() => {
		vi.mocked(getOwnerSession).mockResolvedValue({ email: 'owner@example.com' } as never);
		vi.mocked(readSetupCatalogue).mockResolvedValue(buildSetupCatalogue(CATALOGUE_ROW));
		documentCalls = [];
		answerCalls = [];
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: (table: string) =>
				table === 'setup_protected_documents'
					? query(
							{
								data: [row(HELD_ID, 'business.port_bill'), row(LOOSE_ID, 'business.old_question')],
								error: null
							},
							documentCalls
						)
					: query({ data: [{ value: [HELD_ID] }], error: null }, answerCalls)
		} as never);
	});

	it('is Jafar’s only', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await listDocuments(request());
		expect(response.status).toBe(401);
	});

	it('names each question and says whether its answer still holds the document', async () => {
		const response = await listDocuments(request());
		expect(response.status).toBe(200);
		const { documents } = await response.json();
		expect(documents).toMatchObject([
			{ id: HELD_ID, question: 'Upload a recent phone bill.', in_answer: true },
			// A question no longer asked reads by its key.
			{ id: LOOSE_ID, question: 'business.old_question', in_answer: false }
		]);
		expect(documentCalls).toContainEqual(['eq', 'organization_id', ORGANIZATION_ID]);
		expect(answerCalls).toContainEqual(['eq', 'organization_id', ORGANIZATION_ID]);
		expect(answerCalls).toContainEqual(['eq', 'availability', 'have']);
	});

	it('says an unknown organization is not found', async () => {
		const response = await listDocuments(request('not-an-id'));
		expect(response.status).toBe(404);
	});
});
