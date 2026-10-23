import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import {
	syncTollfreeProofAnswers,
	tollfreeProofUrl,
	tollfreeProofs
} from '$lib/server/communications/sms-tollfree-proof';
import { deleteObject, putObject } from '$lib/server/storage/r2';

const MAX_BYTES = 5 * 1024 * 1024;

async function context(event: Parameters<RequestHandler>[0]): Promise<
	| { response: Response; client?: never; organizationId?: never; check?: never }
	| {
			response?: never;
			client: ReturnType<typeof getOwnerSupabaseClient>;
			organizationId: string;
			check: {
				id: string;
				answers: import('$lib/database.types').Json;
				revision: number;
				status: string;
			};
	  }
> {
	const auth = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in auth) return { response: auth.response };
	const senderId = z.uuid().safeParse(event.params.senderId);
	if (!senderId.success) return { response: json({ error: 'Number not found.' }, { status: 404 }) };
	const client = getOwnerSupabaseClient();
	const organizationId = auth.auth.organization.id;
	const { data: check, error } = await client
		.from('communication_sms_tollfree_verifications')
		.select('id, answers, revision, status')
		.eq('organization_id', organizationId)
		.eq('sender_identity_id', senderId.data)
		.maybeSingle();
	if (error) return { response: databaseError() };
	if (!check) return { response: json({ error: 'Start this check first.' }, { status: 404 }) };
	if (check.status !== 'draft' && check.status !== 'needs_fix')
		return { response: json({ error: 'This check cannot be changed now.' }, { status: 409 }) };
	return { client, organizationId, check };
}

function imageMime(bytes: Uint8Array): 'image/jpeg' | 'image/png' | null {
	if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff)
		return 'image/jpeg';
	if (bytes.length >= 8 && [137, 80, 78, 71, 13, 10, 26, 10].every((part, i) => bytes[i] === part))
		return 'image/png';
	return null;
}

export const POST: RequestHandler = async (event) => {
	const scope = await context(event);
	if (scope.response) return scope.response;
	try {
		// Check public delivery before accepting bytes; Twilio must be able to read the link for days.
		tollfreeProofUrl(crypto.randomUUID());
		const form = await event.request.formData();
		const file = form.get('picture');
		const revision = z.coerce.number().int().min(1).safeParse(form.get('expected_revision'));
		if (!(file instanceof File) || !revision.success || file.size < 1 || file.size > MAX_BYTES)
			return json({ error: 'Add a JPG or PNG picture up to 5 MB.' }, { status: 422 });
		if (revision.data !== scope.check.revision)
			return json({ error: 'This check changed elsewhere. Reload it first.' }, { status: 409 });
		const proofs = await tollfreeProofs(scope.client, scope.organizationId, scope.check.id);
		if (proofs.length >= 5)
			return json({ error: 'Add no more than five pictures.' }, { status: 422 });
		const bytes = new Uint8Array(await file.arrayBuffer());
		const mime = imageMime(bytes);
		if (!mime || (file.type && file.type !== mime))
			return json({ error: 'Add a JPG or PNG picture.' }, { status: 422 });
		const token = crypto.randomUUID();
		const objectKey = `${scope.organizationId}/tollfree-proof/${scope.check.id}/${token}`;
		await putObject(objectKey, bytes, mime);
		const { data: picture, error } = await scope.client
			.from('communication_sms_tollfree_proof_images')
			.insert({
				organization_id: scope.organizationId,
				verification_id: scope.check.id,
				public_token: token,
				object_key: objectKey,
				mime_type: mime,
				file_name: file.name.slice(0, 140) || 'picture',
				size_bytes: bytes.length
			})
			.select('id')
			.single();
		if (error) {
			await deleteObject(objectKey).catch(() => undefined);
			throw error;
		}
		const currentAnswers =
			scope.check.answers &&
			typeof scope.check.answers === 'object' &&
			!Array.isArray(scope.check.answers)
				? scope.check.answers
				: {};
		const nextRevision = await syncTollfreeProofAnswers(
			scope.client,
			scope.organizationId,
			scope.check.id,
			currentAnswers,
			revision.data
		);
		if (!nextRevision) {
			await scope.client
				.from('communication_sms_tollfree_proof_images')
				.delete()
				.eq('id', picture.id);
			await deleteObject(objectKey).catch(() => undefined);
			return json({ error: 'This check changed elsewhere. Reload it first.' }, { status: 409 });
		}
		return json(
			{
				id: picture.id,
				revision: nextRevision,
				pictures: await tollfreeProofs(scope.client, scope.organizationId, scope.check.id)
			},
			{ status: 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not add toll-free proof picture.', error);
		return json({ error: 'The picture could not be added. Try again.' }, { status: 503 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	const scope = await context(event);
	if (scope.response) return scope.response;
	const parsed = z
		.object({ id: z.uuid(), expected_revision: z.number().int().min(1) })
		.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) return json({ error: 'Choose a picture to remove.' }, { status: 422 });
	if (parsed.data.expected_revision !== scope.check.revision)
		return json({ error: 'This check changed elsewhere. Reload it first.' }, { status: 409 });
	const { data: picture, error: readError } = await scope.client
		.from('communication_sms_tollfree_proof_images')
		.select('object_key')
		.eq('organization_id', scope.organizationId)
		.eq('verification_id', scope.check.id)
		.eq('id', parsed.data.id)
		.maybeSingle();
	if (readError) return databaseError();
	if (!picture) return json({ error: 'Picture not found.' }, { status: 404 });
	const { error } = await scope.client
		.from('communication_sms_tollfree_proof_images')
		.delete()
		.eq('organization_id', scope.organizationId)
		.eq('verification_id', scope.check.id)
		.eq('id', parsed.data.id);
	if (error) return databaseError();
	const currentAnswers =
		scope.check.answers &&
		typeof scope.check.answers === 'object' &&
		!Array.isArray(scope.check.answers)
			? scope.check.answers
			: {};
	try {
		const revision = await syncTollfreeProofAnswers(
			scope.client,
			scope.organizationId,
			scope.check.id,
			currentAnswers,
			parsed.data.expected_revision
		);
		if (!revision)
			return json({ error: 'This check changed elsewhere. Reload it first.' }, { status: 409 });
		await deleteObject(picture.object_key).catch(() => undefined);
		return json(
			{
				revision,
				pictures: await tollfreeProofs(scope.client, scope.organizationId, scope.check.id)
			},
			{ headers: NO_STORE_HEADERS }
		);
	} catch (cause) {
		console.error('Could not remove toll-free proof picture.', cause);
		return databaseError();
	}
};
