import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readClientSetupView } from '$lib/server/setup/client-page';

// Client onboarding C2: one client's setup as Jafar's Setup tab shows it (plan §8) — every Send to Uplift,
// one read back by task (`?send=N`, the newest by default), and the client's setup reminders.

const querySchema = z.object({
	organizationId: z.uuid(),
	send: z.coerce.number().int().positive().max(100_000).optional()
});

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsed = querySchema.safeParse({
		organizationId: event.params.organizationId,
		send: event.url.searchParams.get('send') ?? undefined
	});
	if (!parsed.success) return notFound('That setup send does not exist.');

	try {
		const view = await readClientSetupView(
			getOwnerSupabaseClient(),
			parsed.data.organizationId,
			parsed.data.send ?? null
		);
		if (!view) return notFound('That setup send does not exist.');
		return json(view, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read a client setup.', error);
		return json({ error: 'The client’s setup could not be loaded.' }, { status: 500 });
	}
};
