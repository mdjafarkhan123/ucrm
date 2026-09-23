import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	CampaignCreditConflictError,
	CampaignCreditInvalidError,
	declareCampaignCredit
} from '$lib/server/marketing/campaigns';

// Staff-declared attribution (blueprint §13 method 2, plan M5b): connecting a Request or Job to this
// campaign after reviewing the Customer and timing. Needs marketing.draft, the same tier that edits customer
// groups, templates, and drafts -- declaring attribution is an editorial call on campaign results, not the
// final send marketing.launch gates. Exactly one of request_id/job_id, matching how the credit is stored.

const declareSchema = z
	.object({
		request_id: z.string().uuid().nullable().optional(),
		job_id: z.string().uuid().nullable().optional()
	})
	.refine((body) => Boolean(body.request_id) !== Boolean(body.job_id), {
		message: 'Choose exactly one Request or Job to credit.'
	});

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.draft');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = declareSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const work = parsed.data.request_id
		? { requestId: parsed.data.request_id }
		: { jobId: parsed.data.job_id! };

	try {
		const credit = await declareCampaignCredit(
			access.auth.organization.id,
			access.auth.user.id,
			event.params.id,
			work
		);
		return json(credit, { status: 201, headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof CampaignCreditConflictError) {
			return validationError({ form: 'That work is already credited to a campaign.' });
		}
		if (error instanceof CampaignCreditInvalidError) {
			return validationError({ form: 'That campaign or work item no longer exists.' });
		}
		console.error('Could not declare a marketing campaign credit.', error);
		return databaseError();
	}
};
