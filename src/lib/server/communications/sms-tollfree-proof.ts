import { env } from '$env/dynamic/private';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

type Client = SupabaseClient<Database>;

export function tollfreeProofUrl(token: string): string {
	const origin = new URL(env.APP_URL ?? '');
	if (origin.protocol !== 'https:')
		throw new Error('A public HTTPS app address is needed for carrier proof.');
	return new URL(`/api/public/sms/toll-free-proof/${token}`, origin).toString();
}

export async function tollfreeProofs(
	client: Client,
	organizationId: string,
	verificationId: string
) {
	const { data, error } = await client
		.from('communication_sms_tollfree_proof_images')
		.select('id, public_token, file_name, size_bytes, created_at')
		.eq('organization_id', organizationId)
		.eq('verification_id', verificationId)
		.order('created_at', { ascending: true });
	if (error) throw error;
	return data ?? [];
}

export async function syncTollfreeProofAnswers(
	client: Client,
	organizationId: string,
	verificationId: string,
	currentAnswers: Record<string, unknown>,
	expectedRevision: number
) {
	const proofs = await tollfreeProofs(client, organizationId, verificationId);
	const answers = {
		...currentAnswers,
		opt_in_image_urls: proofs.map((proof) => tollfreeProofUrl(proof.public_token))
	};
	const { data, error } = await client
		.from('communication_sms_tollfree_verifications')
		.update({ answers, revision: expectedRevision + 1, updated_at: new Date().toISOString() })
		.eq('organization_id', organizationId)
		.eq('id', verificationId)
		.eq('revision', expectedRevision)
		.in('status', ['draft', 'needs_fix'])
		.select('revision')
		.maybeSingle();
	if (error) throw error;
	return data?.revision ?? null;
}
