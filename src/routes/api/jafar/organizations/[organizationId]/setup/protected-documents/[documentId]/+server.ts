import { json, type RequestEvent } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	deleteProtectedDocument,
	openProtectedDocument,
	scheduleProtectedDocumentDeletion
} from '$lib/server/setup/protected-documents';

// Client onboarding B9a: Jafar's hands on one client's protected setup document. The organization is part of
// every lookup, so a document under the wrong client reads as missing. Each action is recorded in the
// document's history under "Uplift", which the client's owner also sees.

function target(event: RequestEvent) {
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	const documentId = z.uuid().safeParse(event.params.documentId);
	return organizationId.success && documentId.success
		? { organizationId: organizationId.data, documentId: documentId.data }
		: null;
}

const notFound = () => json({ error: 'That file is not available.' }, { status: 404 });

/** Opens the document. */
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const found = target(event);
	if (!found) return notFound();
	return openProtectedDocument(found.organizationId, found.documentId, {
		kind: 'uplift',
		ownerEmail: session.email
	});
};

/** Deletes the document now. */
export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const found = target(event);
	if (!found) return notFound();
	return deleteProtectedDocument(found.organizationId, found.documentId, {
		kind: 'uplift',
		ownerEmail: session.email
	});
};

const scheduleSchema = z.object({ provider_step_finished: z.literal(true) }).strict();

/** The provider step this document served is finished: it is deleted 90 days from now. */
export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const found = target(event);
	if (!found) return notFound();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	if (!scheduleSchema.safeParse(body).success)
		return validationError({ form: 'Say that the provider step is finished.' });

	return scheduleProtectedDocumentDeletion(found.organizationId, found.documentId, session.email);
};
