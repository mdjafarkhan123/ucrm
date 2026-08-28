import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';
import {
	websiteChatSuspensionSchema,
	websiteChatTokenRotationSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'cache-control': 'no-store' };

async function loadAuthority(organizationId: string) {
	const client = getOwnerSupabaseClient();
	const { data, error } = await client.rpc('get_organization_website_chat_authority', {
		p_organization_id: organizationId
	});
	if (error) throw error;
	return data;
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		return json({ authority: await loadAuthority(organizationId.data) }, { headers: noStore });
	} catch (error) {
		console.error('Could not load Website Chat authority.', error);
		return json({ error: 'Website Chat authority could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success) {
		return json(
			{
				error: 'The organization identifier is invalid.',
				field_errors: zodAccessFieldErrors(organizationId.error)
			},
			{ status: 422 }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const action =
		typeof body === 'object' && body !== null && 'action' in body ? body.action : undefined;
	const client = getOwnerSupabaseClient();

	try {
		if (action === 'suspend' || action === 'restore') {
			const parsed = websiteChatSuspensionSchema.safeParse({
				...(body as object),
				engage: action === 'suspend'
			});
			if (!parsed.success) {
				return json(
					{
						error: 'Please review the suspension details.',
						field_errors: zodOwnerFieldErrors(parsed.error)
					},
					{ status: 422 }
				);
			}
			const { error } = await client.rpc('set_organization_website_chat_suspension', {
				p_organization_id: organizationId.data,
				p_engage: parsed.data.engage,
				p_reason: parsed.data.reason,
				p_actor_email: session.email,
				p_idempotency_key: parsed.data.idempotency_key
			});
			if (error) throw error;
		} else if (action === 'rotate_token') {
			const parsed = websiteChatTokenRotationSchema.safeParse(body);
			if (!parsed.success) {
				return json(
					{
						error: 'Please review the token rotation details.',
						field_errors: zodOwnerFieldErrors(parsed.error)
					},
					{ status: 422 }
				);
			}
			const { error } = await client.rpc('rotate_website_chat_widget_public_token', {
				p_organization_id: organizationId.data,
				p_widget_id: parsed.data.widget_id,
				p_expected_revision: parsed.data.expected_revision,
				p_reason: parsed.data.reason,
				p_actor_email: session.email,
				p_idempotency_key: parsed.data.idempotency_key
			});
			if (error) throw error;
		} else {
			return json({ error: 'Choose a valid Website Chat authority action.' }, { status: 422 });
		}

		return json({ authority: await loadAuthority(organizationId.data) }, { headers: noStore });
	} catch (error) {
		const code =
			typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : '';
		const message =
			typeof error === 'object' && error !== null && 'message' in error
				? String(error.message)
				: 'Website Chat authority could not be changed.';
		if (code === '23503') return json({ error: message }, { status: 404 });
		if (['23505', '23514', '40001'].includes(code))
			return json({ error: message }, { status: 409 });
		console.error('Could not change Website Chat authority.', error);
		return json({ error: 'Website Chat authority could not be changed.' }, { status: 500 });
	}
};
