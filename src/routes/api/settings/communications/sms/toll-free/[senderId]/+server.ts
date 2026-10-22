import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError, NO_STORE_HEADERS, PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { readRegistrationAnswers } from '$lib/server/communications/sms-number-paperwork-api';
import { tollfreeProofs } from '$lib/server/communications/sms-tollfree-proof';
import type { Json } from '$lib/database.types';

const saveSchema = z
	.object({
		expected_revision: z.number().int().min(1),
		business: z.record(z.string(), z.unknown())
	})
	.refine((value) => JSON.stringify(value.business).length <= 24000, {
		message: 'This draft is too large.'
	});

async function context(event: Parameters<RequestHandler>[0]): Promise<
	| { response: Response; client?: never; organizationId?: never; sender?: never; actorId?: never }
	| {
			response?: never;
			client: ReturnType<typeof getOwnerSupabaseClient>;
			organizationId: string;
			sender: {
				id: string;
				phone_number: string;
				sender_type: string | null;
				number_type: string | null;
				country_code: string | null;
				lifecycle_state: string;
			};
			actorId: string;
	  }
> {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return { response: check.response };
	const senderId = z.uuid().safeParse(event.params.senderId);
	if (!senderId.success)
		return { response: json({ error: 'That number was not found.' }, { status: 404 }) };
	const client = getOwnerSupabaseClient();
	const organizationId = check.auth.organization.id;
	const { data: sender, error } = await client
		.from('communication_sms_sender_identities')
		.select('id, phone_number, sender_type, number_type, country_code, lifecycle_state')
		.eq('organization_id', organizationId)
		.eq('id', senderId.data)
		.maybeSingle();
	if (error) return { response: databaseError() };
	if (
		!sender ||
		(sender.sender_type !== 'toll_free' && sender.number_type !== 'toll_free') ||
		!['US', 'CA'].includes(sender.country_code ?? '') ||
		sender.lifecycle_state === 'released'
	)
		return { response: json({ error: 'That toll-free number was not found.' }, { status: 404 }) };
	return { client, organizationId, sender, actorId: check.auth.user.id };
}

async function present(
	client: ReturnType<typeof getOwnerSupabaseClient>,
	organizationId: string,
	senderId: string
) {
	const { data: check, error } = await client
		.from('communication_sms_tollfree_verifications')
		.select('id, status, answers, revision, failure_reason, edit_expires_at, submitted_at')
		.eq('organization_id', organizationId)
		.eq('sender_identity_id', senderId)
		.maybeSingle();
	if (error) throw error;
	return {
		check,
		pictures: check ? await tollfreeProofs(client, organizationId, check.id) : []
	};
}

export const GET: RequestHandler = async (event) => {
	const scope = await context(event);
	if (scope.response) return scope.response;
	try {
		return json(
			{
				...(await present(scope.client, scope.organizationId, scope.sender.id)),
				phone_number: scope.sender.phone_number
			},
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not read toll-free check.', error);
		return databaseError();
	}
};

export const POST: RequestHandler = async (event) => {
	const scope = await context(event);
	if (scope.response) return scope.response;
	try {
		const existing = await present(scope.client, scope.organizationId, scope.sender.id);
		if (existing.check) return json(existing, { headers: NO_STORE_HEADERS });
		const reused = await readRegistrationAnswers(scope.client, scope.organizationId);
		const { error } = await scope.client.from('communication_sms_tollfree_verifications').insert({
			organization_id: scope.organizationId,
			sender_identity_id: scope.sender.id,
			created_by: scope.actorId,
			answers: { business: reused ?? {}, opt_in_image_urls: [] } as Json
		});
		if (error && error.code !== '23505') throw error;
		return json(await present(scope.client, scope.organizationId, scope.sender.id), {
			status: error ? 200 : 201,
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not start toll-free check.', error);
		return databaseError();
	}
};

export const PATCH: RequestHandler = async (event) => {
	const scope = await context(event);
	if (scope.response) return scope.response;
	const parsed = saveSchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success)
		return json({ error: 'Please review the business details.' }, { status: 422 });
	try {
		const current = (await present(scope.client, scope.organizationId, scope.sender.id)).check;
		if (!current) return json({ error: 'Start this check first.' }, { status: 404 });
		const previous =
			current.answers && typeof current.answers === 'object' && !Array.isArray(current.answers)
				? current.answers
				: {};
		const { data, error } = await scope.client
			.from('communication_sms_tollfree_verifications')
			.update({
				answers: { ...previous, business: parsed.data.business } as Json,
				revision: parsed.data.expected_revision + 1,
				updated_at: new Date().toISOString()
			})
			.eq('organization_id', scope.organizationId)
			.eq('id', current.id)
			.eq('revision', parsed.data.expected_revision)
			.in('status', ['draft', 'needs_fix'])
			.select('id')
			.maybeSingle();
		if (error) throw error;
		if (!data)
			return json(
				{ error: 'This check changed elsewhere. Reload it before saving.' },
				{ status: 409 }
			);
		return json(await present(scope.client, scope.organizationId, scope.sender.id), {
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not save toll-free check.', error);
		return databaseError();
	}
};
