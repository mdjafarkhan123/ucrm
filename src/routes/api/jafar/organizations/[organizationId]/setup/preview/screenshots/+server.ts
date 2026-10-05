import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	previewScreenshotResponse,
	previewUploadTicketResponse
} from '$lib/server/setup/preview-screenshots';
import { setupPreviewScreenshotPresignSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E3: a screenshot on a client's preview, for Jafar — shown (GET `?key=`, `&size=thumb`), or
// somewhere to upload one for a card (POST), stored under the client's own preview folder.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');
	return previewScreenshotResponse(organizationId.data, event.url);
};

export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = setupPreviewScreenshotPresignSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{ error: parsed.error.issues[0]?.message ?? 'That file cannot be added.' },
			{ status: 422 }
		);
	return previewUploadTicketResponse(organizationId.data, parsed.data);
};
