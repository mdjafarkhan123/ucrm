import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import {
	createNumberPaperworkDeps,
	loadPaperworkForm,
	PaperworkError,
	sendNumberPaperwork
} from '$lib/server/communications/sms-number-paperwork';
import {
	presentPaperwork,
	readPaperwork
} from '$lib/server/communications/sms-number-paperwork-api';
import {
	paperworkFieldErrors,
	paperworkSendSchema
} from '$lib/server/validation/communications-sms-paperwork.schema';

const STATUS: Record<PaperworkError['code'], number> = {
	not_sendable: 409,
	incomplete: 422,
	provider_unavailable: 503
};

// Send the paperwork to the phone company for review. Sending again after a dropped connection continues
// the same set at Twilio rather than making a second one.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	const id = z.uuid().safeParse(event.params.paperworkId);
	if (!id.success) {
		return json(
			{ error: 'That paperwork was not found.' },
			{ status: 404, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}
	const parsed = paperworkSendSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the paperwork.', field_errors: paperworkFieldErrors(parsed.error) },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const deps = createNumberPaperworkDeps();
	try {
		await sendNumberPaperwork(deps, {
			organizationId,
			paperworkId: id.data,
			expectedRevision: parsed.data.expected_revision,
			actorUserId: check.auth.user.id
		});
	} catch (error) {
		if (error instanceof PaperworkError) {
			return json(
				{ error: error.message, code: error.code, problems: error.problems },
				{ status: STATUS[error.code], headers: NO_STORE_HEADERS }
			);
		}
		console.error('Could not send the number paperwork.', error);
		return json(
			{ error: 'Something went wrong. Try again; nothing is sent twice.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const loaded = await readPaperwork(client, organizationId, id.data);
		if (!loaded) return databaseError();
		const { form } = await loadPaperworkForm(deps.catalog, {
			countryCode: loaded.paperwork.countryCode,
			numberType: loaded.paperwork.numberType,
			endUserType: loaded.paperwork.endUserType
		});
		return json(
			{ paperwork: await presentPaperwork(client, loaded, form) },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not read the sent paperwork.', error);
		return databaseError();
	}
};
