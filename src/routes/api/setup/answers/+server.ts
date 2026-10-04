import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { readOrganizationSetupCatalogue } from '$lib/server/setup/catalogue';
import { requireSetupEditor, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';
import { unusableSetupFile } from '$lib/server/setup/files';
import { setupAnswersSchema } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { catalogueFacts } from '$lib/setup/catalogue';

// Autosave. Each answer is a draft the administrator can keep changing; nothing saved here is treated as
// a final, attested answer (ADR 0005).
export const PATCH: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	// Checked against the version published now, as this client sees it, so a question Jafar just removed or
	// one from a stage outside their package is refused.
	const catalogue = await readOrganizationSetupCatalogue(event.locals.supabase, organizationId);
	if (!catalogue) return databaseError();

	const facts = catalogueFacts(catalogue);
	const parsed = setupAnswersSchema(facts).safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// A photo or file answer may only hold this organization's own setup uploads that are still usable.
	for (const answer of parsed.data.answers) {
		if (facts.get(answer.fact_key)?.kind !== 'file' || !Array.isArray(answer.value)) continue;
		let unusable: string | null;
		try {
			unusable = await unusableSetupFile(organizationId, answer.value as string[]);
		} catch (error) {
			console.error('Could not check setup answer files.', error);
			return databaseError();
		}
		if (unusable)
			return validationError({
				[answer.fact_key]: 'One of these files could not be kept. Remove it and try again.'
			});
	}

	const { data, error } = await event.locals.supabase.rpc('save_organization_setup_answers', {
		target_organization_id: organizationId,
		new_answers: parsed.data.answers
	});
	if (error) return setupWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
