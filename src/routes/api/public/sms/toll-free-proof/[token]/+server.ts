import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getObjectStream } from '$lib/server/storage/r2';

// Twilio's carrier reviewers need this picture after a short presigned link would expire. The random
// 128-bit token is the read permission; no organization or storage key is accepted from the caller.
export const GET: RequestHandler = async (event) => {
	const token = z.uuid().safeParse(event.params.token);
	if (!token.success) return json({ error: 'Picture not found.' }, { status: 404 });
	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_tollfree_proof_images')
		.select('object_key, mime_type')
		.eq('public_token', token.data)
		.maybeSingle();
	if (error || !data) return json({ error: 'Picture not found.' }, { status: 404 });
	try {
		const file = await getObjectStream(data.object_key);
		return new Response(file.body, {
			headers: {
				'content-type': data.mime_type,
				'content-disposition': 'inline',
				'x-content-type-options': 'nosniff',
				'cache-control': 'public, max-age=300',
				...(file.contentLength ? { 'content-length': String(file.contentLength) } : {})
			}
		});
	} catch {
		return json({ error: 'Picture unavailable.' }, { status: 503 });
	}
};
