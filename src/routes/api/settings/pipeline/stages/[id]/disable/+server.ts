import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { isStale, settingsWriteError, staleSettingsResponse } from '$lib/server/settings/errors';
import {
	BUILT_IN_DESTINATION,
	disablePipelineStageSchema
} from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const DISABLE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Switching a custom stage off. Its own action rather than part of the Settings Save: it moves cards, so
// it happens when the person confirms it and never by a stage quietly going missing from a saved list.
//
// `disable_pipeline_custom_stage` owns the whole of it — the revision check, moving every card, keeping
// the row as the stage's historical name, and the audit row — in one transaction. A stage holding cards
// is never switched off without a destination: the command answers `needs_destination` instead, which
// reaches the page as a 409 it can turn into the question.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	if (!z.string().uuid().safeParse(event.params.id).success)
		return notFound('That stage could not be found.');

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-pipeline-save:${organizationId}`,
			...DISABLE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = disablePipelineStageSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const destination = parsed.data.destination;
	const toBuiltIn = destination === BUILT_IN_DESTINATION;

	const { data, error } = await event.locals.supabase.rpc('disable_pipeline_custom_stage', {
		target_organization_id: organizationId,
		target_stage_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		move_cards_to_stage_id: toBuiltIn || destination === null ? undefined : destination,
		move_cards_to_built_in: toBuiltIn
	});

	if (error) return settingsWriteError(error);
	if (isStale(data)) return staleSettingsResponse(data);

	const result = data as { status: string; card_count?: number };
	if (result.status === 'needs_destination') {
		return json(
			{
				error: 'This stage has cards in it. Choose where they go first.',
				reason: 'needs_destination',
				card_count: result.card_count ?? 0
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	}

	return json(data, { headers: NO_STORE_HEADERS });
};
