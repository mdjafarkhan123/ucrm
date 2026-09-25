import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { reviewSettingsSchema } from '$lib/server/validation/reviews.schema';
import {
	ReviewSettingsConflictError,
	ReviewSettingsForbiddenError,
	ReviewSettingsRuleError,
	loadReviewSettings,
	saveReviewSettings
} from '$lib/server/reviews/settings';

// Google review setup: the Google link, review page routing, private-feedback form and message styles.
// reviews.manage already folds in the plan's Reputation feature; the database re-checks the permission.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.manage');
	if ('response' in check) return check.response;

	try {
		return json(await loadReviewSettings(check.auth.organization.id), {
			headers: PRIVATE_READ_HEADERS
		});
	} catch (error) {
		console.error('Could not load review settings.', error);
		return json({ error: 'Review settings could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.manage');
	if ('response' in check) return check.response;

	const body = await event.request.json().catch(() => null);
	const parsed = reviewSettingsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		await saveReviewSettings(check.auth.organization.id, check.auth.user.id, parsed.data);
	} catch (error) {
		if (error instanceof ReviewSettingsConflictError) {
			return json(
				{
					error:
						'Someone else saved review settings since you opened them. Reload to see their changes.'
				},
				{ status: 409, headers: NO_STORE_HEADERS }
			);
		}
		if (error instanceof ReviewSettingsForbiddenError) {
			return json(
				{ error: 'You do not have access to do that.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		if (error instanceof ReviewSettingsRuleError) {
			return json({ error: error.message }, { status: 422, headers: NO_STORE_HEADERS });
		}
		console.error('Could not save review settings.', error);
		return json(
			{ error: 'Review settings could not be saved.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}

	try {
		return json(await loadReviewSettings(check.auth.organization.id), {
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not reload review settings.', error);
		return json({ error: 'Saved, but the settings could not be reloaded.' }, { status: 500 });
	}
};
