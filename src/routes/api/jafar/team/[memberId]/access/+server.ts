import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	TeamAccessError,
	getTeamMemberAccess,
	saveTeamMemberAccess
} from '$lib/server/jafar/team-member-access';
import { teamAccessSaveSchema } from '$lib/server/validation/team-member.schema';

// One teammate's role, areas, sensitive actions, and history (D2, ADR 0008). Only the owner manages access;
// the front-door gate already refuses a teammate here, and the role check repeats it.

const memberIdSchema = z.string().uuid();

function accessErrorResponse(error: TeamAccessError) {
	const status = error.code === 'not_found' ? 404 : error.code === 'stale' ? 409 : 422;
	return json({ error: error.message, code: error.code }, { status });
}

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	const memberId = memberIdSchema.safeParse(event.params.memberId);
	if (!memberId.success)
		return json({ error: 'That teammate could not be found.' }, { status: 404 });

	try {
		return json(await getTeamMemberAccess(getOwnerSupabaseClient(), memberId.data));
	} catch (error) {
		if (error instanceof TeamAccessError) return accessErrorResponse(error);
		console.error('Could not load a teammate’s access.', error);
		return json({ error: 'This teammate’s access could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	const memberId = memberIdSchema.safeParse(event.params.memberId);
	if (!memberId.success)
		return json({ error: 'That teammate could not be found.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = teamAccessSaveSchema.safeParse(body);
	if (!parsed.success) {
		return json({ error: 'That access could not be read. Reload and try again.' }, { status: 422 });
	}

	try {
		const view = await saveTeamMemberAccess(getOwnerSupabaseClient(), {
			memberId: memberId.data,
			role: parsed.data.role,
			access: { areas: parsed.data.areas, actions: parsed.data.actions },
			expectedRevision: parsed.data.expected_access_revision,
			actorEmail: session.email
		});
		return json(view);
	} catch (error) {
		if (error instanceof TeamAccessError) return accessErrorResponse(error);
		console.error('Could not save a teammate’s access.', error);
		return json({ error: 'The access could not be saved. Try again.' }, { status: 500 });
	}
};
