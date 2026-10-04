import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	protectedDocumentOwnerOnly,
	requireSetupEditor,
	requireSetupReader,
	setupWriteLimited
} from '$lib/server/setup/access';
import {
	deleteProtectedDocument,
	memberActorLabel,
	openProtectedDocument
} from '$lib/server/setup/protected-documents';

const notFound = () => json({ error: 'That file is not available.' }, { status: 404 });

// Client onboarding B9a: opens one protected setup document. The business owner only — an administrator who
// uploaded it sees that it arrived, and cannot open it (Jafar, 2026-10-04). Every opening is recorded.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;
	const refused = protectedDocumentOwnerOnly(check);
	if (refused) return refused;

	const id = z.uuid().safeParse(event.params.id);
	if (!id.success) return notFound();

	return openProtectedDocument(check.auth.organization.id, id.data, {
		kind: 'member',
		userId: check.auth.user.id,
		label: await memberActorLabel(check.auth.user.id, check.auth.user.email)
	});
};

// Removes a protected document for good: whoever can fill in setup can take back a file they added by mistake.
// The removal is recorded, and the history stays.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;
	const limited = await setupWriteLimited(event, check.auth.organization.id);
	if (limited) return limited;

	const id = z.uuid().safeParse(event.params.id);
	if (!id.success) return notFound();

	return deleteProtectedDocument(check.auth.organization.id, id.data, {
		kind: 'member',
		userId: check.auth.user.id,
		label: await memberActorLabel(check.auth.user.id, check.auth.user.email)
	});
};
