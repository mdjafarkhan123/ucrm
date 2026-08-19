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
		...overrides
	};
}

function readEvent(rows: unknown[]) {
	const rpc = vi.fn().mockResolvedValue({ data: rows, error: null });
	return {
		url: new URL('http://localhost/api/pipeline/opportunities?stage=new_request'),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
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
