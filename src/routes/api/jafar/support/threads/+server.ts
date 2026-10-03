import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	SupportAttachmentError,
	resolveSupportAttachments,
	type ResolvedSupportAttachment
} from '$lib/server/support/attachments';
import { readSupportInbox, readSupportSettings } from '$lib/server/support/inbox';
import {
	supportInboxQuerySchema,
	supportUpliftStartThreadSchema
} from '$lib/server/validation/support.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// The Support Inbox: every contractor's chat with Uplift, newest activity first, optionally one topic's,
// plus how Uplift currently appears to them. Separate from any tenant's customer inbox.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsed = supportInboxQuerySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined,
		topic: event.url.searchParams.get('topic') ?? undefined,
		status: event.url.searchParams.get('status') ?? undefined
	});
	if (!parsed.success) return json({ error: 'The inbox filter is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const [inbox, settings] = await Promise.all([
			readSupportInbox(client, parsed.data.limit, parsed.data.topic, parsed.data.status),
			readSupportSettings(client)
		]);
		return json({ ...inbox, settings });
	} catch (error) {
		console.error('Could not load the Support Inbox.', error);
		return json({ error: 'The Support Inbox could not be loaded.' }, { status: 500 });
	}
};

// Uplift starts a chat with one active team member (D5a). The chat is theirs, as if they had started it:
// it shows in their own list, counts on their badge, and follows the same who-sees-what rules.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = supportUpliftStartThreadSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review your message.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	let attachments: ResolvedSupportAttachment[];
	try {
		attachments = await resolveSupportAttachments(
			parsed.data.organization_id,
			parsed.data.attachments
		);
	} catch (error) {
		if (error instanceof SupportAttachmentError)
			return json({ error: error.message }, { status: 422 });
		console.error('Could not check the files for a new support chat.', error);
		return json({ error: 'Your message could not be sent.' }, { status: 500 });
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('start_support_thread_by_uplift', {
		target_organization_id: parsed.data.organization_id,
		target_user_id: parsed.data.user_id,
		thread_topic: parsed.data.topic,
		actor_email: session.email,
		message_body: parsed.data.body,
		message_client_id: parsed.data.client_message_id,
		message_attachments: attachments
	});
	if (error) {
		// The function's own sentences are written for Jafar: the missing responder name, who to write to.
		if (error.code === '23514') return json({ error: error.message }, { status: 422 });
		console.error('Could not start a support chat.', error);
		return json({ error: 'Your message could not be sent.' }, { status: 500 });
	}

	return json(data, { status: 201 });
};
