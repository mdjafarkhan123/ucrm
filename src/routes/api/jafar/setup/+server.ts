import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { setupEditorCommandError } from '$lib/server/setup/owner-editor';

// Client onboarding A4 (plan §2.1): the setup clients see now, Jafar's draft of the next one, his service
// list and the publish history.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_setup_editor');
	if (error) {
		console.error('Could not load the setup editor.', error);
		return json({ error: 'The client setup could not be loaded.' }, { status: 500 });
	}
	return json({ editor: data }, { headers: { 'cache-control': 'no-store' } });
};

// Starts a draft as a copy of the published setup, or returns the draft already open.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_start_setup_draft', {
		actor_owner_email: session.email
	});
	if (error) return setupEditorCommandError(error, 'started');
	return json({ editor: data });
};
