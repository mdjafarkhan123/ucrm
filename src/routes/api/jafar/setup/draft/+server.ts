import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	invalidSetupDraft,
	readJsonBody,
	setupEditorCommandError,
	staleSetupDraft
} from '$lib/server/setup/owner-editor';
import {
	saveSetupDraftSchema,
	setupDraftRevisionSchema
} from '$lib/server/validation/setup-editor.schema';

type CommandResult = { saved?: boolean; discarded?: boolean; reason?: string; editor: unknown };

// Saves the draft's whole stage list, in order, against the revision this tab loaded.
export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const read = await readJsonBody(event);
	if (read.response) return read.response;
	const parsed = saveSetupDraftSchema.safeParse(read.body);
	if (!parsed.success) return invalidSetupDraft(parsed.error);

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_save_setup_draft_stages', {
		target_version_id: parsed.data.version_id,
		loaded_revision: parsed.data.revision,
		new_stages: parsed.data.stages as Json,
		actor_owner_email: session.email
	});
	if (error) return setupEditorCommandError(error, 'saved');
	const result = data as CommandResult;
	if (!result.saved) return staleSetupDraft(result.editor);
	return json({ editor: result.editor });
};

// Throws the draft away. Clients keep the published setup.
export const DELETE: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const read = await readJsonBody(event);
	if (read.response) return read.response;
	const parsed = setupDraftRevisionSchema.safeParse(read.body);
	if (!parsed.success) return invalidSetupDraft(parsed.error);

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_discard_setup_draft', {
		target_version_id: parsed.data.version_id,
		loaded_revision: parsed.data.revision
	});
	if (error) return setupEditorCommandError(error, 'discarded');
	const result = data as CommandResult;
	if (!result.discarded) return staleSetupDraft(result.editor);
	return json({ editor: result.editor });
};
