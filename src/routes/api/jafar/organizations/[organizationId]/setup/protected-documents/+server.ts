import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readOrganizationSetupVersion } from '$lib/server/setup/catalogue';
import { listProtectedDocuments } from '$lib/server/setup/protected-documents';
import { catalogueFacts } from '$lib/setup/catalogue';

// Client onboarding B9b: every protected document one client has uploaded in setup, for Jafar's client page —
// where he opens one, marks its provider step finished, deletes it, or reads its history.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return json({ error: 'Organization not found.' }, { status: 404 });

	try {
		const catalogue = await readOrganizationSetupVersion(
			getOwnerSupabaseClient(),
			organizationId.data
		);
		const labels = new Map(
			[...catalogueFacts(catalogue ?? { versionId: '', sections: [] })].map(([key, fact]) => [
				key,
				fact.label
			])
		);
		const documents = await listProtectedDocuments(organizationId.data, labels);
		return json({ documents }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not list protected setup documents.', error);
		return databaseError();
	}
};
