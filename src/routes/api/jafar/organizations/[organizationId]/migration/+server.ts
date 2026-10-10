import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	migrationCommandSchema,
	migrationCompareSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { loadMigrationTab, recordPath, takeSnapshot } from '$lib/server/experience/migration';

// Multi-industry foundation B10: a business's inventory snapshots, the access path it follows, and a
// comparison of any two snapshots. Anyone who may open Organizations can read it; taking a snapshot and
// switching the path are the Platform Owner's (`OWNER_ONLY_CHANGES`). Snapshots hold counts and
// fingerprints only; no customer link secret or record content is stored or shown.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	const from = event.url.searchParams.get('from');
	const to = event.url.searchParams.get('to');
	let compare: { from: string; to: string } | undefined;
	if (from || to) {
		const parsed = migrationCompareSchema.safeParse({ from, to });
		if (!parsed.success)
			return json({ error: 'Choose two snapshots to compare.' }, { status: 422 });
		compare = parsed.data;
	}

	try {
		return json(await loadMigrationTab(getOwnerSupabaseClient(), parsedId.data, compare), {
			headers: { 'cache-control': 'no-store' }
		});
	} catch (error) {
		console.error('Could not load the migration view.', error);
		return json({ error: 'The migration view could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = migrationCommandSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{ error: 'Please review the request.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);

	try {
		const client = getOwnerSupabaseClient();
		const command = parsed.data;
		const result =
			command.action === 'snapshot'
				? await takeSnapshot(client, parsedId.data, command.label, session.email)
				: await recordPath(client, parsedId.data, command, session.email);
		return json(
			{ command: result, ...(await loadMigrationTab(client, parsedId.data)) },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		const code = (error as { code?: string }).code;
		if (code === '23503') return json({ error: 'Organization was not found.' }, { status: 404 });
		if (code === '23505' || code === '23514')
			return json({ error: (error as Error).message }, { status: 409 });
		console.error('Could not record the migration command.', error);
		return json({ error: 'The migration request could not be completed.' }, { status: 500 });
	}
};
