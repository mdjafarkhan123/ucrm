import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { collectJobSignatureSchema } from '$lib/server/validation/signatures.schema';
import { signatureReadError, signatureWriteError } from '$lib/server/signatures/errors';
import type { JobSignature } from '$lib/signatures/types';
import { buildJobSignatureObjectKey } from '$lib/server/storage/r2';
import {
	decodeSignatureImage,
	discardSignatureImage,
	storeSignatureImageAt
} from '$lib/server/storage/signature-image';
// The same truncated-IP-and-user-agent note a customer's quote decision keeps. What is worth recording
// about where a signature came from does not change because a crew member is holding the tablet.
import { customerDecisionEvidence } from '$lib/server/quotes/access-links';

type SignatureListPayload = {
	signatures: (JobSignature & { collected_by: string | null })[];
	can_collect: boolean;
};

// One job's collected signatures. `job_signatures_for_job` is definer and decides for itself what this
// reader may see — a Field member at assigned scope gets the job's signatures only for jobs they are on —
// so a reader who may see less simply gets less rather than a second gate here. The collector's name is
// resolved separately through `profiles`, the same way the job's history does it; a collector who has
// since left simply shows no name rather than an id.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const supabase = event.locals.supabase;
	const { data, error } = await supabase.rpc('job_signatures_for_job', {
		target_job_id: event.params.id
	});
	if (error) return signatureReadError(error);

	const payload = data as unknown as SignatureListPayload;
	const collectorIds = [
		...new Set(payload.signatures.map((row) => row.collected_by).filter((id): id is string => !!id))
	];

	const names = new Map<string, string>();
	if (collectorIds.length > 0) {
		const profiles = await supabase.from('profiles').select('id, full_name').in('id', collectorIds);
		if (profiles.error) return databaseError();
		for (const profile of profiles.data ?? []) {
			if (profile.full_name) names.set(profile.id, profile.full_name);
		}
	}

	return json(
		{
			signatures: payload.signatures.map((row) => ({
				...row,
				collected_by_name: row.collected_by ? (names.get(row.collected_by) ?? null) : null
			})),
			can_collect: payload.can_collect
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Collecting one. The gate here is jobs.view, the same one that lets a person open the job at all; whether
// they may collect — field_records.record, and the job being one they are on — is decided by the command.
//
// The drawn PNG is verified and stored before the command runs, because the command takes a row lock and
// the behavior contract forbids a network call while a row is held. If the command then refuses, the
// object is unreferenced and discarded here, so a refusal never leaves an orphan anybody can name.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = collectJobSignatureSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	let objectKey: string | null = null;
	let byteSize: number | null = null;
	if (parsed.data.image) {
		const image = decodeSignatureImage(parsed.data.image);
		if (!image) return validationError({ image: 'That signature could not be read.' });
		try {
			objectKey = await storeSignatureImageAt(
				buildJobSignatureObjectKey(check.auth.organization.id, event.params.id),
				image
			);
			byteSize = image.byteSize;
		} catch {
			return json(
				{ error: 'We could not save that signature. Please try again in a moment.' },
				{ status: 500, headers: NO_STORE_HEADERS }
			);
		}
	}

	const { data, error } = await event.locals.supabase.rpc('collect_job_signature', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		new_signature_type: parsed.data.signature_type,
		new_signer_name: parsed.data.signer_name,
		new_statement: parsed.data.statement,
		new_method: parsed.data.method,
		new_signer_role: parsed.data.signer_role ?? undefined,
		target_visit_id: parsed.data.visit_id ?? undefined,
		new_image_object_key: objectKey ?? undefined,
		new_image_byte_size: byteSize ?? undefined,
		supplied_evidence: customerDecisionEvidence(
			event.getClientAddress(),
			event.request.headers.get('user-agent') ?? null
		)
	});
	if (error) {
		await discardSignatureImage(objectKey);
		return signatureWriteError(error);
	}

	return json(data, { headers: NO_STORE_HEADERS });
};
