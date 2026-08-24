import { json } from '@sveltejs/kit';
import type { PostgrestError } from '@supabase/supabase-js';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The team commands are SECURITY DEFINER and `authenticated` holds no grant on them, so the signed-in
// user's client cannot call them. They run as the service role, whose only reach into a team member's
// standing is through these functions -- the authority rules live inside them, not out here.
// Made once per process, the same way the quote access resolver client is.
let commandClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getTeamCommandClient() {
	commandClient ??= getOwnerSupabaseClient();
	return commandClient;
}

// The commands raise with a message written for the person on the screen, so the message is passed
// through for the codes we recognise instead of being replaced by something vaguer. Anything else is a
// fault on our side and says nothing about the member.
//
//   P0409 application conflict -- somebody else saved while this editor was looking at an older copy.
//         It is deliberately not 40001: PostgREST retries serialization failures, but an outdated revision
//         cannot become current through retrying.
//   23514 check_violation      -- an authority or state rule refused the change.
//   P0002 no_data_found        -- the member is not in this organization.
export function teamCommandErrorResponse(error: PostgrestError, fallbackMessage: string) {
	if (error.code === 'P0409') {
		return json({ error: error.message, stale: true }, { status: 409 });
	}
	if (error.code === '23514') {
		return json({ error: error.message }, { status: 409 });
	}
	if (error.code === 'P0002') {
		return json({ error: error.message }, { status: 404 });
	}

	console.error('A team member command failed.', error);
	return json({ error: fallbackMessage }, { status: 500 });
}

export type TeamMemberSummary = {
	user_id: string;
	role: string;
	status: string;
	access_revision: number;
	created_at: string;
};

export function teamMemberSummary(member: {
	user_id: string;
	role: string;
	status: string;
	access_revision: number;
	created_at: string;
}): TeamMemberSummary {
	return {
		user_id: member.user_id,
		role: member.role,
		status: member.status,
		access_revision: member.access_revision,
		created_at: member.created_at
	};
}

export type TeamMemberProfileSummary = {
	user_id: string;
	profile_revision: number;
};

export function teamMemberProfileSummary(member: {
	user_id: string;
	profile_revision: number;
}): TeamMemberProfileSummary {
	return {
		user_id: member.user_id,
		profile_revision: member.profile_revision
	};
}
