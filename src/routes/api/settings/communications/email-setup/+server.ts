import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import {
	EmailSetupRequestError,
	createEmailSetupRequest,
	loadEmailSetup
} from '$lib/server/communications/email-setup-requests';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	emailSetupRequestSchema
} from '$lib/server/validation/communications.schema';
import { mailboxProviderLabel } from '$lib/communications/email-setup';

const noStore = { 'Cache-Control': 'no-store' };

// Owners and admins ask Jafar to set up the business's email; a plain member never sees this page's actions.
// "Setting up" and "Ready" are read from the sending domains (see email-setup-requests.ts), not stored.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	try {
		const setup = await loadEmailSetup(getOwnerSupabaseClient(), check.auth.organization.id);
		return json(setup, { headers: noStore });
	} catch (error) {
		console.error('Could not load the email setup state.', error);
		return json(
			{ error: 'Your email setup could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = emailSetupRequestSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the request details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `email_setup_request:${check.auth.organization.id}`,
			windowSeconds: 3600,
			maxAttempts: 10
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const created = await createEmailSetupRequest(client, {
			organizationId: check.auth.organization.id,
			actorId: check.auth.user.id,
			rootDomain: parsed.data.root_domain,
			mailboxProvider: parsed.data.mailbox_provider,
			note: parsed.data.note
		});

		// The ask is saved; the alert is best effort so a notification hiccup never loses the contractor's request.
		try {
			await raiseOwnerAlert(client, {
				kind: 'email_setup_requested',
				severity: 'attention',
				title: `${check.auth.organization.name} asked for email setup`,
				body: `Domain ${created.root_domain}. Email lives at: ${mailboxProviderLabel(created.mailbox_provider)}.`,
				target: { targetKind: 'organization', targetId: check.auth.organization.id },
				correlationId: created.id,
				origin: event.url.origin
			});
		} catch (alertError) {
			console.error('Could not raise the email setup alert.', alertError);
		}

		return json(await loadEmailSetup(client, check.auth.organization.id), {
			status: 201,
			headers: noStore
		});
	} catch (error) {
		if (error instanceof EmailSetupRequestError) {
			return json({ error: error.message }, { status: error.status, headers: noStore });
		}
		console.error('Could not create the email setup request.', error);
		return json({ error: 'The request could not be sent.' }, { status: 500, headers: noStore });
	}
};
