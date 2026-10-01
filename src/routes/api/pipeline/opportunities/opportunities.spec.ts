import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { encodeBoardCursor } from '$lib/server/pipeline/board';
import { requireOrganizationPermission, hasPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));

// The Task order asks what day it is for the contractor, so every test reads a fixed calendar.
vi.mock('$lib/server/requests/timezone', () => ({
	organizationFormatting: vi.fn().mockResolvedValue({
		ok: true,
		formatting: { timezone: 'UTC', currency_code: 'USD', locale: 'en-US' }
	})
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
		progress_at: '2026-08-10T00:00:00.000Z',
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
		next_task_due_on: null,
		task_id: null,
		task_title: null,
		task_due_on: null,
		quote_id: null,
		quote_status: null,
		assessment_starts_at: null,
		assessment_ends_at: null,
		custom_stage_id: null,
		quote_delivery_failed_at: null,
		quote_delivery_failed_email: null,
		quote_delivery_failure: null,
		client_lead_source: null,
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
		expect(body.opportunities[0].quote).toEqual({
			id: 'quote-1',
			status: 'draft',
			delivery_failure: null
		});
		expect(body.opportunities[0].request).toBeNull();
	});

	it('says when the quote email did not reach the customer', async () => {
		const response = await GET(
			readEvent([
				boardRow({
					stage: 'quote_awaiting_response',
					request_id: null,
					request_status: null,
					quote_id: 'quote-1',
					quote_status: 'awaiting_response',
					quote_delivery_failure: 'bounced',
					quote_delivery_failed_at: '2026-10-01T09:00:00.000Z',
					quote_delivery_failed_email: 'ada@example.com'
				})
			])
		);

		const body = await response.json();
		expect(body.opportunities[0].quote.delivery_failure).toEqual({
			reason: 'bounced',
			failed_at: '2026-10-01T09:00:00.000Z',
			recipient_email: 'ada@example.com'
		});
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
describe('the Table view', () => {
	it('asks the database for every card at once, through the same function', async () => {
		const event = readEvent([], 'stage=all&sort=created');
		const response = await GET(event);

		expect(response.status).toBe(200);
		expect(rpcOf(event)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({ target_stage: 'all', sort_key: 'created_at' })
		);
	});

	it('refuses a marker cut from one column when paging the whole table', async () => {
		const cursor = encodeBoardCursor({
			column: 'new_request',
			sort: 'created',
			phase: 1,
			value: '2026-08-19T04:00:00.000Z',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		});
		const event = readEvent([], `stage=all&sort=created&cursor=${encodeURIComponent(cursor)}`);
		const response = await GET(event);

		expect(response.status).toBe(422);
		expect(rpcOf(event)).not.toHaveBeenCalled();
	});
});

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

		const first = await GET(readEvent(page, 'stage=assessment&sort=stage&limit=2'));
		const firstBody = await first.json();

		expect(firstBody.opportunities).toHaveLength(2);
		expect(firstBody.next_cursor).toBe('assessment:stage:1:2026-08-21T00:00:00.000Z|opp-b');

		const second = readEvent(
			[assessmentCard('opp-c', 'assessment_completed', '2026-08-20T00:00:00.000Z')],
			`stage=assessment&sort=stage&limit=2&cursor=${encodeURIComponent(firstBody.next_cursor)}`
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
			'stage=assessment&sort=stage&cursor=assessment:stage:1:2026-08-21T00:00:00.000Z|opp-b'
		);
		expect((await GET(event)).status).toBe(200);
		expect(rpcOf(event)).toHaveBeenCalled();
	});
});

describe('a custom follow-up column', () => {
	const stageId = '7b0c8f2e-0000-4000-8000-000000000001';

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(false);
	});

	it('asks the database for the stage by its id', async () => {
		const event = readEvent([], `stage=${stageId.toUpperCase()}`);
		const response = await GET(event);

		expect(response.status).toBe(200);
		expect(rpcOf(event)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({ target_stage: stageId })
		);
	});

	it('keeps the real stage on a placed card and says where it was placed', async () => {
		const response = await GET(
			readEvent([boardRow({ stage: 'quote_draft', custom_stage_id: stageId })], `stage=${stageId}`)
		);
		const body = await response.json();

		expect(body.opportunities[0].stage).toBe('quote_draft');
		expect(body.opportunities[0].custom_stage_id).toBe(stageId);
	});

	it('pages with a marker cut from that same stage and refuses one from another', async () => {
		const own = await GET(
			readEvent(
				[],
				`stage=${stageId}&sort=stage&cursor=${stageId}:stage:1:2026-08-21T00:00:00.000Z|opp-b`
			)
		);
		expect(own.status).toBe(200);

		const other = await GET(
			readEvent([], `stage=${stageId}&cursor=quote_draft:stage:1:2026-08-21T00:00:00.000Z|opp-b`)
		);
		expect(other.status).toBe(422);
	});

	it('says the column has gone when the stage was switched off', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '22023' } });
		const response = await GET({
			url: new URL(`http://localhost/api/pipeline/opportunities?stage=${stageId}`),
			locals: { supabase: { rpc } }
		} as unknown as Parameters<typeof GET>[0]);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.stage).toBeDefined();
	});

	it('refuses a column name that is neither a stage nor an id', async () => {
		const event = readEvent([], 'stage=somewhere');
		const response = await GET(event);

		expect(response.status).toBe(422);
		expect(rpcOf(event)).not.toHaveBeenCalled();
	});
});

describe('the Task order', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.useFakeTimers({ toFake: ['Date'] });
		vi.setSystemTime(new Date('2026-09-10T12:00:00.000Z'));
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it('is the order an untouched board asks for, and it brings today along', async () => {
		const event = readEvent([]);
		expect((await GET(event)).status).toBe(200);
		expect(rpcOf(event)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({ sort_key: 'attention', board_today: '2026-09-10' })
		);
	});

	// Each phase holds one kind of card, so the last card says which phase the next page continues.
	it.each([
		['an overdue Task', '2026-09-01', 'new_request:attention:1:2026-09-01|opp-2'],
		['a Task due today', '2026-09-10', 'new_request:attention:1:2026-09-10|opp-2'],
		['no dated Task', null, 'new_request:attention:2:2026-08-10T00:00:00.000Z|opp-2'],
		['a Task due later', '2026-09-30', 'new_request:attention:3:2026-09-30|opp-2']
	])('marks the page after %s', async (_name, due, cursor) => {
		const rows = [
			boardRow({ id: 'opp-2', next_task_due_on: due }),
			boardRow({ id: 'opp-3', next_task_due_on: due })
		];
		const body = await (await GET(readEvent(rows, 'stage=new_request&limit=1'))).json();
		expect(body.next_cursor).toBe(cursor);
	});

	it('sends a day back as a day and a time back as a time', async () => {
		const byDay = readEvent(
			[],
			'stage=new_request&cursor=new_request:attention:3:2026-09-30|opp-2'
		);
		await GET(byDay);
		expect(rpcOf(byDay)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({
				cursor_phase: 3,
				cursor_date: '2026-09-30',
				cursor_timestamp: undefined
			})
		);

		const byTime = readEvent(
			[],
			'stage=new_request&cursor=new_request:attention:2:2026-08-10T00:00:00.000Z|opp-2'
		);
		await GET(byTime);
		expect(rpcOf(byTime)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({
				cursor_phase: 2,
				cursor_timestamp: '2026-08-10T00:00:00.000Z',
				cursor_date: undefined
			})
		);
	});

	it('refuses a marker whose value is not the kind its phase pages by', async () => {
		const event = readEvent([], 'stage=new_request&cursor=new_request:attention:1:soon|opp-2');
		expect((await GET(event)).status).toBe(422);
		expect(rpcOf(event)).not.toHaveBeenCalled();
	});
});

describe('the expected close order', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	it('puts cards with no date after the dated ones', async () => {
		const dated = await GET(
			readEvent(
				[boardRow({ id: 'opp-2', expected_close_on: '2026-10-05' }), boardRow({ id: 'opp-3' })],
				'stage=new_request&sort=close&direction=asc&limit=1'
			)
		);
		expect((await dated.json()).next_cursor).toBe('new_request:close:1:2026-10-05|opp-2');

		const undated = await GET(
			readEvent(
				[boardRow({ id: 'opp-2' }), boardRow({ id: 'opp-3' })],
				'stage=new_request&sort=close&direction=asc&limit=1'
			)
		);
		expect((await undated.json()).next_cursor).toBe('new_request:close:2:|opp-2');
	});

	it('pages a dated card by its day', async () => {
		const event = readEvent(
			[],
			'stage=new_request&sort=close&direction=asc&cursor=new_request:close:1:2026-10-05|opp-2'
		);
		await GET(event);
		expect(rpcOf(event)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({ sort_key: 'expected_close_on', cursor_date: '2026-10-05' })
		);
	});
});

describe('search and lead source', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHasPermission.mockReturnValue(true);
	});

	it('asks the database for the typed term as text and as phone digits', async () => {
		const event = readEvent([], 'stage=new_request&sort=stage&q=555-0102');
		expect((await GET(event)).status).toBe(200);
		expect(rpcOf(event)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({ search_like: '%555-0102%', search_digits: '5550102' })
		);
	});

	it('asks for one lead source by name', async () => {
		const event = readEvent([], 'stage=new_request&sort=stage&source=Referral');
		expect((await GET(event)).status).toBe(200);
		expect(rpcOf(event)).toHaveBeenCalledWith(
			'pipeline_board_page',
			expect.objectContaining({ lead_source_filter: 'Referral' })
		);
	});

	it('sends neither when the board is not searched or filtered', async () => {
		const event = readEvent([], 'stage=new_request&sort=stage');
		await GET(event);
		const sent = rpcOf(event).mock.calls[0][1];
		expect('search_like' in sent).toBe(false);
		expect('lead_source_filter' in sent).toBe(false);
	});

	it('refuses a search too short to mean anything', async () => {
		const event = readEvent([], 'stage=new_request&sort=stage&q=a');
		expect((await GET(event)).status).toBe(422);
		expect(rpcOf(event)).not.toHaveBeenCalled();
	});

	it('puts the client lead source on the card', async () => {
		const rows = [boardRow({ client_lead_source: 'Referral' }), boardRow({ id: 'opp-2' })];
		const body = await (await GET(readEvent(rows, 'stage=new_request&sort=stage'))).json();
		expect(body.opportunities[0].client.lead_source).toBe('Referral');
		expect(body.opportunities[1].client.lead_source).toBeNull();
	});
});
