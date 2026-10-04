import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireSetupReader } from '$lib/server/setup/access';
import { openSetupFile } from '$lib/server/setup/files';

// Client onboarding A5c: opens one file of the organization's own setup answers.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const id = z.uuid().safeParse(event.params.id);
	if (!id.success) return json({ error: 'That file is not available.' }, { status: 404 });

	return openSetupFile(check.auth.organization.id, id.data);
};
