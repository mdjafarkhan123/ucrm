import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { readProtectedDocumentHistory } from '$lib/server/setup/protected-documents';

// Client onboarding B9a: who uploaded, opened and removed one client's protected setup document, and when —
// the same list the client's owner sees.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	const documentId = z.uuid().safeParse(event.params.documentId);
	if (!organizationId.success || !documentId.success)
		return json({ error: 'That file is not available.' }, { status: 404 });

	try {
		const history = await readProtectedDocumentHistory(organizationId.data, documentId.data);
		if (!history) return json({ error: 'That file is not available.' }, { status: 404 });
		return json({ history }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read a protected setup document history.', error);
		return databaseError();
	}
};
