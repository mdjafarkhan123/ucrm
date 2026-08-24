import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import type { ZodType } from 'zod';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	customerDecisionEvidence,
	getQuoteAccessResolverClient,
	quoteAccessIpBucketKey,
	quoteAccessTokenBucketKey,
	quoteAccessTokenHash
} from '$lib/server/quotes/access-links';
import {
	decodeSignatureImage,
	discardSignatureImage,
	storeSignatureImage
} from '$lib/server/quotes/signatures';

// The customer's side of the wire. Approving and asking for changes are the same journey with a
// different word on the button, so they share this handler and differ only in the body they accept and
// the outcome they send - two route files that drifted apart would be two ways to answer a quote.
//
// Nothing here trusts the caller for anything but the token and a message. Which quote, which version
// and whether an answer is even allowed are all decided inside the database command.

// Deliberately vague, and deliberately the same sentence for a token that never existed, one that was
// turned off, one that ran out, and one for a document that has since been replaced. A person holding a
// dead link needs to know to ask for a new one; nobody needs to learn which of those it was.
const UNAVAILABLE = 'This quote is no longer available. Ask the company for an up-to-date link.';

// A public write with no session behind it, so both limits are low. The window is generous enough for a
// person who taps twice, tight enough that the URL space is not worth walking.
const DECISION_LIMIT = { windowSeconds: 300, maxAttempts: 8 };
const DECISION_TOKEN_LIMIT = { windowSeconds: 300, maxAttempts: 5 };

type DecisionOutcome = 'approved' | 'changes_requested';

type CustomerSignature = { name: string; method: 'typed' | 'drawn'; image?: string };

export async function handleCustomerDecision(
	event: RequestEvent<{ token: string }>,
	outcome: DecisionOutcome,
	schema: ZodType<{ note?: string; signature?: CustomerSignature }>
) {
	const noStore = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

	const tokenHash = quoteAccessTokenHash(event.params.token);
	// A token of the wrong shape never reaches the database, and never spends a rate-limit slot either.
	if (!tokenHash) return json({ error: UNAVAILABLE }, { status: 410, headers: noStore });

	const client = getQuoteAccessResolverClient();
	const address = event.getClientAddress();

	// Both buckets are checked together rather than one after the other. The answer that matters is
	// "either of these is full", and a customer on a phone should not wait for two round trips in a row
	// to find out that neither is.
	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: quoteAccessIpBucketKey('decision', address),
			...DECISION_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: quoteAccessTokenBucketKey('decision', tokenHash),
			...DECISION_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byToken.allowed) return rateLimitedResponse(byToken.retryAfterSeconds);

	let body: unknown = {};
	const raw = await event.request.text();
	if (raw.trim().length > 0) {
		try {
			body = JSON.parse(raw);
		} catch {
			return json({ error: 'We could not read that. Please try again.' }, { status: 400 });
		}
	}

	const parsed = schema.safeParse(body);
	if (!parsed.success) {
		// One field, one sentence, in the customer's words. The staff shape with `field_errors` would be
		// telling a homeowner about our form validation.
		const first = parsed.error.issues[0];
		return json(
			{ error: first?.message ?? 'Please check what you have written.' },
			{ status: 422, headers: noStore }
		);
	}

	const signature = parsed.data.signature;

	// The drawing is checked and stored before the command runs, because the contract forbids a network
	// call while the quote's row is locked. If the command then refuses, the object is unreferenced and
	// deleted below - an orphan nobody can name is cheaper than a lock held across the wire.
	let objectKey: string | undefined;
	let byteSize: number | undefined;

	if (signature?.image) {
		const image = decodeSignatureImage(signature.image);
		if (!image) {
			return json(
				{ error: 'That signature could not be read. Please sign again.' },
				{ status: 422, headers: noStore }
			);
		}

		// The customer's document deliberately never names its organization or its quote, so the one
		// place that pairing exists is the link row itself. One lookup by the unique token hash, and
		// only when there is actually a drawing to file.
		const { data: link } = await client
			.from('quote_access_links')
			.select('organization_id, quote_id')
			// `tokenHash` is already the hex literal Postgres reads a `bytea` from.
			.eq('token_hash', tokenHash)
			.maybeSingle();
		if (!link) return json({ error: UNAVAILABLE }, { status: 410, headers: noStore });

		try {
			objectKey = await storeSignatureImage(link.organization_id, link.quote_id, image);
			byteSize = image.byteSize;
		} catch {
			// Storage is down, not the customer's problem to solve. Nothing has been written yet.
			console.error('A customer signature could not be stored.');
			return json(
				{ error: 'We could not record that. Please try again in a moment.' },
				{ status: 500, headers: noStore }
			);
		}
	}

	const { data, error } = await client.rpc('submit_quote_customer_decision', {
		supplied_token_hash: tokenHash,
		new_outcome: outcome,
		// Left out entirely rather than sent as null, so the command's own default is what decides what
		// "no message" means.
		...(parsed.data.note ? { customer_note: parsed.data.note } : {}),
		supplied_evidence: customerDecisionEvidence(
			address,
			event.request.headers.get('user-agent') ?? null
		),
		...(signature
			? {
					signature_name: signature.name,
					signature_method: signature.method,
					signature_object_key: objectKey,
					signature_byte_size: byteSize
				}
			: {})
	});

	if (error) {
		await discardSignatureImage(objectKey);
		// The database phrases the two answers a person can act on: this was already answered, and you
		// already asked. Anything else is ours to have got wrong, and is not explained to a customer.
		if (error.code === 'P0409') {
			return json({ error: error.message }, { status: 409, headers: noStore });
		}
		// Logged without the token, the note, or the address. A failure here is either a broken link or
		// somebody probing, and neither belongs in a log file with a customer's URL beside it.
		console.error('A customer decision could not be recorded.', { code: error.code });
		return json(
			{ error: 'We could not record that. Please try again in a moment.' },
			{ status: 500, headers: noStore }
		);
	}

	if (!data) {
		await discardSignatureImage(objectKey);
		return json({ error: UNAVAILABLE }, { status: 410, headers: noStore });
	}

	// A repeated tap. The first signature stands, so the one that came with the retry is filed nowhere and
	// swept up here.
	if ((data as { already_answered?: boolean }).already_answered) {
		await discardSignatureImage(objectKey);
	}

	return json(data, { headers: noStore });
}
