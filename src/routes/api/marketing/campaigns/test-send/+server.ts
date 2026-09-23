import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { marketingCampaignContentSchema } from '$lib/marketing/campaign-content';
import { MarketingEmailSubmissionError } from '$lib/server/communications/ses';
import { MarketingTestSendError, sendTestMarketingEmail } from '$lib/server/marketing/test-send';

// "Send a test email" in CampaignReviewStep.svelte -- content-only like preview/, no campaign id or saved
// draft required. marketing.draft is enough (the same permission that lets someone edit and preview a
// campaign) since this never touches a real customer or the Marketing allowance. The recipient is always the
// signed-in member's own address, never client-supplied, so a test can't be turned into an arbitrary send.

const testSendSchema = z.object({ content: marketingCampaignContentSchema });

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.draft');
	if ('response' in access) return access.response;

	const recipientEmail = access.auth.user.email;
	if (!recipientEmail) {
		return validationError({
			form: 'Your account has no email address on file to send a test to.'
		});
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = testSendSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const result = await sendTestMarketingEmail(
			access.auth.organization.id,
			recipientEmail,
			parsed.data.content
		);
		return json(result, { headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof MarketingTestSendError) {
			return validationError({ form: error.message });
		}
		if (error instanceof MarketingEmailSubmissionError) {
			return validationError({ form: error.message });
		}
		console.error('Could not send a Marketing test email.', error);
		return databaseError();
	}
};
