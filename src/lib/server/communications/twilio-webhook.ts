import { validateRequest } from 'twilio';
import { env } from '$env/dynamic/private';
import { z } from 'zod';

// Signed Twilio status callbacks (Stage 5A). Signature validation uses the official `twilio` library
// (`validateRequest`) -- Jafar approved this as the mature-industry approach, and it is the ONLY place the
// library is used; every other Twilio call in this codebase stays hand-rolled. The route learns the
// subaccount from the *unvalidated* AccountSid, loads that subaccount's Auth Token(s), then validates the
// signature against the exact URL we registered with Twilio. Nothing here logs bodies or credentials.

/** The status-callback URL exactly as our provisioning registers it with Twilio. Twilio signs over this
 *  string, so it must match the registered StatusCallback byte for byte -- never the incoming request URL,
 *  which a proxy can rewrite. Mirrors the APP_URL discipline used by the outbound email links. */
export function getTwilioStatusWebhookUrl(): string {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin)
		throw new Error('APP_URL must be set before Twilio status callbacks can be handled.');
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	return `${origin.origin}/api/webhooks/twilio/status`;
}

/** A decrypted Auth Token candidate, tagged with its rotation lifecycle. `prior` carries a retirement
 *  instant; it is accepted only while that instant is still in the future. `current`/`staged` have none. */
export type ValidationTokenCandidate =
	| {
			token: string;
			retireAfter?: string | null;
	  }
	| null
	| undefined;

/**
 * Ordered list of Auth Tokens to try when validating a signature, newest first. During an Auth Token
 * rotation the real token may briefly be any of current, the just-promoted staged, or the retiring prior --
 * so we accept the overlap. The prior token is dropped the moment its retire_after passes, closing the
 * window a leaked old token could be replayed in. Empty tokens are ignored. Pure and fully unit-testable.
 */
export function orderedValidationTokens(
	tokens: {
		current?: ValidationTokenCandidate;
		staged?: ValidationTokenCandidate;
		prior?: ValidationTokenCandidate;
	},
	now: Date
): string[] {
	const ordered: string[] = [];

	for (const candidate of [tokens.current, tokens.staged]) {
		const token = candidate?.token?.trim();
		if (token) ordered.push(token);
	}

	const prior = tokens.prior;
	const priorToken = prior?.token?.trim();
	if (priorToken && prior?.retireAfter) {
		const retireAfter = new Date(prior.retireAfter);
		if (!Number.isNaN(retireAfter.getTime()) && retireAfter.getTime() > now.getTime()) {
			ordered.push(priorToken);
		}
	}

	return ordered;
}

/**
 * True when `signature` is a valid Twilio signature for `url` + `params` under any of the ordered tokens.
 * A missing signature or an empty token list is never valid. `validateRequest` is defensive but we still
 * guard it so a malformed input can only ever fail closed.
 */
export function validateTwilioSignature(
	tokens: string[],
	signature: string | null | undefined,
	url: string,
	params: Record<string, string>
): boolean {
	if (!signature) return false;
	for (const token of tokens) {
		try {
			if (validateRequest(token, signature, url, params)) return true;
		} catch {
			// A single malformed token must not abort the remaining candidates.
		}
	}
	return false;
}

const statusParamsSchema = z
	.object({
		MessageSid: z
			.string()
			.trim()
			.regex(/^(SM|MM)[0-9A-Fa-f]{32}$/),
		MessageStatus: z.string().trim().min(1).max(40),
		AccountSid: z
			.string()
			.trim()
			.regex(/^AC[0-9A-Fa-f]{32}$/)
	})
	.passthrough();

export type TwilioStatusParams = {
	MessageSid: string;
	MessageStatus: string;
	AccountSid: string;
};

/** Parse the identifying fields of a status callback. Returns null when the shape is not a Twilio status
 *  callback at all; the full param set is still what gets signature-checked and stored. */
export function parseTwilioStatusParams(params: Record<string, string>): TwilioStatusParams | null {
	const parsed = statusParamsSchema.safeParse(params);
	if (!parsed.success) return null;
	return {
		MessageSid: parsed.data.MessageSid,
		MessageStatus: parsed.data.MessageStatus,
		AccountSid: parsed.data.AccountSid
	};
}

/** Dedupe key for the shared callback spine: one row per (message, status). Twilio resends the same status
 *  on retry, and out-of-order duplicates collapse onto the same key via unique(provider, provider_event_key). */
export function statusEventKey(
	params: Pick<TwilioStatusParams, 'MessageSid' | 'MessageStatus'>
): string {
	return `${params.MessageSid}:${params.MessageStatus}`;
}
