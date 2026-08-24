import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { collectQuoteSignatureSchema } from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';
import {
	decodeSignatureImage,
	discardSignatureImage,
	storeSignatureImage
} from '$lib/server/quotes/signatures';

// Jobber's Collect Signature: the in-person close, on the staff member's own device at the customer's
// door. Signing here is what approves the quote, so this is an approval with a different method rather
// than a separate kind of event — the answer lands in the same decision history as "they rang and said
// yes". From a draft the command publishes first, because a signature on a document that was never
// frozen is a signature on nothing.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.record_decision');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = collectQuoteSignatureSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// Stored before the command and outside its lock, exactly like the customer's. A refused command
	// leaves an object nothing points at, and it is deleted below.
	let objectKey: string | undefined;
	let byteSize: number | undefined;

	if (parsed.data.image) {
		const image = decodeSignatureImage(parsed.data.image);
		if (!image) return validationError({ image: 'That signature could not be read.' });

		try {
			objectKey = await storeSignatureImage(check.auth.organization.id, event.params.id, image);
			byteSize = image.byteSize;
		} catch {
			console.error('A signature could not be stored.');
			return json({ error: 'That signature could not be saved.' }, { status: 500 });
		}
	}

	const { data, error } = await event.locals.supabase.rpc('record_quote_in_person_signature', {
		target_quote_id: event.params.id,
		signer_name: parsed.data.name,
		signature_method: parsed.data.method,
		signature_object_key: objectKey,
		signature_byte_size: byteSize,
		decision_note: parsed.data.note,
		expected_revision: parsed.data.expected_revision ?? null
	});

	if (error) {
		await discardSignatureImage(objectKey);
		return quoteWriteError(error);
	}

	return json(data, { headers: NO_STORE_HEADERS });
};
