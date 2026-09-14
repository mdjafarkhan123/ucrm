import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	smsNumberActionSchema,
	smsSettingsFieldErrors
} from '$lib/server/validation/communications-sms-settings.schema';
import { safeSmsSender, type SmsSenderRow } from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };
const senderIdSchema = z.string().uuid();

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

// A raised P0001 from the number commands carries a contractor-friendly message. "not found" is a 404; every
// other guarded state (released, not ready, not SMS-capable) is a 409 the contractor can act on.
function commandError(message: string) {
	if (/not found/i.test(message)) {
		return json({ error: 'That number was not found.' }, { status: 404, headers: noStore });
	}
	return json({ error: message }, { status: 409, headers: noStore });
}

// Rename a number or make it the organization's default sending number. Both are contractor-safe: renaming is
// local metadata, and set-default only chooses among numbers the org already owns. Provider actions are absent.
export const PATCH: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const senderId = senderIdSchema.safeParse(event.params.senderId);
	if (!senderId.success) {
		return json({ error: 'The number identifier is invalid.' }, { status: 422, headers: noStore });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = smsNumberActionSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the number details.',
				field_errors: smsSettingsFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	const result =
		parsed.data.action === 'rename'
			? await client.rpc('communication_sms_rename_sender', {
					p_organization_id: check.auth.organization.id,
					p_sender_id: senderId.data,
					// The command applies nullif(btrim(...), '') itself, so an empty string clears the label back to
					// the phone number -- identical to the null the schema normalises to.
					p_display_name: parsed.data.display_name ?? '',
					p_actor: check.auth.user.id
				})
			: await client.rpc('communication_sms_set_default_sender', {
					p_organization_id: check.auth.organization.id,
					p_sender_id: senderId.data,
					p_actor: check.auth.user.id
				});

	if (result.error) {
		if (result.error.code === 'P0001') {
			return commandError(result.error.message);
		}
		console.error('Could not update the SMS number.', result.error);
		return json({ error: 'The number could not be updated.' }, { status: 500, headers: noStore });
	}

	return json({ number: safeSmsSender(result.data as SmsSenderRow) }, { headers: noStore });
};
