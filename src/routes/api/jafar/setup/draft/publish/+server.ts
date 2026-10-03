import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	invalidSetupDraft,
	readJsonBody,
	setupEditorCommandError,
	staleSetupDraft
} from '$lib/server/setup/owner-editor';
import { setupDraftRevisionSchema } from '$lib/server/validation/setup-editor.schema';

// Publishes the saved draft exactly as saved. Clients still filling in setup see it on their next page
// load; clients who already sent setup to Uplift are not reopened (plan §2.1).
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const read = await readJsonBody(event);
	if (read.response) return read.response;
	const parsed = setupDraftRevisionSchema.safeParse(read.body);
	if (!parsed.success) return invalidSetupDraft(parsed.error);

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_publish_setup_draft', {
		target_version_id: parsed.data.version_id,
		loaded_revision: parsed.data.revision,
		actor_owner_email: session.email
	});
	if (error) return setupEditorCommandError(error, 'published');
	const result = data as { published: boolean; editor: unknown };
	if (!result.published) return staleSetupDraft(result.editor);
	return json({ editor: result.editor });
};
