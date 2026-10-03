import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { requireSupportMember, supportSendLimited } from '$lib/server/support/access';
import { readOrganizationSetupCatalogue } from '$lib/server/setup/catalogue';
import { readMemberAttachments } from '$lib/server/support/attachments';
import { readChats } from '$lib/server/support/team';
import { supportStartThreadSchema } from '$lib/server/validation/support.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { catalogueSection } from '$lib/setup/catalogue';
import type { SupportChats } from '$lib/support/api';

// The messenger's chat lists: the member's own chats, and someone else's they may see (D3, D4a).
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const supabase = event.locals.supabase;
	try {
		const [chats, settings] = await Promise.all([
			readChats(supabase, check.auth.organization.id, check.auth.user.id),
			supabase.from('platform_support_settings').select('availability_note').maybeSingle()
		]);
		if (settings.error) return databaseError();
		const body: SupportChats = {
			...chats,
			availability_note: settings.data?.availability_note ?? ''
		};
		return json(body, { headers: PRIVATE_READ_HEADERS });
	} catch {
		return databaseError();
	}
};

// A new chat with its first message (D4a: each question is its own chat). The topic is optional.
export const POST: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const limited = await supportSendLimited(event, check.auth.user.id);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = supportStartThreadSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	if (parsed.data.context_section) {
		const catalogue = await readOrganizationSetupCatalogue(
			event.locals.supabase,
			check.auth.organization.id
		);
		if (!catalogue) return databaseError();
		if (!catalogueSection(catalogue, parsed.data.context_section))
			return validationError({ context_section: 'That setup section is not recognised.' });
	}

	const files = await readMemberAttachments(check.auth.organization.id, parsed.data.attachments);
	if ('response' in files) return files.response;

	const { data, error } = await event.locals.supabase.rpc('start_support_thread', {
		target_organization_id: check.auth.organization.id,
		thread_topic: parsed.data.topic,
		message_body: parsed.data.body,
		message_client_id: parsed.data.client_message_id,
		message_attachments: files.attachments,
		thread_context_section: parsed.data.context_section
	});
	if (error) {
		if (error.code === '42501')
			return json(
				{ error: 'Only an active team member can message Uplift.', reason: 'permission_denied' },
				{ status: 403 }
			);
		if (error.code === '23514')
			return validationError({ body: error.message ?? 'That message could not be sent.' });
		console.error('Could not start a support chat.', error);
		return databaseError();
	}

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
