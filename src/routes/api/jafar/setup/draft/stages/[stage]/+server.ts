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
import { saveSetupStageItemsSchema } from '$lib/server/validation/setup-editor.schema';

type CommandResult = { saved: boolean; reason?: string; editor: unknown };

// Client onboarding A5: saves one stage's headings and questions, in order, against the revision this tab
// loaded. Built-in questions keep their answer type and cannot be removed; answered questions keep theirs.
export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const stageKey = event.params.stage;
	if (!/^[a-z][a-z0-9_]*$/.test(stageKey) || stageKey.length > 40)
		return json({ error: 'This stage does not exist.' }, { status: 404 });
	const read = await readJsonBody(event);
	if (read.response) return read.response;
	const parsed = saveSetupStageItemsSchema.safeParse(read.body);
	if (!parsed.success) return invalidSetupDraft(parsed.error, 'items');

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_save_setup_draft_stage_items', {
		target_version_id: parsed.data.version_id,
		loaded_revision: parsed.data.revision,
		target_stage_key: stageKey,
		new_items: parsed.data.items as Json,
		actor_owner_email: session.email
	});
	if (error) return setupEditorCommandError(error, 'saved');
	const result = data as CommandResult;
	if (!result.saved) return staleSetupDraft(result.editor);
	return json({ editor: result.editor });
};
