import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { openSetupFile } from '$lib/server/setup/files';

// Client onboarding A5c: Jafar opens a file a client added to a setup answer. The organization is part of the
// lookup, so a file id under the wrong client reads as missing.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	const fileId = z.uuid().safeParse(event.params.fileId);
	if (!organizationId.success || !fileId.success)
		return json({ error: 'That file is not available.' }, { status: 404 });

	return openSetupFile(organizationId.data, fileId.data);
};
