import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

const querySchema = z.object({
	status: z.enum(['pending', 'active', 'deactivated']).optional(),
	search: z.string().trim().max(100).optional(),
	limit: z.coerce.number().int().min(1).max(50).default(25),
	cursor: z.string().max(500).optional()
});
const cursorSchema = z.object({
	status_order: z.number().int().min(1).max(3),
	created_at: z.iso.datetime({ offset: true }),
	user_id: z.uuid()
});
type TeamCursor = z.infer<typeof cursorSchema>;
type DirectoryEnvelope = { members: unknown[]; next_cursor: TeamCursor | null; seats_used: number };

function validationResponse(fieldErrors: Record<string, string>) {
	return json(
		{ error: 'Please review the Team filters.', field_errors: fieldErrors },
		{ status: 422, headers: PRIVATE_READ_HEADERS }
	);
}
function decodeCursor(value: string | undefined): TeamCursor | null | 'invalid' {
	if (!value) return null;
	try {
		const result = cursorSchema.safeParse(
			JSON.parse(Buffer.from(value, 'base64url').toString('utf8'))
		);
		return result.success ? result.data : 'invalid';
	} catch {
		return 'invalid';
	}
}
function encodeCursor(cursor: TeamCursor | null) {
	return cursor ? Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url') : null;
}
function readEnvelope(value: unknown): DirectoryEnvelope | null {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
	const envelope = value as Partial<DirectoryEnvelope>;
	if (!Array.isArray(envelope.members) || !Number.isInteger(envelope.seats_used)) return null;
	const cursor =
		envelope.next_cursor === null ? null : cursorSchema.safeParse(envelope.next_cursor);
	if (cursor !== null && !cursor.success) return null;
	return {
		members: envelope.members,
		next_cursor: cursor === null ? null : cursor.data,
		seats_used: envelope.seats_used as number
	};
}

export const GET: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const raw = Object.fromEntries(
		['status', 'search', 'limit', 'cursor']
			.map((key) => [key, event.url.searchParams.get(key)])
			.filter((entry): entry is [string, string] => entry[1] !== null)
	);
	const parsed = querySchema.safeParse(raw);
	if (!parsed.success) {
		return validationResponse(
			Object.fromEntries(parsed.error.issues.map((issue) => [String(issue.path[0]), issue.message]))
		);
	}
	const cursor = decodeCursor(parsed.data.cursor);
	if (cursor === 'invalid') return validationResponse({ cursor: 'That page link is invalid.' });

	const { auth, access } = required.context;
	const { data, error } = await event.locals.supabase.rpc('list_team_directory', {
		target_organization_id: auth.organization.id,
		requested_status: parsed.data.status ?? null,
		search_term: parsed.data.search || null,
		page_limit: parsed.data.limit,
		cursor_status_order: cursor?.status_order ?? null,
		cursor_created_at: cursor?.created_at ?? null,
		cursor_user_id: cursor?.user_id ?? null
	});
	if (error) {
		console.error('Could not load the Team directory.', error);
		return json(
			{ error: 'Team members could not be loaded.' },
			{ status: 500, headers: PRIVATE_READ_HEADERS }
		);
	}
	const envelope = readEnvelope(data);
	if (!envelope) {
		console.error('The Team directory returned an invalid response shape.');
		return json(
			{ error: 'Team members could not be loaded.' },
			{ status: 500, headers: PRIVATE_READ_HEADERS }
		);
	}

	return json(
		{
			members: envelope.members,
			next_cursor: encodeCursor(envelope.next_cursor),
			seats: {
				used: envelope.seats_used,
				limit: access.limits.employee_seats.value,
				is_unlimited: access.limits.employee_seats.is_unlimited
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
