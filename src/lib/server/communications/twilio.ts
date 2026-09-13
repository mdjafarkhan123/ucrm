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
//   - the PLATFORM key (deployment secret) creates and lists subaccounts;
//   - each subaccount's AUTH TOKEN performs privileged one-time setup (mint the first Restricted key, create the
//     Messaging Service) and token lifecycle -- this is the only credential that can bootstrap a fresh
//     subaccount, since a subaccount has no API key until we create one;
//   - the subaccount RESTRICTED KEY is reserved for the ordinary runtime send path (Stage 4), never for setup.
//
// Twilio returns each secret (subaccount Auth Token, API-key secret) exactly once, at creation. The saga
// encrypts and stores it immediately; this adapter returns it to the saga and never logs it.

const SUBACCOUNT_SID = /^AC[0-9A-Fa-f]{32}$/;
const API_KEY_SID = /^SK[0-9A-Fa-f]{32}$/;
const MESSAGING_SERVICE_SID = /^MG[0-9A-Fa-f]{32}$/;

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
	createRestrictedApiKey(input: CreateRestrictedApiKeyInput): Promise<CreatedRestrictedApiKey>;
	listApiKeys(input: SubaccountAuthInput): Promise<FoundApiKey[]>;
	deleteApiKey(input: SubaccountAuthInput & { keySid: string }): Promise<void>;
	createMessagingService(input: CreateMessagingServiceInput): Promise<CreatedMessagingService>;
	findMessagingService(
		input: SubaccountAuthInput & { friendlyName: string }
	): Promise<CreatedMessagingService | null>;
	createSecondaryAuthToken(input: {
		subaccountSid: string;
		currentAuthToken: string;
	}): Promise<{ secondaryAuthToken: string }>;
	deleteSecondaryAuthToken(input: { subaccountSid: string; currentAuthToken: string }): Promise<void>;
	promoteAuthToken(input: { subaccountSid: string; secondaryAuthToken: string }): Promise<void>;
	verifyAuthToken(input: { subaccountSid: string; authToken: string }): Promise<boolean>;
	verifyRestrictedApiKey(input: {
		subaccountSid: string;
		keySid: string;
		keySecret: string;
	}): Promise<boolean>;
};

// The Restricted API key our runtime send path (Stage 4) authenticates with. We grant only the Messaging
// capabilities UCRM actually calls. Twilio expresses Restricted-key permissions as "allow assertions"; the
// exact assertion identifiers are published only in Twilio's downloadable Messaging permissions PDF and must
// be confirmed there and proven with a live restricted-key test in staging before real provisioning (Stage 2B
// gate). This constant records the intended least-privilege capability set so review and the staging test have
// a single source of truth; it is not yet exercised against Twilio because provisioning runs against a mock.
export const RESTRICTED_KEY_MESSAGING_CAPABILITIES = [
	'messaging.send', // POST .../Messages -- send an SMS/MMS
	'messaging.read', // GET .../Messages/{sid} -- read delivery status
	'messaging.service.read' // GET messaging/v1/Services/{sid} -- confirm the sending service
] as const;

export type RestrictedKeyCapability = (typeof RESTRICTED_KEY_MESSAGING_CAPABILITIES)[number];
export type RestrictedKeyPolicy = { capabilities: readonly RestrictedKeyCapability[] };

export function buildRestrictedKeyMessagingPolicy(): RestrictedKeyPolicy {
	return { capabilities: RESTRICTED_KEY_MESSAGING_CAPABILITIES };
}

const platformEnvSchema = z.object({
	TWILIO_ACCOUNT_SID: z.string().trim().regex(SUBACCOUNT_SID),
	TWILIO_PROVISIONING_KEY_SID: z.string().trim().regex(API_KEY_SID),
	TWILIO_PROVISIONING_KEY_SECRET: z.string().trim().min(1)
});

export type TwilioPlatformEnv = z.infer<typeof platformEnvSchema>;

/**
 * The platform-level provisioning credential. A main-account Restricted/Standard API key (SID + secret) kept
 * only in deployment secrets, used to create and list subaccounts. Validated lazily so the app boots without
 * SMS configured.
 */
export function getTwilioPlatformEnv(): TwilioPlatformEnv {
	const result = platformEnvSchema.safeParse({
		TWILIO_ACCOUNT_SID: env.TWILIO_ACCOUNT_SID,
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
		throw new TwilioProvisioningError('Twilio did not return a result.', null, 'twilio_unknown', true);
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
	const subaccountAuth = (sid: string, token: string) => basicAuthHeader(sid, token);

	return {
		async createSubaccount(friendlyName) {
			const { body } = await twilioRequest({
				base: TWILIO_API_BASE,
				path: '/2010-04-01/Accounts.json',
				method: 'POST',
				auth: platformAuth,
				form: { FriendlyName: friendlyName }
			});
			return {
				subaccountSid: requireSid(readString(body, 'sid'), SUBACCOUNT_SID, 'twilio_bad_subaccount_sid'),
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
				body && typeof body === 'object' && Array.isArray((body as Record<string, unknown>).accounts)
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
				body && typeof body === 'object' && Array.isArray((body as Record<string, unknown>).services)
					? ((body as Record<string, unknown>).services as unknown[])
					: [];
			const match = services.find((service) => readString(service, 'friendly_name') === friendlyName);
			if (!match) return null;
			return {
				messagingServiceSid: requireSid(
					readString(match, 'sid'),
					MESSAGING_SERVICE_SID,
					'twilio_bad_messaging_service_sid'
				)
			};
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
