import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	packageChangePreviewSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

// Package builder P8b: what moving the organization to another published edition would do — both
// editions side by side, features gained and lost, limit changes, what is over the new limits, and the
// payment effect — before Jafar confirms it through the Billing command. Reading it changes nothing.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	const parsed = packageChangePreviewSchema.safeParse({
		edition_id: event.url.searchParams.get('edition_id'),
		billing_interval: event.url.searchParams.get('billing_interval'),
		timing: event.url.searchParams.get('timing')
	});
	if (!parsed.success)
		return json(
			{
				error: 'Choose a package, billing, and start.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_package_change_preview', {
		target_organization_id: parsedId.data,
		target_edition_id: parsed.data.edition_id,
		billing_interval: parsed.data.billing_interval,
		timing: parsed.data.timing
	});
	if (error) {
		if (['23503', '23514'].includes(error.code))
			return json({ error: error.message }, { status: 409 });
		console.error('Could not preview the package change.', error);
		return json({ error: 'The change could not be previewed.' }, { status: 500 });
	}
	return json({ preview: data }, { headers: { 'cache-control': 'no-store' } });
};
