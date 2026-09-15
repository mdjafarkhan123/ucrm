import { validateRequest } from 'twilio';
import { env } from '$env/dynamic/private';
import { z } from 'zod';
import { decryptTwilioCredential } from './twilio-credential-crypto';
import type { StoredTwilioCredential, TwilioProvisioningStore } from './twilio-provisioning-store';

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
/** Decrypt an Auth Token credential into a rotation candidate; a decryption failure drops that one token
 *  (never the whole request) so a single broken credential can't lock out an otherwise valid signature. */
function toTokenCandidate(
	credential: StoredTwilioCredential | null,
	context: { organizationId: string; subaccountSid: string }
): ValidationTokenCandidate {
	if (!credential) return null;
	try {
		const token = decryptTwilioCredential(credential.encrypted, {
			organizationId: context.organizationId,
			credentialId: credential.id,
			subaccountSid: context.subaccountSid,
			purpose: 'auth_token'
		});
		return { token, retireAfter: credential.retireAfter };
	} catch {
		return null;
	}
}

/** Loads and orders every Auth Token candidate for one subaccount, ready for `validateTwilioSignature`.
 *  Shared by every Twilio webhook route so each one applies the same rotation-overlap rule. */
export async function collectTwilioValidationTokens(
	store: TwilioProvisioningStore,
	accountId: string,
	context: { organizationId: string; subaccountSid: string }
): Promise<string[]> {
	const [current, staged, prior] = await Promise.all([
		store.getCredential({ accountId, purpose: 'auth_token', lifecycleState: 'current' }),
		store.getCredential({ accountId, purpose: 'auth_token', lifecycleState: 'staged' }),
		store.getCredential({ accountId, purpose: 'auth_token', lifecycleState: 'prior' })
	]);
	return orderedValidationTokens(
		{
			current: toTokenCandidate(current, context),
			staged: toTokenCandidate(staged, context),
			prior: toTokenCandidate(prior, context)
		},
		new Date()
	);
}

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

// --- Stage 5B: signed inbound messages -----------------------------------------------------------------

/** The inbound-message URL exactly as our provisioning registers it with Twilio. Same byte-for-byte
 *  discipline as the status URL: Twilio signs over this string, never the incoming request URL. */
export function getTwilioInboundWebhookUrl(): string {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin)
		throw new Error('APP_URL must be set before Twilio inbound messages can be handled.');
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	return `${origin.origin}/api/webhooks/twilio/inbound`;
}

const inboundParamsSchema = z
	.object({
		MessageSid: z
			.string()
			.trim()
			.regex(/^(SM|MM)[0-9A-Fa-f]{32}$/),
		AccountSid: z
			.string()
			.trim()
			.regex(/^AC[0-9A-Fa-f]{32}$/),
		From: z.string().trim().min(1).max(40),
		To: z.string().trim().min(1).max(40),
		Body: z.string().max(1600).default(''),
		NumMedia: z
			.string()
			.trim()
			.regex(/^\d+$/)
			.default('0')
			.transform((value) => Number.parseInt(value, 10)),
		// Present only when Advanced Opt-Out is configured on the Messaging Service; Twilio has already sent its
		// own keyword confirmation in that case, so the route must never send another.
		OptOutType: z.enum(['STOP', 'START', 'HELP']).optional()
	})
	.passthrough();

export type TwilioInboundParams = {
	MessageSid: string;
	AccountSid: string;
	From: string;
	To: string;
	Body: string;
	NumMedia: number;
	OptOutType?: 'STOP' | 'START' | 'HELP';
};

/** Parse the identifying fields of an inbound message callback. Returns null when the shape is not a
 *  Twilio inbound message at all; the full param set is still what gets signature-checked. */
export function parseTwilioInboundParams(
	params: Record<string, string>
): TwilioInboundParams | null {
	const parsed = inboundParamsSchema.safeParse(params);
	if (!parsed.success) return null;
	return {
		MessageSid: parsed.data.MessageSid,
		AccountSid: parsed.data.AccountSid,
		From: parsed.data.From,
		To: parsed.data.To,
		Body: parsed.data.Body,
		NumMedia: parsed.data.NumMedia,
		OptOutType: parsed.data.OptOutType
	};
}

export type SmsConsentEventKind = 'opt_in' | 'opt_out' | 'help_requested';

/** Twilio's own default STOP-family keyword list (twilio.com/docs/messaging/tutorials/advanced-opt-out),
 *  matched case-insensitively against the *exact* message body -- the same rule Twilio itself applies.
 *  Advanced Opt-Out is not yet provisioned on our Messaging Service (no `OptOutType` will arrive), but
 *  Twilio's plain-number STOP-family handling is on by default for every long code and toll-free sender
 *  regardless, so a customer's opt-out must still be recognized and recorded from the body alone. */
const DEFAULT_OPT_OUT_KEYWORDS = new Set([
	'stop',
	'stopall',
	'unsubscribe',
	'cancel',
	'end',
	'quit'
]);
const DEFAULT_OPT_IN_KEYWORDS = new Set(['start', 'yes', 'unstop']);
const DEFAULT_HELP_KEYWORDS = new Set(['help', 'info']);

/** Classify an inbound message as a consent keyword event, preferring Twilio's own `OptOutType`
 *  classification (Advanced Opt-Out, when configured) and falling back to Twilio's documented default
 *  keyword list otherwise. Returns null for an ordinary reply. */
export function classifySmsConsentEvent(params: TwilioInboundParams): {
	kind: SmsConsentEventKind;
	confirmedByProvider: boolean;
} | null {
	if (params.OptOutType === 'STOP') return { kind: 'opt_out', confirmedByProvider: true };
	if (params.OptOutType === 'START') return { kind: 'opt_in', confirmedByProvider: true };
	if (params.OptOutType === 'HELP') return { kind: 'help_requested', confirmedByProvider: true };

	const body = params.Body.trim().toLowerCase();
	if (DEFAULT_OPT_OUT_KEYWORDS.has(body)) return { kind: 'opt_out', confirmedByProvider: false };
	if (DEFAULT_OPT_IN_KEYWORDS.has(body)) return { kind: 'opt_in', confirmedByProvider: false };
	if (DEFAULT_HELP_KEYWORDS.has(body))
		return { kind: 'help_requested', confirmedByProvider: false };
	return null;
}
