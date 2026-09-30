import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { ownerPackageCommandError } from '$lib/server/packages/owner-package-errors';
import {
	packageIdSchema,
	publishPackageDraftSchema
} from '$lib/server/validation/package-builder.schema';

// Package builder P7: publish the exact draft Jafar reviewed as the package's next edition. The command
// refuses a draft saved again since the review (409 with the newer draft) and a draft that cannot be sold
// yet (422 with each problem). Customers already on the package keep their edition (ADR 0003 decision 2).

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = packageIdSchema.safeParse(event.params.packageId);
	if (!parsedId.success)
		return json({ error: 'The package identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = publishPackageDraftSchema.safeParse(body);
	if (!parsed.success) return json({ error: 'The draft details are invalid.' }, { status: 422 });

	const { data, error } = await getOwnerSupabaseClient().rpc('publish_package_draft', {
		target_package_id: parsedId.data,
		draft_edition_id: parsed.data.edition_id,
		reviewed_revision: parsed.data.revision,
		actor_owner_email: session.email
	});
	if (error) {
		const refused = ownerPackageCommandError(error);
		if (refused) return refused;
		console.error('Could not publish the package draft.', error);
		return json({ error: 'The draft could not be published.' }, { status: 500 });
	}

	const result = data as {
		published: boolean;
		reason?: 'stale' | 'not_ready';
		edition_number?: number;
		draft?: unknown;
		problems?: unknown;
	};
	if (result.reason === 'stale') {
		return json(
			{
				error: 'This draft was saved again after you reviewed it. Review the latest version.',
				reason: 'stale',
				draft: result.draft
			},
			{ status: 409 }
		);
	}
	if (result.reason === 'not_ready') {
		return json(
			{
				error: 'This draft cannot be published yet.',
				reason: 'not_ready',
				problems: result.problems
			},
			{ status: 422 }
		);
	}
	return json({ edition_number: result.edition_number });
};
