import { env } from '$env/dynamic/private';
import { z } from 'zod';

// Twilio provisioning adapter (A2 Stage 2B). This is the only module that talks to Twilio's provisioning and
// credential-lifecycle endpoints. It is a thin, injectable boundary: the provisioning saga depends on the
// TwilioProvisioningClient interface, so unit tests drive the saga against a fake and no test ever contacts
// Twilio. Every method verified against current Twilio docs (2026):
//   - Subaccounts:            POST/GET https://api.twilio.com/2010-04-01/Accounts.json
//   - Restricted API keys:    POST https://iam.twilio.com/v1/Keys (KeyType=restricted + Policy)
//   - API key list/delete:    GET/DELETE .../2010-04-01/Accounts/{sid}/Keys[/{keySid}].json
//   - Messaging Service:      POST/GET https://messaging.twilio.com/v1/Services  (Services REST API: Public Beta)
//   - Auth Token lifecycle:   https://accounts.twilio.com/v1/AuthTokens/Secondary and .../Promote
//
// Least-privilege credential split (docs/research/communications-stage2-security.md):
//   - the platform MAIN API KEY (deployment secret) lists subaccounts and performs subaccount-scoped reads that
//     do not return a subaccount's own Auth Token;
//   - the platform MASTER Account SID + AUTH TOKEN (deployment secret) is used ONLY for the two operations that
//     must read back a fresh subaccount's plaintext Auth Token -- creating a subaccount and fetching one by SID.
//     Verified live (2026-09-14) and confirmed against Twilio docs: Twilio returns a subaccount's `auth_token`
//     only to a request authenticated with the parent's real Account SID + Auth Token, never to any API key.
//     This is the standard Twilio ISV pattern for a Standard-edition account; the API-key-only alternative
//     (Public Key Client Validation) is restricted to Enterprise/Security editions and is out of scope for launch.
//   - each subaccount's AUTH TOKEN performs privileged one-time setup (mint the first Restricted key, create the
//     Messaging Service) and token lifecycle -- this is the only credential that can bootstrap a fresh
//     subaccount, since a subaccount has no API key until we create one;
//   - the subaccount RESTRICTED KEY is reserved for the ordinary runtime send path (Stage 4), never for setup.
//
// The master Auth Token is the most sensitive secret in the system. It lives only in deployment secrets, never
// in Postgres, a Docker image, a log, an error, or any browser payload, and never leaves this module.
//
// Twilio returns each secret (subaccount Auth Token, API-key secret) exactly once, at creation. The saga
// encrypts and stores it immediately; this adapter returns it to the saga and never logs it.

const SUBACCOUNT_SID = /^AC[0-9A-Fa-f]{32}$/;
const API_KEY_SID = /^SK[0-9A-Fa-f]{32}$/;
const MESSAGING_SERVICE_SID = /^MG[0-9A-Fa-f]{32}$/;
const PHONE_NUMBER_SID = /^PN[0-9A-Fa-f]{32}$/;

const TWILIO_API_BASE = 'https://api.twilio.com';
const TWILIO_IAM_BASE = 'https://iam.twilio.com';
const TWILIO_MESSAGING_BASE = 'https://messaging.twilio.com';
const TWILIO_ACCOUNTS_BASE = 'https://accounts.twilio.com';

// A hung provisioning call must not strand the operation. Bounded well under any owner-request budget; an
// aborted call surfaces as an ambiguous outcome the saga can safely re-run (reconciliation is idempotent).
const PROVIDER_TIMEOUT_MS = 15_000;

export class TwilioProvisioningError extends Error {
	constructor(
		message: string,
		public readonly status: number | null,
		public readonly code: string,
		// retryable: an unknown/ambiguous provider outcome (network, timeout, 5xx, 429) the saga may safely
		// re-run because every step reconciles known SIDs before creating. A definite 4xx conflict is NOT
		// retryable -- it needs an operator decision.
		public readonly retryable: boolean,
		public readonly providerCode: string | null = null
	) {
		super(message);
		this.name = 'TwilioProvisioningError';
	}
}

export type CreatedSubaccount = { subaccountSid: string; authToken: string; status: string };
export type FoundSubaccount = { subaccountSid: string; status: string };
export type CreatedRestrictedApiKey = { keySid: string; secret: string };
export type FoundApiKey = { keySid: string; friendlyName: string | null };
export type CreatedMessagingService = { messagingServiceSid: string };

export type AddPhoneNumberToMessagingServiceInput = SubaccountAuthInput & {
	messagingServiceSid: string;
	phoneNumberSid: string;
};

export type CreateRestrictedApiKeyInput = {
	subaccountSid: string;
	subaccountAuthToken: string;
	friendlyName: string;
	policy: RestrictedKeyPolicy;
};

export type SubaccountAuthInput = { subaccountSid: string; subaccountAuthToken: string };

export type CreateMessagingServiceInput = SubaccountAuthInput & {
	friendlyName: string;
	inboundRequestUrl: string;
	statusCallback: string;
};

/**
 * The provisioning and credential-lifecycle operations the saga needs. Kept semantic and secret-in/secret-out
 * so the saga can inject a fake in tests and the real adapter owns all auth and transport concerns.
 */
export type TwilioProvisioningClient = {
	createSubaccount(friendlyName: string): Promise<CreatedSubaccount>;
	findSubaccount(friendlyName: string): Promise<FoundSubaccount | null>;
	/** Fetch a subaccount's current Auth Token with the platform credential, regardless of who created it. Used
	 *  to adopt a subaccount that was set up outside the saga (e.g. directly in the Twilio console). */
	fetchSubaccountBySid(subaccountSid: string): Promise<CreatedSubaccount>;
	createRestrictedApiKey(input: CreateRestrictedApiKeyInput): Promise<CreatedRestrictedApiKey>;
	listApiKeys(input: SubaccountAuthInput): Promise<FoundApiKey[]>;
	deleteApiKey(input: SubaccountAuthInput & { keySid: string }): Promise<void>;
	createMessagingService(input: CreateMessagingServiceInput): Promise<CreatedMessagingService>;
	findMessagingService(
		input: SubaccountAuthInput & { friendlyName: string }
	): Promise<CreatedMessagingService | null>;
	/** Add a phone number already owned by the subaccount to a Messaging Service's sender pool. Idempotent:
	 *  Twilio's "already in this Service" rejection (error 21710) is treated as success. */
	addPhoneNumberToMessagingService(
		input: AddPhoneNumberToMessagingServiceInput
	): Promise<{ phoneNumberSid: string }>;
	createSecondaryAuthToken(input: {
		subaccountSid: string;
		currentAuthToken: string;
	}): Promise<{ secondaryAuthToken: string }>;
	deleteSecondaryAuthToken(input: {
		subaccountSid: string;
		currentAuthToken: string;
	}): Promise<void>;
	promoteAuthToken(input: { subaccountSid: string; secondaryAuthToken: string }): Promise<void>;
	verifyAuthToken(input: { subaccountSid: string; authToken: string }): Promise<boolean>;
	verifyRestrictedApiKey(input: {
		subaccountSid: string;
		keySid: string;
		keySecret: string;
	}): Promise<boolean>;
};

// The Restricted API key our runtime send path (Stage 4) authenticates with. We grant only the Messaging
// assertions UCRM actually calls. Confirmed 2026-09-13 against Twilio's downloadable Messaging permissions
// PDF (https://www.twilio.com/docs/iam/api-keys/restricted-api-keys) and proven with a live restricted-key
// create during Raad LTD subaccount adoption -- these are the exact `allow` assertion strings Twilio expects,
// not a guess.
export const RESTRICTED_KEY_MESSAGING_CAPABILITIES = [
	'/twilio/messaging/messages/create', // POST .../Messages -- send an SMS/MMS
	'/twilio/messaging/messages/read', // GET .../Messages/{sid} -- read delivery status
	'/twilio/messaging/services/read', // GET messaging/v1/Services/{sid} -- confirm the sending service
	// GET .../Usage/Records (and its Daily/Monthly subresources) -- Stage 8-2's usage-window reconciliation.
	// Confirmed against Twilio's own Restricted API Keys Permissions PDF (Usage Records table, 2026-09-15).
	'/twilio/billing/usage/read',
	// GET .../Messages/{sid}/Media/{sid} -- Stage 6D-1's inbound MMS download. Confirmed against Twilio's own
	// Restricted API Keys Permissions PDF (Messaging Permissions table, `messages.media/read`, 2026-09-16).
	'/twilio/messaging/messages.media/read'
] as const;

export type RestrictedKeyCapability = (typeof RESTRICTED_KEY_MESSAGING_CAPABILITIES)[number];
export type RestrictedKeyPolicy = { allow: readonly RestrictedKeyCapability[] };

export function buildRestrictedKeyMessagingPolicy(): RestrictedKeyPolicy {
	return { allow: RESTRICTED_KEY_MESSAGING_CAPABILITIES };
}

// -----------------------------------------------------------------------------------------------------------------
// Runtime SMS submission (A2 Stage 4B). The single call the bounded SMS worker makes per claim: one POST to the
// subaccount's Messages endpoint, authenticated with that subaccount's least-privilege Restricted API key. There
// are no hidden retries -- one HTTP request, one recorded outcome -- because a database-owned outbox, not the
// client, owns retry timing. The frozen sender number and the organization's Messaging Service are both supplied
// so the service governs compliance and status callbacks while the specific chosen number is the sender.
//
// The outcome vocabulary matches the finalize command exactly:
//   - submitted           Twilio accepted the message (2xx with a Message SID). Delivery is later, via webhooks.
//   - retry               a PROVEN pre-submission transient failure (429 rate limit, 5xx). The message was not
//                         accepted, so re-sending later is safe.
//   - cancelled           a definite rejection (a 4xx other than 429, e.g. an invalid number or an opted-out
//                         recipient). Re-sending would fail the same way; the held funds are released.
//   - submission_unknown  the outcome is genuinely unknown (network failure or timeout after the request left
//                         UCRM, or a 2xx without a Message SID). Twilio may have accepted it, so it is quarantined
//                         for reconciliation and never resent.

const SMS_SEND_TIMEOUT_MS = 10_000;
const MESSAGE_SID = /^(SM|MM)[0-9A-Fa-f]{32}$/;

export type TwilioSmsSubmissionOutcome = 'retry' | 'cancelled' | 'submission_unknown';

export class TwilioSmsSubmissionError extends Error {
	constructor(
		message: string,
		public readonly outcome: TwilioSmsSubmissionOutcome,
		public readonly code: string,
		// Twilio's own numeric error code (e.g. 21610 opted-out, 21211 invalid To) when it returned one, for
		// correlation and reconciliation. Never the response body itself -- it can echo request content.
		public readonly providerCode: string | null = null
	) {
		super(message);
		this.name = 'TwilioSmsSubmissionError';
	}
}

export type SubmitTwilioSmsInput = {
	subaccountSid: string;
	messagingServiceSid: string;
	apiKeySid: string;
	apiKeySecret: string;
	from: string;
	to: string;
	body: string;
	// The frozen logical-send identity. Passed to Twilio as an idempotency-style tag for correlation only; the
	// database outbox is the real exactly-once boundary.
	deliveryIntentId: string;
	// Stage 6D-2: presigned inline URLs for the message's picture(s), one repeated MediaUrl field per
	// Twilio's own form-encoding for MMS. Undefined/empty sends a plain SMS, matching today's behavior.
	mediaUrls?: string[];
};

/**
 * Submit one SMS to Twilio. Resolves with the accepted Message SID, or throws a TwilioSmsSubmissionError whose
 * `outcome` tells the worker exactly how to finalize the claim. Makes exactly one request; never retries.
 */
export async function submitTwilioSms(
	input: SubmitTwilioSmsInput
): Promise<{ providerMessageId: string }> {
	const url = new URL(`/2010-04-01/Accounts/${input.subaccountSid}/Messages.json`, TWILIO_API_BASE);
	// API-key auth is Basic with the key SID as username and its secret as password, scoped to the subaccount by
	// the Account SID in the path.
	const auth = basicAuthHeader(input.apiKeySid, input.apiKeySecret);

	const params = new URLSearchParams({
		To: input.to,
		From: input.from,
		MessagingServiceSid: input.messagingServiceSid,
		Body: input.body
	});
	for (const mediaUrl of input.mediaUrls ?? []) {
		params.append('MediaUrl', mediaUrl);
	}

	let response: Response;
	try {
		response = await fetch(url, {
			method: 'POST',
			headers: {
				accept: 'application/json',
				authorization: auth,
				'content-type': 'application/x-www-form-urlencoded'
			},
			body: params.toString(),
			signal: AbortSignal.timeout(SMS_SEND_TIMEOUT_MS)
		}).catch(() => {
			throw new TwilioSmsSubmissionError(
				'Twilio did not return a submission outcome.',
				'submission_unknown',
				'twilio_network_unknown'
			);
		});
	} catch (error) {
		if (error instanceof TwilioSmsSubmissionError) throw error;
		throw new TwilioSmsSubmissionError(
			'Twilio did not return a submission outcome.',
			'submission_unknown',
			'twilio_network_unknown'
		);
	}

	let body: unknown = null;
	const text = await response.text().catch(() => '');
	if (text) {
		try {
			body = JSON.parse(text);
		} catch {
			body = null;
		}
	}

	if (!response.ok) {
		const providerCode =
			body &&
			typeof body === 'object' &&
			'code' in body &&
			typeof (body as { code: unknown }).code === 'number'
				? String((body as { code: number }).code)
				: null;
		// 429 (rate limit) and 5xx are proven pre-submission transients; every other 4xx is a definite rejection.
		const retryable = response.status === 429 || response.status >= 500;
		throw new TwilioSmsSubmissionError(
			`Twilio rejected the message with status ${response.status}.`,
			retryable ? 'retry' : 'cancelled',
			`twilio_http_${response.status}`,
			providerCode
		);
	}

	const providerMessageId = readString(body, 'sid');
	if (!providerMessageId || !MESSAGE_SID.test(providerMessageId)) {
		// A 2xx without a usable Message SID: Twilio may have accepted the message but we cannot correlate it, so
		// the safe outcome is unknown (hold + reconcile), never a blind resend.
		throw new TwilioSmsSubmissionError(
			'Twilio accepted the message without returning a usable identifier.',
			'submission_unknown',
			'twilio_missing_message_sid'
		);
	}
	return { providerMessageId };
}

export type TwilioMessagePriceLookup = {
	subaccountSid: string;
	messageSid: string;
	apiKeySid: string;
	apiKeySecret: string;
};

export type TwilioMessagePriceResult =
	| { available: true; priceMinor: number; priceCurrency: string; segmentCount: number }
	| { available: false };

/**
 * Fetch a sent message's actual billed price and segment count from Twilio, for Stage 8 price reconciliation.
 * Twilio's status callback never carries Price/PriceUnit -- it is only ever available by fetching the Message
 * resource, and only once Twilio has finished billing it (an undocumented delay). `available: false` on a
 * clean 2xx with no price yet is expected; the caller should retry later. Throws TwilioProvisioningError on a
 * genuine transport/HTTP failure (its `retryable` flag tells the caller whether to back off or give up).
 */
export async function fetchTwilioMessagePrice(
	input: TwilioMessagePriceLookup
): Promise<TwilioMessagePriceResult> {
	const { body } = await twilioRequest({
		base: TWILIO_API_BASE,
		path: `/2010-04-01/Accounts/${input.subaccountSid}/Messages/${input.messageSid}.json`,
		method: 'GET',
		auth: basicAuthHeader(input.apiKeySid, input.apiKeySecret)
	});

	const priceRaw = readString(body, 'price');
	const priceUnit = readString(body, 'price_unit');
	const segmentsRaw = readString(body, 'num_segments');
	if (!priceRaw || !priceUnit || !segmentsRaw) return { available: false };

	const priceMajor = Number(priceRaw);
	const segmentCount = Number(segmentsRaw);
	if (!Number.isFinite(priceMajor) || !Number.isInteger(segmentCount) || segmentCount < 1) {
		return { available: false };
	}

	// Twilio reports price as a negative decimal (its own cost, not ours); store the magnitude in minor units.
	return {
		available: true,
		priceMinor: Math.round(Math.abs(priceMajor) * 100),
		priceCurrency: priceUnit.toUpperCase(),
		segmentCount
	};
}

export type TwilioUsageRecordsLookup = {
	subaccountSid: string;
	category: string;
	startDate: string;
	endDate: string;
	apiKeySid: string;
	apiKeySecret: string;
};

export type TwilioUsageRecord = {
	usageDate: string;
	messageCount: number;
	priceMinor: number;
	priceCurrency: string;
};

// A single window is already bounded by the caller (Stage 8-2's max-window-days cap); this is a hard safety
// valve against an unbounded page-follow loop, not the primary bound.
const MAX_USAGE_RECORD_PAGES = 10;

/**
 * Fetch one account's daily SMS usage totals for Stage 8-2's usage-window reconciliation. Follows
 * `next_page_uri` for a wide window; a row missing any of the fields this needs is skipped rather than thrown,
 * since a malformed usage row should not abort the whole day's comparison.
 */
export async function fetchTwilioUsageRecords(
	input: TwilioUsageRecordsLookup
): Promise<TwilioUsageRecord[]> {
	const auth = basicAuthHeader(input.apiKeySid, input.apiKeySecret);
	const records: TwilioUsageRecord[] = [];

	let path = `/2010-04-01/Accounts/${input.subaccountSid}/Usage/Records/Daily.json`;
	let query: Record<string, string> | undefined = {
		Category: input.category,
		StartDate: input.startDate,
		EndDate: input.endDate,
		PageSize: '1000'
	};

	for (let page = 0; page < MAX_USAGE_RECORD_PAGES; page++) {
		const { body } = await twilioRequest({
			base: TWILIO_API_BASE,
			path,
			method: 'GET',
			auth,
			query
		});

		const rows =
			body &&
			typeof body === 'object' &&
			Array.isArray((body as { usage_records?: unknown }).usage_records)
				? (body as { usage_records: unknown[] }).usage_records
				: [];

		for (const row of rows) {
			const usageDate = readString(row, 'start_date');
			const priceRaw = readString(row, 'price');
			const priceUnit = readString(row, 'price_unit');
			const countRaw = readString(row, 'count');
			if (!usageDate || !priceRaw || !priceUnit || !countRaw) continue;

			const priceMajor = Number(priceRaw);
			const count = Number(countRaw);
			if (!Number.isFinite(priceMajor) || !Number.isFinite(count)) continue;

			records.push({
				usageDate,
				messageCount: Math.round(count),
				priceMinor: Math.round(Math.abs(priceMajor) * 100),
				priceCurrency: priceUnit.toUpperCase()
			});
		}

		const nextPageUri = body && typeof body === 'object' ? readString(body, 'next_page_uri') : null;
		if (!nextPageUri) break;
		path = nextPageUri;
		query = undefined; // next_page_uri already carries its own query string
	}

	return records;
}

const platformEnvSchema = z.object({
	TWILIO_ACCOUNT_SID: z.string().trim().regex(SUBACCOUNT_SID),
	// The master Account Auth Token. Required, and used only for the two operations that must read back a
	// subaccount's own Auth Token (createSubaccount, fetchSubaccountBySid); Twilio returns it to no other
	// credential. Kept out of Postgres, images, logs, and browser payloads.
	TWILIO_AUTH_TOKEN: z.string().trim().min(1),
	TWILIO_PROVISIONING_KEY_SID: z.string().trim().regex(API_KEY_SID),
	TWILIO_PROVISIONING_KEY_SECRET: z.string().trim().min(1)
});

export type TwilioPlatformEnv = z.infer<typeof platformEnvSchema>;

/**
 * The platform-level provisioning credentials, kept only in deployment secrets and validated lazily so the app
 * boots without SMS configured. Two secrets, each least-privilege for what it does:
 *   - a main-account API key (SID + secret) for listing subaccounts and subaccount-scoped reads;
 *   - the master Account SID + Auth Token, used only where Twilio will return a subaccount's plaintext Auth
 *     Token (subaccount create and fetch-by-SID) and nowhere else.
 */
export function getTwilioPlatformEnv(): TwilioPlatformEnv {
	const result = platformEnvSchema.safeParse({
		TWILIO_ACCOUNT_SID: env.TWILIO_ACCOUNT_SID,
		TWILIO_AUTH_TOKEN: env.TWILIO_AUTH_TOKEN,
		TWILIO_PROVISIONING_KEY_SID: env.TWILIO_PROVISIONING_KEY_SID,
		TWILIO_PROVISIONING_KEY_SECRET: env.TWILIO_PROVISIONING_KEY_SECRET
	});
	if (!result.success) {
		throw new Error('Twilio provisioning credentials are not configured.');
	}
	return result.data;
}

function basicAuthHeader(user: string, password: string): string {
	return `Basic ${Buffer.from(`${user}:${password}`, 'utf8').toString('base64')}`;
}

type TwilioRequest = {
	base: string;
	path: string;
	method: 'GET' | 'POST' | 'DELETE';
	auth: string;
	form?: Record<string, string>;
	query?: Record<string, string>;
};

async function twilioRequest(request: TwilioRequest): Promise<{ status: number; body: unknown }> {
	const url = new URL(request.path, request.base);
	for (const [key, value] of Object.entries(request.query ?? {})) {
		url.searchParams.set(key, value);
	}

	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS);
	let response: Response;
	try {
		response = await fetch(url, {
			method: request.method,
			headers: {
				accept: 'application/json',
				authorization: request.auth,
				...(request.form ? { 'content-type': 'application/x-www-form-urlencoded' } : {})
			},
			body: request.form ? new URLSearchParams(request.form).toString() : undefined,
			signal: controller.signal
		});
	} catch {
		// Network failure or timeout: the provider outcome is unknown, so it is safe to re-run (reconciliation
		// will adopt anything that was actually created). Never surface the underlying error text -- it can echo
		// request headers, including credentials.
		throw new TwilioProvisioningError(
			'Twilio did not return a result.',
			null,
			'twilio_unknown',
			true
		);
	} finally {
		clearTimeout(timeout);
	}

	let body: unknown = null;
	const text = await response.text().catch(() => '');
	if (text) {
		try {
			body = JSON.parse(text);
		} catch {
			body = null;
		}
	}

	if (!response.ok) {
		const providerCode =
			body && typeof body === 'object' && 'code' in body && typeof body.code === 'number'
				? String(body.code)
				: null;
		// 429 and 5xx are transient; 4xx is a definite rejection. We never include the body text in the message
		// to avoid leaking any echoed credential or PII.
		const retryable = response.status === 429 || response.status >= 500;
		throw new TwilioProvisioningError(
			`Twilio rejected a provisioning request (status ${response.status}).`,
			response.status,
			'twilio_rejected',
			retryable,
			providerCode
		);
	}

	return { status: response.status, body };
}

function readString(body: unknown, key: string): string | null {
	if (body && typeof body === 'object' && key in body) {
		const value = (body as Record<string, unknown>)[key];
		return typeof value === 'string' ? value : null;
	}
	return null;
}

function requireSid(value: string | null, pattern: RegExp, code: string): string {
	if (!value || !pattern.test(value)) {
		throw new TwilioProvisioningError(
			'Twilio returned an unexpected identifier.',
			null,
			code,
			false
		);
	}
	return value;
}

/**
 * The live Twilio adapter. Holds the platform credential; subaccount secrets are passed in per call by the
 * saga (which decrypts them just-in-time) and are never retained here.
 */
export function createTwilioProvisioningClient(
	platform: TwilioPlatformEnv = getTwilioPlatformEnv()
): TwilioProvisioningClient {
	const platformAuth = basicAuthHeader(
		platform.TWILIO_PROVISIONING_KEY_SID,
		platform.TWILIO_PROVISIONING_KEY_SECRET
	);
	// The master credential. Reserved for the two calls that must read back a subaccount's own Auth Token, which
	// Twilio returns to no API key. Not used anywhere else in this adapter.
	const masterAuth = basicAuthHeader(platform.TWILIO_ACCOUNT_SID, platform.TWILIO_AUTH_TOKEN);
	const subaccountAuth = (sid: string, token: string) => basicAuthHeader(sid, token);

	return {
		async createSubaccount(friendlyName) {
			const { body } = await twilioRequest({
				base: TWILIO_API_BASE,
				path: '/2010-04-01/Accounts.json',
				method: 'POST',
				// Master credential: the create response is the only time Twilio returns the new subaccount's
				// Auth Token, and it returns it to no API key.
				auth: masterAuth,
				form: { FriendlyName: friendlyName }
			});
			return {
				subaccountSid: requireSid(
					readString(body, 'sid'),
					SUBACCOUNT_SID,
					'twilio_bad_subaccount_sid'
				),
				authToken: requireSid(readString(body, 'auth_token'), /^.+$/, 'twilio_missing_auth_token'),
				status: readString(body, 'status') ?? 'active'
			};
		},

		async findSubaccount(friendlyName) {
			const { body } = await twilioRequest({
				base: TWILIO_API_BASE,
				path: '/2010-04-01/Accounts.json',
				method: 'GET',
				auth: platformAuth,
				query: { FriendlyName: friendlyName, PageSize: '2' }
			});
			const accounts =
				body &&
				typeof body === 'object' &&
				Array.isArray((body as Record<string, unknown>).accounts)
					? ((body as Record<string, unknown>).accounts as unknown[])
					: [];
			if (accounts.length === 0) return null;
			if (accounts.length > 1) {
				// Two subaccounts share our deterministic name: an ambiguous state we must not resolve by guessing.
				throw new TwilioProvisioningError(
					'Multiple Twilio subaccounts share this organization name.',
					null,
					'twilio_ambiguous_subaccount',
					false
				);
			}
			const sid = readString(accounts[0], 'sid');
			return {
				subaccountSid: requireSid(sid, SUBACCOUNT_SID, 'twilio_bad_subaccount_sid'),
				status: readString(accounts[0], 'status') ?? 'active'
			};
		},

		async fetchSubaccountBySid(subaccountSid) {
			const { body } = await twilioRequest({
				base: TWILIO_API_BASE,
				path: `/2010-04-01/Accounts/${subaccountSid}.json`,
				method: 'GET',
				// Master credential: reading a subaccount by SID returns its Auth Token only to the parent's real
				// Account SID + Auth Token, never to an API key.
				auth: masterAuth
			});
			return {
				subaccountSid: requireSid(
					readString(body, 'sid'),
					SUBACCOUNT_SID,
					'twilio_bad_subaccount_sid'
				),
				authToken: requireSid(readString(body, 'auth_token'), /^.+$/, 'twilio_missing_auth_token'),
				status: readString(body, 'status') ?? 'active'
			};
		},

		async createRestrictedApiKey({ subaccountSid, subaccountAuthToken, friendlyName, policy }) {
			const { body } = await twilioRequest({
				base: TWILIO_IAM_BASE,
				path: '/v1/Keys',
				method: 'POST',
				auth: subaccountAuth(subaccountSid, subaccountAuthToken),
				form: {
					AccountSid: subaccountSid,
					FriendlyName: friendlyName,
					KeyType: 'restricted',
					Policy: JSON.stringify(policy)
				}
			});
			return {
				keySid: requireSid(readString(body, 'sid'), API_KEY_SID, 'twilio_bad_key_sid'),
				secret: requireSid(readString(body, 'secret'), /^.+$/, 'twilio_missing_key_secret')
			};
		},

		async listApiKeys({ subaccountSid, subaccountAuthToken }) {
			const { body } = await twilioRequest({
				base: TWILIO_API_BASE,
				path: `/2010-04-01/Accounts/${subaccountSid}/Keys.json`,
				method: 'GET',
				auth: subaccountAuth(subaccountSid, subaccountAuthToken),
				query: { PageSize: '100' }
			});
			const keys =
				body && typeof body === 'object' && Array.isArray((body as Record<string, unknown>).keys)
					? ((body as Record<string, unknown>).keys as unknown[])
					: [];
			return keys
				.map((key) => ({
					keySid: readString(key, 'sid') ?? '',
					friendlyName: readString(key, 'friendly_name')
				}))
				.filter((key) => API_KEY_SID.test(key.keySid));
		},

		async deleteApiKey({ subaccountSid, subaccountAuthToken, keySid }) {
			await twilioRequest({
				base: TWILIO_API_BASE,
				path: `/2010-04-01/Accounts/${subaccountSid}/Keys/${keySid}.json`,
				method: 'DELETE',
				auth: subaccountAuth(subaccountSid, subaccountAuthToken)
			});
		},

		async createMessagingService({
			subaccountSid,
			subaccountAuthToken,
			friendlyName,
			inboundRequestUrl,
			statusCallback
		}) {
			const { body } = await twilioRequest({
				base: TWILIO_MESSAGING_BASE,
				path: '/v1/Services',
				method: 'POST',
				auth: subaccountAuth(subaccountSid, subaccountAuthToken),
				form: {
					FriendlyName: friendlyName,
					InboundRequestUrl: inboundRequestUrl,
					StatusCallback: statusCallback
				}
			});
			return {
				messagingServiceSid: requireSid(
					readString(body, 'sid'),
					MESSAGING_SERVICE_SID,
					'twilio_bad_messaging_service_sid'
				)
			};
		},

		async findMessagingService({ subaccountSid, subaccountAuthToken, friendlyName }) {
			const { body } = await twilioRequest({
				base: TWILIO_MESSAGING_BASE,
				path: '/v1/Services',
				method: 'GET',
				auth: subaccountAuth(subaccountSid, subaccountAuthToken),
				query: { PageSize: '100' }
			});
			const services =
				body &&
				typeof body === 'object' &&
				Array.isArray((body as Record<string, unknown>).services)
					? ((body as Record<string, unknown>).services as unknown[])
					: [];
			const match = services.find(
				(service) => readString(service, 'friendly_name') === friendlyName
			);
			if (!match) return null;
			return {
				messagingServiceSid: requireSid(
					readString(match, 'sid'),
					MESSAGING_SERVICE_SID,
					'twilio_bad_messaging_service_sid'
				)
			};
		},

		async addPhoneNumberToMessagingService({
			subaccountSid,
			subaccountAuthToken,
			messagingServiceSid,
			phoneNumberSid
		}) {
			requireSid(phoneNumberSid, PHONE_NUMBER_SID, 'twilio_bad_phone_number_sid');
			try {
				await twilioRequest({
					base: TWILIO_MESSAGING_BASE,
					path: `/v1/Services/${messagingServiceSid}/PhoneNumbers`,
					method: 'POST',
					auth: subaccountAuth(subaccountSid, subaccountAuthToken),
					form: { PhoneNumberSid: phoneNumberSid }
				});
			} catch (error) {
				// 21710 "Phone Number Already Exists in Messaging Service" is not a failure -- the number is
				// already where we want it, so treat it the same as our other find-or-create steps.
				if (error instanceof TwilioProvisioningError && error.providerCode === '21710') {
					return { phoneNumberSid };
				}
				throw error;
			}
			return { phoneNumberSid };
		},

		async createSecondaryAuthToken({ subaccountSid, currentAuthToken }) {
			const { body } = await twilioRequest({
				base: TWILIO_ACCOUNTS_BASE,
				path: '/v1/AuthTokens/Secondary',
				method: 'POST',
				auth: subaccountAuth(subaccountSid, currentAuthToken),
				// Rotating across many subaccounts otherwise emails every owner/admin; suppress and communicate
				// through UCRM's own channels (Twilio's documented recommendation).
				form: { SuppressEmailNotification: 'true' }
			});
			return {
				secondaryAuthToken: requireSid(
					readString(body, 'secondary_auth_token'),
					/^.+$/,
					'twilio_missing_secondary_token'
				)
			};
		},

		async deleteSecondaryAuthToken({ subaccountSid, currentAuthToken }) {
			await twilioRequest({
				base: TWILIO_ACCOUNTS_BASE,
				path: '/v1/AuthTokens/Secondary',
				method: 'DELETE',
				auth: subaccountAuth(subaccountSid, currentAuthToken)
			});
		},

		async promoteAuthToken({ subaccountSid, secondaryAuthToken }) {
			// Authenticate with the token being promoted. After this returns, the old primary is permanently
			// dead at Twilio -- there is no provider-side overlap, only UCRM's local prior-token grace window.
			await twilioRequest({
				base: TWILIO_ACCOUNTS_BASE,
				path: '/v1/AuthTokens/Promote',
				method: 'POST',
				auth: subaccountAuth(subaccountSid, secondaryAuthToken)
			});
		},

		async verifyAuthToken({ subaccountSid, authToken }) {
			try {
				await twilioRequest({
					base: TWILIO_API_BASE,
					path: `/2010-04-01/Accounts/${subaccountSid}.json`,
					method: 'GET',
					auth: subaccountAuth(subaccountSid, authToken)
				});
				return true;
			} catch (error) {
				if (error instanceof TwilioProvisioningError && error.status === 401) return false;
				throw error;
			}
		},

		async verifyRestrictedApiKey({ subaccountSid, keySid, keySecret }) {
			// A cheap authenticated read the Messaging Restricted key is permitted to perform. The exact
			// permitted read is confirmed with the policy in staging (Stage 2B gate); a 401/403 means the newly
			// created key is not usable yet, so rotation must not cut over to it.
			try {
				await twilioRequest({
					base: TWILIO_MESSAGING_BASE,
					path: '/v1/Services',
					method: 'GET',
					auth: subaccountAuth(keySid, keySecret),
					query: { PageSize: '1' }
				});
				return true;
			} catch (error) {
				if (
					error instanceof TwilioProvisioningError &&
					(error.status === 401 || error.status === 403)
				) {
					return false;
				}
				throw error;
			}
		}
	};
}

// -----------------------------------------------------------------------------------------------------------------
// Stage 6D-1: inbound MMS media download. Twilio's inbound webhook gives only an authenticated MediaUrl per
// item, never the bytes themselves -- the worker fetches them separately, mirroring fetchTwilioMessagePrice's
// transport style but returning raw bytes instead of parsed JSON.

export class TwilioInboundMediaDownloadError extends Error {
	constructor(
		message: string,
		public readonly status: number | null
	) {
		super(message);
		this.name = 'TwilioInboundMediaDownloadError';
	}
}

const INBOUND_MEDIA_DOWNLOAD_TIMEOUT_MS = 15_000;

/**
 * Download one inbound MMS media item from Twilio's authenticated Media URL. `mediaUrl` comes from a
 * signature-validated webhook, but its host is still checked against api.twilio.com before ever being
 * fetched -- defense in depth against a corrupted or malicious value reaching this far. Basic-auth with the
 * organization's Restricted key (messages.media/read capability).
 */
export async function downloadTwilioInboundMedia(
	mediaUrl: string,
	credentials: { apiKeySid: string; apiKeySecret: string }
): Promise<Uint8Array> {
	let url: URL;
	try {
		url = new URL(mediaUrl);
	} catch {
		throw new TwilioInboundMediaDownloadError('Twilio returned an unusable media URL.', null);
	}
	if (url.protocol !== 'https:' || url.hostname !== 'api.twilio.com') {
		throw new TwilioInboundMediaDownloadError('The media URL host was not Twilio.', null);
	}

	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), INBOUND_MEDIA_DOWNLOAD_TIMEOUT_MS);
	let response: Response;
	try {
		response = await fetch(url, {
			headers: { authorization: basicAuthHeader(credentials.apiKeySid, credentials.apiKeySecret) },
			signal: controller.signal
		});
	} catch {
		throw new TwilioInboundMediaDownloadError('Twilio did not return the media download.', null);
	} finally {
		clearTimeout(timeout);
	}

	if (!response.ok) {
		throw new TwilioInboundMediaDownloadError(
			`Twilio rejected the media download with status ${response.status}.`,
			response.status
		);
	}

	return new Uint8Array(await response.arrayBuffer());
}
