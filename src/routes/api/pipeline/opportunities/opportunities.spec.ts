import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission, hasPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedHasPermission = vi.mocked(hasPermission);

const organizationId = '00000000-0000-4000-8000-0000000000aa';
const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
	access: {}
} as never;

// One board row, shaped the way `pipeline_board_page` answers it since the migration that added the
// card's open Task. Every column the route does not touch is filled with a value the mapping should
// pass straight through untouched.
function boardRow(overrides: Record<string, unknown> = {}) {
	return {
		id: 'opp-1',
		title: 'Rewire the panel',
		stage: 'new_request',
		stage_entered_at: '2026-08-10T00:00:00.000Z',
		outcome: 'open',
		created_at: '2026-08-10T00:00:00.000Z',
		request_id: 'req-1',
		request_status: 'new',
		client_id: 'client-1',
		client_display_name: 'Ada Lovelace',
		client_company_name: null,
		property_id: null,
		property_label: null,
		property_address_line1: null,
		property_city: null,
		property_state_region: null,
		property_postal_code: null,
		owner_user_id: null,
		owner_full_name: null,
		owner_avatar_url: null,
		estimated_value: null,
		expected_close_on: null,
		next_follow_up_on: null,
		task_id: null,
		task_title: null,
		task_due_on: null,
		quote_id: null,
		quote_status: null,
		assessment_starts_at: null,
		assessment_ends_at: null,
		...overrides
	};
}

function readEvent(rows: unknown[], query = 'stage=new_request') {
	const rpc = vi.fn().mockResolvedValue({ data: rows, error: null });
	return {
		url: new URL(`http://localhost/api/pipeline/opportunities?${query}`),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}

// The rpc mock, so a test can read back what the route actually asked the database for.
function rpcOf(event: Parameters<typeof GET>[0]) {
	return (event.locals as unknown as { supabase: { rpc: ReturnType<typeof vi.fn> } }).supabase.rpc;
}

describe('board column task field', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	it('carries the card open Task through when the function found one', async () => {
		const response = await GET(
			readEvent([
				boardRow({ task_id: 'task-1', task_title: 'Call Colin', task_due_on: '2026-09-05' })
			])
		);

		const body = await response.json();
		expect(body.opportunities[0].task).toEqual({
			id: 'task-1',
			title: 'Call Colin',
			due_on: '2026-09-05'
		});
	});

	it('is null when the Opportunity has no open Task', async () => {
		const response = await GET(readEvent([boardRow()]));

		const body = await response.json();
		expect(body.opportunities[0].task).toBeNull();
	});
});

describe('board column quote pointer', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	it('carries the quote pointer through for a Quote-backed card', async () => {
		const response = await GET(
			readEvent([
				boardRow({
					stage: 'quote_draft',
					request_id: null,
					request_status: null,
					quote_id: 'quote-1',
					quote_status: 'draft'
				})
			])
		);

		const body = await response.json();
		expect(body.opportunities[0].quote).toEqual({ id: 'quote-1', status: 'draft' });
		expect(body.opportunities[0].request).toBeNull();
	});

	it('is null for a Request-backed card', async () => {
		const response = await GET(readEvent([boardRow()]));

		const body = await response.json();
		expect(body.opportunities[0].quote).toBeNull();
	});
});

// The collapsed Assessment column asks for one named logical column, and the database maps it to the three
// protected stages. From this route's side the important thing is that it is one page in one order, not
// three lists stitched together: the cards come back interleaved across sub-states and the cursor it hands
// out continues that single walk.
describe('the collapsed Assessment column', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	function assessmentCard(id: string, stage: string, enteredAt: string, extra = {}) {
		return boardRow({ id, stage, stage_entered_at: enteredAt, request_status: stage, ...extra });
	}

	it('asks the database for the logical column by name', async () => {
		const event = readEvent([], 'stage=assessment');
		await GET(event);

		expect(rpcOf(event)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({ target_stage: 'assessment' })
		);
	});

	it('carries the booked appointment through for a scheduled card', async () => {
		const response = await GET(
			readEvent(
				[
					assessmentCard('opp-2', 'assessment_scheduled', '2026-08-20T00:00:00.000Z', {
						assessment_starts_at: '2026-09-01T09:00:00.000Z',
						assessment_ends_at: '2026-09-01T10:00:00.000Z'
					})
				],
				'stage=assessment'
			)
		);

		expect((await response.json()).opportunities[0].assessment).toEqual({
			starts_at: '2026-09-01T09:00:00.000Z',
			ends_at: '2026-09-01T10:00:00.000Z'
		});
	});

	it('leaves the appointment null for a card nobody has scheduled', async () => {
		const response = await GET(
			readEvent(
				[assessmentCard('opp-3', 'assessment_unscheduled', '2026-08-20T00:00:00.000Z')],
				'stage=assessment'
			)
		);

		expect((await response.json()).opportunities[0].assessment).toBeNull();
	});

	it('keeps every card its own real stage, so the badge can say which one', async () => {
		const response = await GET(
			readEvent(
				[
					assessmentCard('opp-a', 'assessment_scheduled', '2026-08-22T00:00:00.000Z'),
					assessmentCard('opp-b', 'assessment_unscheduled', '2026-08-21T00:00:00.000Z'),
					assessmentCard('opp-c', 'assessment_completed', '2026-08-20T00:00:00.000Z')
				],
				'stage=assessment'
			)
		);

		const body = await response.json();
		expect(body.stage).toBe('assessment');
		expect(body.opportunities.map((card: { stage: string }) => card.stage)).toEqual([
			'assessment_scheduled',
			'assessment_unscheduled',
			'assessment_completed'
		]);
	});

	// The page boundary is the dangerous place: if the column were three lists, a cursor cut in the middle
	// would restart at the top of the next sub-state and repeat or skip cards. It is one keyset, so the
	// marker is simply the last card on the page, whichever sub-state it happened to be in.
	it('pages on from wherever the previous page ended, even mid sub-state', async () => {
		const page = [
			assessmentCard('opp-a', 'assessment_scheduled', '2026-08-22T00:00:00.000Z'),
			assessmentCard('opp-b', 'assessment_unscheduled', '2026-08-21T00:00:00.000Z'),
			// The extra row that only says "there is more".
			assessmentCard('opp-c', 'assessment_completed', '2026-08-20T00:00:00.000Z')
		];

		const first = await GET(readEvent(page, 'stage=assessment&limit=2'));
		const firstBody = await first.json();

		expect(firstBody.opportunities).toHaveLength(2);
		expect(firstBody.next_cursor).toBe('assessment:stage:1:2026-08-21T00:00:00.000Z|opp-b');

		const second = readEvent(
			[assessmentCard('opp-c', 'assessment_completed', '2026-08-20T00:00:00.000Z')],
			`stage=assessment&limit=2&cursor=${encodeURIComponent(firstBody.next_cursor)}`
		);
		const secondResponse = await GET(second);

		expect(secondResponse.status).toBe(200);
		expect(rpcOf(second)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({
				target_stage: 'assessment',
				cursor_timestamp: '2026-08-21T00:00:00.000Z',
				cursor_id: 'opp-b'
			})
		);
	});
});

describe('a page marker only works where it was cut', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	async function refusedFor(query: string) {
		const event = readEvent([], query);
		const response = await GET(event);
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.cursor).toBe('Start this column again.');
		// Refused before the database is asked anything, so a replay cannot be timed either.
		expect(rpcOf(event)).not.toHaveBeenCalled();
	}

	// The one this part adds. A marker from the grouped column replayed against a single stage would page
	// a set of cards that column never showed.
	it('refuses a cursor from another column', async () => {
		await refusedFor('stage=new_request&cursor=assessment:stage:1:2026-08-21T00:00:00.000Z|opp-b');
	});

	it('refuses a cursor from the same column in another order', async () => {
		await refusedFor('stage=assessment&cursor=assessment:created:1:2026-08-21T00:00:00.000Z|opp-b');
	});

	it('refuses a marker written before columns were bound in', async () => {
		await refusedFor('stage=assessment&cursor=stage:1:2026-08-21T00:00:00.000Z|opp-b');
	});

	it('accepts its own marker', async () => {
		const event = readEvent(
			[],
			'stage=assessment&cursor=assessment:stage:1:2026-08-21T00:00:00.000Z|opp-b'
		);
		expect((await GET(event)).status).toBe(200);
		expect(rpcOf(event)).toHaveBeenCalled();
	});
});
