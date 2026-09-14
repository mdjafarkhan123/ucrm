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
	'/twilio/messaging/services/read' // GET messaging/v1/Services/{sid} -- confirm the sending service
] as const;

export type RestrictedKeyCapability = (typeof RESTRICTED_KEY_MESSAGING_CAPABILITIES)[number];
export type RestrictedKeyPolicy = { allow: readonly RestrictedKeyCapability[] };

export function buildRestrictedKeyMessagingPolicy(): RestrictedKeyPolicy {
	return { allow: RESTRICTED_KEY_MESSAGING_CAPABILITIES };
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
