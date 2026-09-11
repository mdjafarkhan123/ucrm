import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

// Settings → Team → Activity log: a company-wide, reverse-chronological "who changed what" feed
// (Contractor Settings Part 3, jobber-09 § 6 parity). Reads `organization_member_access_events` directly --
// no new RPC, no schema change -- because its own RLS already scopes rows to team.manage, the same gate this
// route re-checks for the UI-facing 403. Cursor-paginated on (created_at desc, id desc), matching the
// existing index plus a tiebreaker for rows created in the same instant.
//
// The events table intentionally stores no names or emails (member_access_event_shapes forbids free text),
// so every page resolves display names itself in three batched lookups -- never one query per row. A former
// team member's profile is unreachable through RLS once they are `removed` (profiles policy excludes removed
// targets on purpose), so the fallback reads organization_members.display_name_at_removal first, then a
// generic phrase, exactly as the approved plan requires.

const PAGE_SIZE = 25;

const querySchema = z.object({
	limit: z.coerce.number().int().min(1).max(50).default(PAGE_SIZE),
	cursor: z.string().max(200).optional()
});

type EventRow = {
	id: string;
	event_type: string;
	actor_kind: string;
	actor_user_id: string | null;
	subject_user_id: string | null;
	subject_invitation_id: string | null;
	summary: Record<string, unknown>;
	created_at: string;
};

function decodeCursor(raw: string | undefined) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const createdAt = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (!id || Number.isNaN(Date.parse(createdAt))) return null;
	return { createdAt, id };
}

function encodeCursor(row: EventRow | undefined) {
	return row ? `${row.created_at}|${row.id}` : null;
}

// A removed member's profile is gone from view (RLS), and their organization_members row can outlive that --
// or, one day, be gone entirely. Resolve in that order and never fail the row or leak a raw id.
function resolveMemberName(
	userId: string | null,
	fullNameById: Map<string, string | null>,
	membershipByUserId: Map<string, { display_name_at_removal: string | null }>
) {
	if (!userId) return 'Someone who is no longer on the team';
	const fullName = fullNameById.get(userId);
	if (fullName) return fullName;
	const membership = membershipByUserId.get(userId);
	if (membership?.display_name_at_removal) return membership.display_name_at_removal;
	if (membership) return 'A former team member';
	return 'Someone who is no longer on the team';
}

export const GET: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsed = querySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined
	});
	if (!parsed.success) {
		return json(
			{ error: 'That page link is invalid.' },
			{ status: 422, headers: PRIVATE_READ_HEADERS }
		);
	}
	const cursor = decodeCursor(parsed.data.cursor);
	if (parsed.data.cursor && !cursor) {
		return json(
			{ error: 'That page link is invalid.' },
			{ status: 422, headers: PRIVATE_READ_HEADERS }
		);
	}

	const { auth } = required.context;
	const supabase = event.locals.supabase;

	let query = supabase
		.from('organization_member_access_events')
		.select(
			'id, event_type, actor_kind, actor_user_id, subject_user_id, subject_invitation_id, summary, created_at'
		)
		.eq('organization_id', auth.organization.id)
		.order('created_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(parsed.data.limit + 1);

	if (cursor) {
		query = query.or(
			`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`
		);
	}

	const { data, error } = await query;
	if (error) {
		console.error('Could not load the Team activity log.', error);
		return json(
			{ error: 'The activity log could not be loaded.' },
			{ status: 500, headers: PRIVATE_READ_HEADERS }
		);
	}

	const rows = (data ?? []) as EventRow[];
	const page = rows.slice(0, parsed.data.limit);
	const hasMore = rows.length > parsed.data.limit;
	const nextCursor = hasMore ? encodeCursor(page.at(-1)) : null;

	// Batch every name and label this page needs -- at most four round trips total, never one per row.
	const memberIds = new Set<string>();
	const invitationIds = new Set<string>();
	const permissionKeys = new Set<string>();
	for (const row of page) {
		if (row.actor_user_id) memberIds.add(row.actor_user_id);
		if (row.subject_user_id) memberIds.add(row.subject_user_id);
		if (row.subject_invitation_id) invitationIds.add(row.subject_invitation_id);
		for (const key of ['added_permissions', 'removed_permissions']) {
			const value = row.summary[key];
			if (Array.isArray(value)) {
				for (const permissionKey of value) {
					if (typeof permissionKey === 'string') permissionKeys.add(permissionKey);
				}
			}
		}
	}

	const [profilesResult, membersResult, invitationsResult, permissionsResult] = await Promise.all([
		memberIds.size
			? supabase
					.from('profiles')
					.select('id, full_name')
					.in('id', [...memberIds])
			: Promise.resolve({ data: [] as { id: string; full_name: string | null }[], error: null }),
		memberIds.size
			? supabase
					.from('organization_members')
					.select('user_id, display_name_at_removal')
					.eq('organization_id', auth.organization.id)
					.in('user_id', [...memberIds])
			: Promise.resolve({
					data: [] as { user_id: string; display_name_at_removal: string | null }[],
					error: null
				}),
		invitationIds.size
			? supabase
					.from('organization_member_invitations')
					.select('id, invited_email')
					.in('id', [...invitationIds])
			: Promise.resolve({ data: [] as { id: string; invited_email: string }[], error: null }),
		permissionKeys.size
			? supabase
					.from('permissions')
					.select('key, description')
					.in('key', [...permissionKeys])
			: Promise.resolve({ data: [] as { key: string; description: string }[], error: null })
	]);
	for (const result of [profilesResult, membersResult, invitationsResult, permissionsResult]) {
		if (result.error)
			console.error('Team activity name lookup failed; falling back.', result.error);
	}

	const fullNameById = new Map((profilesResult.data ?? []).map((row) => [row.id, row.full_name]));
	const membershipByUserId = new Map(
		(membersResult.data ?? []).map((row) => [
			row.user_id,
			{ display_name_at_removal: row.display_name_at_removal }
		])
	);
	const emailByInvitationId = new Map(
		(invitationsResult.data ?? []).map((row) => [row.id, row.invited_email])
	);
	const permissionLabelByKey = new Map(
		(permissionsResult.data ?? []).map((row) => [row.key, row.description])
	);

	const entries = page.map((row) => {
		const summary = { ...row.summary };
		for (const key of ['added_permissions', 'removed_permissions']) {
			const value = summary[key];
			if (Array.isArray(value)) {
				summary[key] = value.map((permissionKey) =>
					typeof permissionKey === 'string'
						? (permissionLabelByKey.get(permissionKey) ?? permissionKey)
						: permissionKey
				);
			}
		}
		return {
			id: row.id,
			event_type: row.event_type,
			created_at: row.created_at,
			actor_name:
				row.actor_kind === 'system'
					? 'An automatic process'
					: resolveMemberName(row.actor_user_id, fullNameById, membershipByUserId),
			subject_name: row.subject_user_id
				? resolveMemberName(row.subject_user_id, fullNameById, membershipByUserId)
				: null,
			invited_email: row.subject_invitation_id
				? (emailByInvitationId.get(row.subject_invitation_id) ?? null)
				: null,
			summary
		};
	});

	return json({ entries, next_cursor: nextCursor }, { headers: PRIVATE_READ_HEADERS });
};
