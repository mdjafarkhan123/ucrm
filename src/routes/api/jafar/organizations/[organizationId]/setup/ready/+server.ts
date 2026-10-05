import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readClientSetupView } from '$lib/server/setup/client-page';
import { setupReadySchema, setupReadyWithdrawSchema } from '$lib/server/validation/setup.schema';

// Client onboarding C4 (plan §4–5): Jafar records Ready for Uplift on a client's newest send, which starts the
// 7–10 business-day range the client sees, or takes a mistaken one back with a reason. Ready is refused with 409
// while any blocker remains — worked out here from the same reads the Setup tab shows, and the database
// re-checks what it can — or when the client has sent again since the page was opened.

async function readBody<T>(
	request: Request,
	schema: z.ZodType<T>
): Promise<{ data: T } | { response: Response }> {
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return { response: validationError({ form: 'Request body must be valid JSON.' }) };
	}
	const parsed = schema.safeParse(body);
	if (parsed.success) return { data: parsed.data };
	const fieldErrors: Record<string, string> = {};
	for (const issue of parsed.error.issues)
		fieldErrors[String(issue.path[0] ?? 'form')] ??= issue.message;
	return { response: validationError(fieldErrors) };
}

const conflict = (error: string, extra: Record<string, unknown> = {}) =>
	json({ error, ...extra }, { status: 409, headers: NO_STORE_HEADERS });

const STALE =
	'The client has sent their setup again since you opened it. Look at the newest send first.';

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');
	const body = await readBody(event.request, setupReadySchema);
	if ('response' in body) return body.response;

	const client = getOwnerSupabaseClient();
	try {
		const view = await readClientSetupView(client, organizationId.data, null);
		if (!view) return notFound('That client does not exist.');
		if (view.ready)
			return json({ status: 'unchanged', ...view.ready }, { headers: NO_STORE_HEADERS });
		if (view.sends[0] && view.sends[0].number !== body.data.send)
			return conflict(STALE, { latest_number: view.sends[0].number });
		if (view.ready_blockers?.length)
			return conflict('Ready for Uplift waits until every blocker is cleared.', {
				blockers: view.ready_blockers
			});

		const { data, error } = await client.rpc('owner_mark_setup_ready', {
			target_organization_id: organizationId.data,
			seen_number: body.data.send,
			actor_email: session.email
		});
		if (error) {
			// The database's own checks, met between the read above and now, in plain words.
			if (error.code === '23514' || error.code === 'P0002') return conflict(error.message);
			throw error;
		}
		const result = data as { status: string; latest_number?: number };
		if (result.status === 'stale') return conflict(STALE, { latest_number: result.latest_number });
		return json(result, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not record Ready for Uplift.', error);
		return databaseError();
	}
};

export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');
	const body = await readBody(event.request, setupReadyWithdrawSchema);
	if ('response' in body) return body.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_withdraw_setup_ready', {
		target_organization_id: organizationId.data,
		withdraw_reason: body.data.reason,
		actor_email: session.email
	});
	if (error) {
		console.error('Could not take back Ready for Uplift.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};
