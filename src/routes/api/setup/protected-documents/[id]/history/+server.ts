import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { protectedDocumentOwnerOnly, requireSetupReader } from '$lib/server/setup/access';
import { readProtectedDocumentHistory } from '$lib/server/setup/protected-documents';

// Client onboarding B9a: who uploaded, opened and removed one protected setup document, and when. The business
// owner sees it, as Jafar does, so "has anyone opened my bill?" always has an answer (Jafar, 2026-10-04).
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;
	const refused = protectedDocumentOwnerOnly(check);
	if (refused) return refused;

	const id = z.uuid().safeParse(event.params.id);
	if (!id.success) return json({ error: 'That file is not available.' }, { status: 404 });

	try {
		const history = await readProtectedDocumentHistory(check.auth.organization.id, id.data);
		if (!history) return json({ error: 'That file is not available.' }, { status: 404 });
		return json({ history }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read a protected setup document history.', error);
		return databaseError();
	}
};
