import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';

vi.mock('$lib/server/access/contractor', () => ({ requireContractorTeamAdmin: vi.fn() }));

const organizationId = '00000000-0000-4000-8000-000000000021';
const managerId = '00000000-0000-4000-8000-000000000022';
const actorId = '00000000-0000-4000-8000-000000000023';
const subjectId = '00000000-0000-4000-8000-000000000024';
const removedWithSnapshotId = '00000000-0000-4000-8000-000000000025';
const removedWithoutTraceId = '00000000-0000-4000-8000-000000000026';
const invitationId = '00000000-0000-4000-8000-000000000027';

type TableResult = { data: unknown; error: unknown };

function makeBuilder(result: TableResult) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'order', 'limit', 'or', 'in']) {
		builder[method] = vi.fn(() => builder);
	}
	builder.then = (
		onResolve: (value: TableResult) => unknown,
		onReject?: (reason: unknown) => unknown
	) => Promise.resolve(result).then(onResolve, onReject);
	return builder;
}

function makeSupabase(resultsByTable: Record<string, TableResult>) {
	return {
		from: vi.fn((table: string) => makeBuilder(resultsByTable[table] ?? { data: [], error: null }))
	};
}

function event(query: string, supabase: ReturnType<typeof makeSupabase>) {
	return {
		url: new URL(`https://app.example.com/api/team/activity${query}`),
		locals: { supabase }
	} as unknown as Parameters<typeof GET>[0];
}

describe('Team activity log API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireContractorTeamAdmin).mockResolvedValue({
			context: {
				auth: {
					user: { id: managerId },
					organization: { id: organizationId, name: 'Ridgeway', role: 'admin' }
				},
				access: {
					features: { 'core.team': true },
					permissions: { 'team.manage': true },
					limits: {}
				}
			} as never
		});
	});

	it('returns the authorization response without querying anything', async () => {
		vi.mocked(requireContractorTeamAdmin).mockResolvedValueOnce({
			response: new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 })
		});
		const supabase = makeSupabase({});
		const response = await GET(event('', supabase));
		expect(response.status).toBe(403);
		expect(supabase.from).not.toHaveBeenCalled();
	});

	it('rejects a malformed cursor before querying', async () => {
		const supabase = makeSupabase({});
		const response = await GET(event('?cursor=not-a-cursor', supabase));
		expect(response.status).toBe(422);
		expect(supabase.from).not.toHaveBeenCalled();
	});

	it('resolves actor and subject names, falling back for a member who has left', async () => {
		const events = [
			{
				id: 'evt-1',
				event_type: 'member.role_changed',
				actor_kind: 'member',
				actor_user_id: actorId,
				subject_user_id: subjectId,
				subject_invitation_id: null,
				summary: { previous_role: 'field', new_role: 'office' },
				created_at: '2026-09-10T12:00:00+00:00'
			},
			{
				id: 'evt-2',
				event_type: 'member.removed',
				actor_kind: 'member',
				actor_user_id: actorId,
				subject_user_id: removedWithSnapshotId,
				subject_invitation_id: null,
				summary: {},
				created_at: '2026-09-09T12:00:00+00:00'
			},
			{
				id: 'evt-3',
				event_type: 'member.identity_revoked',
				actor_kind: 'system',
				actor_user_id: null,
				subject_user_id: removedWithoutTraceId,
				subject_invitation_id: null,
				summary: {},
				created_at: '2026-09-08T12:00:00+00:00'
			}
		];
		const supabase = makeSupabase({
			organization_member_access_events: { data: events, error: null },
			profiles: {
				data: [
					{ id: actorId, full_name: 'Alex Rivera' },
					{ id: subjectId, full_name: 'Sam Fern' }
				],
				error: null
			},
			organization_members: {
				data: [{ user_id: removedWithSnapshotId, display_name_at_removal: 'Jordan Pine' }],
				error: null
			},
			organization_member_invitations: { data: [], error: null },
			permissions: { data: [], error: null }
		});

		const response = await GET(event('', supabase));
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.entries).toHaveLength(3);
		expect(body.entries[0]).toMatchObject({ actor_name: 'Alex Rivera', subject_name: 'Sam Fern' });
		// Removed, but the permanent-removal snapshot still names them.
		expect(body.entries[1]).toMatchObject({
			actor_name: 'Alex Rivera',
			subject_name: 'Jordan Pine'
		});
		// A system event with no membership trace left at all falls back to the generic phrase.
		expect(body.entries[2]).toMatchObject({
			actor_name: 'An automatic process',
			subject_name: 'Someone who is no longer on the team'
		});
		expect(body.next_cursor).toBeNull();
	});

	it('resolves an invitation email and translates permission keys to labels', async () => {
		const events = [
			{
				id: 'evt-4',
				event_type: 'invitation.sent',
				actor_kind: 'member',
				actor_user_id: actorId,
				subject_user_id: null,
				subject_invitation_id: invitationId,
				summary: { role: 'office' },
				created_at: '2026-09-10T12:00:00+00:00'
			},
			{
				id: 'evt-5',
				event_type: 'member.permissions_changed',
				actor_kind: 'member',
				actor_user_id: actorId,
				subject_user_id: subjectId,
				subject_invitation_id: null,
				summary: { added_permissions: ['customers.view'], removed_permissions: [] },
				created_at: '2026-09-09T12:00:00+00:00'
			}
		];
		const supabase = makeSupabase({
			organization_member_access_events: { data: events, error: null },
			profiles: {
				data: [
					{ id: actorId, full_name: 'Alex Rivera' },
					{ id: subjectId, full_name: 'Sam Fern' }
				],
				error: null
			},
			organization_members: { data: [], error: null },
			organization_member_invitations: {
				data: [{ id: invitationId, invited_email: 'new.hire@example.com' }],
				error: null
			},
			permissions: { data: [{ key: 'customers.view', description: 'View customers' }], error: null }
		});

		const response = await GET(event('', supabase));
		const body = await response.json();
		expect(body.entries[0]).toMatchObject({ invited_email: 'new.hire@example.com' });
		expect(body.entries[1].summary.added_permissions).toEqual(['View customers']);
	});

	it('returns a next-page cursor only when a 26th row proves there is more', async () => {
		const events = Array.from({ length: 26 }, (_, index) => ({
			id: `evt-${index}`,
			event_type: 'member.removed',
			actor_kind: 'member',
			actor_user_id: actorId,
			subject_user_id: subjectId,
			subject_invitation_id: null,
			summary: {},
			created_at: '2026-09-10T12:00:00+00:00'
		}));
		const supabase = makeSupabase({
			organization_member_access_events: { data: events, error: null },
			profiles: { data: [], error: null },
			organization_members: { data: [], error: null },
			organization_member_invitations: { data: [], error: null },
			permissions: { data: [], error: null }
		});
		const response = await GET(event('', supabase));
		const body = await response.json();
		expect(body.entries).toHaveLength(25);
		expect(body.next_cursor).toBe('2026-09-10T12:00:00+00:00|evt-24');
	});

	it('returns a stable private error when the database fails', async () => {
		const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
		const supabase = makeSupabase({
			organization_member_access_events: {
				data: null,
				error: { code: 'XX000', message: 'private detail' }
			}
		});
		const response = await GET(event('', supabase));
		expect(response.status).toBe(500);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
		expect(await response.json()).toEqual({ error: 'The activity log could not be loaded.' });
		consoleError.mockRestore();
	});
});
