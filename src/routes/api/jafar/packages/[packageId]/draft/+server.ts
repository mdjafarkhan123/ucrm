import { json, type RequestEvent } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { ownerPackageCommandError } from '$lib/server/packages/owner-package-errors';
import {
	deletePackageDraftSchema,
	packageFieldErrors,
	packageIdSchema,
	savePackageDraftSchema
} from '$lib/server/validation/package-builder.schema';

// Package builder P6: open, save, and delete a package's draft. Save and delete name the revision the
// editor loaded; when another tab saved first, nothing is written and the newer draft comes back with
// 409 so the builder can show what changed (ADR 0003 decision 3).

async function readBody(event: RequestEvent) {
	try {
		return { body: (await event.request.json()) as unknown };
	} catch {
		return { response: json({ error: 'Request body must be valid JSON.' }, { status: 400 }) };
	}
}

function failed(error: { code?: string; message: string }, action: string) {
	const refused = ownerPackageCommandError(error);
	if (refused) return refused;
	console.error(`Could not ${action} the package draft.`, error);
	return json(
		{ error: `The draft could not be ${action === 'open' ? 'opened' : action + 'd'}.` },
		{ status: 500 }
	);
}

function staleResponse(draft: unknown) {
	return json(
		{
			error: 'This draft was saved in another tab after you opened it.',
			reason: 'stale',
			draft
		},
		{ status: 409 }
	);
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = packageIdSchema.safeParse(event.params.packageId);
	if (!parsedId.success)
		return json({ error: 'The package identifier is invalid.' }, { status: 422 });

	const { data, error } = await getOwnerSupabaseClient().rpc('open_package_draft', {
		target_package_id: parsedId.data,
		actor_owner_email: session.email
	});
	if (error) return failed(error, 'open');
	return json({ result: data });
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = packageIdSchema.safeParse(event.params.packageId);
	if (!parsedId.success)
		return json({ error: 'The package identifier is invalid.' }, { status: 422 });

	const read = await readBody(event);
	if (read.response) return read.response;
	const parsed = savePackageDraftSchema.safeParse(read.body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the package details.',
				field_errors: packageFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('save_package_draft', {
		target_package_id: parsedId.data,
		draft_edition_id: parsed.data.edition_id,
		loaded_revision: parsed.data.revision,
		terms: parsed.data.terms,
		actor_owner_email: session.email
	});
	if (error) return failed(error, 'save');
	const result = data as { saved: boolean; draft: unknown };
	if (!result.saved) return staleResponse(result.draft);
	return json({ draft: result.draft });
};

export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = packageIdSchema.safeParse(event.params.packageId);
	if (!parsedId.success)
		return json({ error: 'The package identifier is invalid.' }, { status: 422 });

	const read = await readBody(event);
	if (read.response) return read.response;
	const parsed = deletePackageDraftSchema.safeParse(read.body);
	if (!parsed.success) return json({ error: 'The draft details are invalid.' }, { status: 422 });

	const { data, error } = await getOwnerSupabaseClient().rpc('delete_package_draft', {
		target_package_id: parsedId.data,
		draft_edition_id: parsed.data.edition_id,
		loaded_revision: parsed.data.revision,
		actor_owner_email: session.email
	});
	if (error) return failed(error, 'delete');
	const result = data as { deleted: boolean; package_removed?: boolean; draft?: unknown };
	if (!result.deleted) return staleResponse(result.draft);
	return json({ package_removed: result.package_removed ?? false });
};
