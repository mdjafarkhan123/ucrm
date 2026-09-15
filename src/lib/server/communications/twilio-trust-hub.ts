import { getTwilioPlatformEnv, type TwilioPlatformEnv } from './twilio';

// Twilio Trust Hub / A2P 10DLC adapter (A2 Stage 9B). The only module that talks to Twilio's ISV registration
// endpoints. Verified against Twilio's current docs (2026) -- specifically the "A2P 10DLC - Standard and
// Low-Volume Standard Brand Onboarding Guide for ISVs"
// (docs/messaging/compliance/a2p-10dlc/onboarding-isv-api) -- not guessed:
//   - Customer Profile, End Users, Supporting Documents, Entity Assignments, Evaluations, Trust Products:
//     https://trusthub.twilio.com/v1/...
//   - Address:                https://api.twilio.com/2010-04-01/Accounts/{AccountSid}/Addresses.json (the
//     legacy 2010 resource, NOT a Trust Hub endpoint -- it is wrapped by a `customer_profile_address`
//     SupportingDocument before it can be attached to a profile)
//   - Brand Registration:      https://messaging.twilio.com/v1/a2p/BrandRegistrations
//
// Authenticated with the platform's main-account Restricted API key (TWILIO_PROVISIONING_KEY_SID/SECRET), the
// same least-privilege credential Stage 2B uses for subaccount-scoped reads -- Trust Hub and Brand resources
// belong to the platform's own (parent) account, never a contractor's subaccount, and none of these calls need
// to read back a subaccount's plaintext Auth Token, so the master Account SID + Auth Token is not used here.
//
// Twilio's own guide: "rate limit all API requests for Brand and Campaign registration to one request per
// second" -- the saga (trust-hub-submission.ts), not this adapter, owns that pacing since it is the caller
// that knows the full step sequence.
//
// No sandbox exists for CustomerProfiles/EndUsers/SupportingDocuments/Evaluations/EntityAssignments/
// TrustProducts (Twilio's test-credential system covers only phone numbers, Messages, Calls and Lookup) --
// every call here is real when it runs. Stage 9B builds and unit-tests this adapter against a fake HTTP layer;
// it is never invoked against live Twilio until a real registered business exists (see Stage 9 roadmap note).

const CUSTOMER_PROFILE_SID = /^BU[0-9A-Fa-f]{32}$/;
const TRUST_PRODUCT_SID = /^BU[0-9A-Fa-f]{32}$/; // Twilio reuses the BU prefix for TrustProducts.
const END_USER_SID = /^IT[0-9A-Fa-f]{32}$/;
const ADDRESS_SID = /^AD[0-9A-Fa-f]{32}$/;
const SUPPORTING_DOCUMENT_SID = /^RD[0-9A-Fa-f]{32}$/;
const EVALUATION_SID = /^EL[0-9A-Fa-f]{32}$/;
const BRAND_REGISTRATION_SID = /^BN[0-9A-Fa-f]{32}$/;
const CAMPAIGN_SID = /^QE[0-9A-Fa-f]{32}$/;
// Entity assignments and Trust Product entity assignments observed with an RA prefix; not load-bearing for any
// ledger cross-reference (assignments are not one of the tracked resource roles), so validated loosely.
const ASSIGNMENT_SID = /^[A-Z]{2}[0-9A-Fa-f]{32}$/;

const TRUSTHUB_BASE = 'https://trusthub.twilio.com';
const MESSAGING_BASE = 'https://messaging.twilio.com';
const TWILIO_API_BASE = 'https://api.twilio.com';

// Fixed per Twilio's ISV onboarding guide, which explicitly instructs not to change these: "the policy_sid must
// be..." (Trust Product, step 2.1) and "the policy_sid is..." (Customer Profile, step 1.10). Twilio's separate
// general Trust Hub overview page recommends a runtime GET /v1/Policies lookup as a general best practice, but
// the ISV guide itself hardcodes these two for exactly this flow.
export const CUSTOMER_PROFILE_POLICY_SID = 'RNdfbf3fae0e1107f8aded0e7cead80bf5';
export const A2P_TRUST_PRODUCT_POLICY_SID = 'RNb0d4771c2c98518d916a3d4cd70a8f8b';
// Fixed per Twilio's separate "New Sole Proprietor A2P 10DLC Registration for ISVs" guide (2026-09-15 research):
// a Starter Customer Profile plays the same bundle role as a Secondary Customer Profile above, and a Sole
// Proprietor A2P Trust Bundle plays the same role as the A2P Trust Product above -- both created through the
// exact same CustomerProfiles/TrustProducts endpoints, distinguished only by policy_sid.
export const STARTER_CUSTOMER_PROFILE_POLICY_SID = 'RN806dd6cd175f314e1f96a9727ee271f4';
export const SOLE_PROPRIETOR_TRUST_POLICY_SID = 'RN670d5d2e282a6130ae063b234b6019c8';

const PROVIDER_TIMEOUT_MS = 15_000;

export class TwilioTrustHubError extends Error {
	constructor(
		message: string,
		public readonly status: number | null,
		public readonly code: string,
		// A definite 4xx rejection needs operator review; a 429/5xx/network outcome is safe to retry since every
		// step below reconciles the ledger's stored SID before creating anything.
		public readonly retryable: boolean,
		public readonly providerCode: string | null = null
	) {
		super(message);
		this.name = 'TwilioTrustHubError';
	}
}

export type CustomerProfileStatus =
	'draft' | 'pending-review' | 'in-review' | 'twilio-rejected' | 'twilio-approved';

export type CreatedCustomerProfile = { sid: string; status: CustomerProfileStatus };
export type CreatedEndUser = { sid: string };
export type CreatedAddress = { sid: string };
export type CreatedSupportingDocument = { sid: string };
export type CreatedEntityAssignment = { sid: string; objectSid: string };
export type EvaluationResultItem = {
	requirementName: string;
	passed: boolean;
	failureReason: string | null;
};
export type EvaluationOutcome = {
	sid: string;
	status: 'compliant' | 'noncompliant';
	results: EvaluationResultItem[];
};
export type BrandRegistrationStatus = 'PENDING' | 'IN_REVIEW' | 'APPROVED' | 'FAILED' | 'SUSPENDED';
export type CreatedBrandRegistration = {
	sid: string;
	status: BrandRegistrationStatus;
	failureReason: string | null;
};

// Verified against Twilio's Usa2p (A2P Campaign) resource doc, 2026-09-15: PENDING (not yet seen by The
// Campaign Registry) -> IN_PROGRESS (TCR reviewing) -> VERIFIED (approved) | FAILED (rejected), with SUSPENDED
// as a rare separate terminal state -- a distinct enum from BrandRegistrationStatus (Twilio's own naming: a
// Brand is "APPROVED", a Campaign is "VERIFIED").
export type CampaignStatus = 'PENDING' | 'IN_PROGRESS' | 'VERIFIED' | 'FAILED' | 'SUSPENDED';
export type CreatedCampaign = {
	sid: string;
	status: CampaignStatus;
	failureReason: string | null;
};

export type CreateCustomerProfileInput = {
	friendlyName: string;
	email: string;
	statusCallback?: string;
	// Which Trust Hub policy this bundle is evaluated against -- the caller decides (Standard/Low-Volume Secondary
	// Customer Profile vs. Sole Proprietor Starter Customer Profile), this adapter just submits it.
	policySid: string;
};
export type CreateTrustProductInput = {
	friendlyName: string;
	email: string;
	statusCallback?: string;
	policySid: string;
};
export type CreateEndUserInput = {
	friendlyName: string;
	type: string;
	attributes: Record<string, unknown>;
};
export type CreateAddressInput = {
	customerName: string;
	street: string;
	streetSecondary?: string;
	city: string;
	region: string;
	postalCode: string;
	isoCountry: string;
	friendlyName: string;
};
export type CreateSupportingDocumentInput = {
	friendlyName: string;
	type: string;
	attributes: Record<string, unknown>;
};
export type CreateCampaignInput = {
	messagingServiceSid: string;
	brandRegistrationSid: string;
	// Twilio requires min 40 chars for description/messageFlow and 2-5 samples of 20-1024 chars each -- the
	// caller (trust-hub-submission.ts) owns building content that actually meets those bounds; this adapter
	// only carries it to Twilio verbatim.
	description: string;
	messageFlow: string;
	messageSamples: string[];
	usAppToPersonUsecase: string;
	hasEmbeddedLinks: boolean;
	hasEmbeddedPhone: boolean;
};

/**
 * The Trust Hub / Brand Registration operations the submission saga needs. Kept semantic so the saga can inject
 * a fake in tests -- no test in this codebase ever contacts Twilio's Trust Hub.
 */
export type TwilioTrustHubClient = {
	createCustomerProfile(input: CreateCustomerProfileInput): Promise<CreatedCustomerProfile>;
	createTrustProduct(input: CreateTrustProductInput): Promise<CreatedCustomerProfile>;
	createEndUser(input: CreateEndUserInput): Promise<CreatedEndUser>;
	createAddress(input: CreateAddressInput): Promise<CreatedAddress>;
	createSupportingDocument(
		input: CreateSupportingDocumentInput
	): Promise<CreatedSupportingDocument>;
	/** Attach an object (EndUser, SupportingDocument, or another CustomerProfile) to a Customer Profile bundle. */
	createCustomerProfileEntityAssignment(input: {
		customerProfileSid: string;
		objectSid: string;
	}): Promise<CreatedEntityAssignment>;
	createTrustProductEntityAssignment(input: {
		trustProductSid: string;
		objectSid: string;
	}): Promise<CreatedEntityAssignment>;
	evaluateCustomerProfile(input: {
		customerProfileSid: string;
		policySid: string;
	}): Promise<EvaluationOutcome>;
	evaluateTrustProduct(input: {
		trustProductSid: string;
		policySid: string;
	}): Promise<EvaluationOutcome>;
	/** Move a Customer Profile from `draft` to `pending-review`, which Twilio then advances to `in-review`. */
	submitCustomerProfileForReview(customerProfileSid: string): Promise<CreatedCustomerProfile>;
	submitTrustProductForReview(trustProductSid: string): Promise<CreatedCustomerProfile>;
	createBrandRegistration(input: {
		customerProfileBundleSid: string;
		a2pProfileBundleSid: string;
		// Omitted defaults to Twilio's own "STANDARD" (verified against the BrandRegistrations request schema,
		// 2026-09-15): "SOLE_PROPRIETOR is for low volume, SOLE_PROPRIETOR use cases. STANDARD is for all other
		// use cases."
		brandType?: 'STANDARD' | 'SOLE_PROPRIETOR';
		skipAutomaticSecVet?: boolean;
		mock?: boolean;
	}): Promise<CreatedBrandRegistration>;
	/** Re-read a Brand's current status (Stage 9C: syncing status back onto communication_sms_registrations). */
	fetchBrandRegistration(brandRegistrationSid: string): Promise<CreatedBrandRegistration>;
	/** Create the Campaign (Usa2p resource) once the Brand is approved. Real, billable, and -- per Twilio's own
	 *  guide -- must never be recreated once it exists, matching brand_registration's ledger treatment. */
	createCampaign(input: CreateCampaignInput): Promise<CreatedCampaign>;
	fetchCampaign(input: {
		messagingServiceSid: string;
		campaignSid: string;
	}): Promise<CreatedCampaign>;
};

function basicAuthHeader(user: string, password: string): string {
	return `Basic ${Buffer.from(`${user}:${password}`, 'utf8').toString('base64')}`;
}

type TrustHubRequest = {
	base: string;
	path: string;
	method: 'GET' | 'POST';
	auth: string;
	// A string[] value is sent as the same key repeated (Twilio's convention for list parameters, e.g.
	// MessageSamples on the Usa2p/Campaign create call), not a single JSON-encoded field.
	form?: Record<string, string | string[]>;
};

function encodeForm(form: Record<string, string | string[]>): string {
	const params = new URLSearchParams();
	for (const [key, value] of Object.entries(form)) {
		if (Array.isArray(value)) {
			for (const item of value) params.append(key, item);
		} else {
			params.append(key, value);
		}
	}
	return params.toString();
}

async function trustHubRequest(
	request: TrustHubRequest
): Promise<{ status: number; body: unknown }> {
	const url = new URL(request.path, request.base);
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
			body: request.form ? encodeForm(request.form) : undefined,
			signal: controller.signal
		});
	} catch {
		// Network failure or timeout: the provider outcome is unknown, so it is safe to re-run (every step below
		// reconciles the ledger's known SID before creating). Never surface the underlying error text -- it can
		// echo request headers, including credentials.
		throw new TwilioTrustHubError(
			'Twilio did not return a result.',
			null,
			'twilio_trust_hub_unknown',
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
			body &&
			typeof body === 'object' &&
			'code' in body &&
			typeof (body as { code: unknown }).code === 'number'
				? String((body as { code: number }).code)
				: null;
		const retryable = response.status === 429 || response.status >= 500;
		throw new TwilioTrustHubError(
			`Twilio rejected a Trust Hub request (status ${response.status}).`,
			response.status,
			'twilio_trust_hub_rejected',
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
		throw new TwilioTrustHubError('Twilio returned an unexpected identifier.', null, code, false);
	}
	return value;
}

function readEvaluation(body: unknown): EvaluationOutcome {
	const sid = requireSid(
		readString(body, 'sid'),
		EVALUATION_SID,
		'twilio_trust_hub_missing_evaluation_sid'
	);
	const status = readString(body, 'status');
	const results =
		body && typeof body === 'object' && Array.isArray((body as { results?: unknown }).results)
			? ((body as { results: unknown[] }).results as unknown[]).map((row) => ({
					requirementName:
						readString(row, 'requirement_name') ?? readString(row, 'friendly_name') ?? 'unknown',
					passed: Boolean(
						row && typeof row === 'object' && (row as { passed?: unknown }).passed === true
					),
					failureReason: readString(row, 'failure_reason')
				}))
			: [];
	return {
		sid,
		status: status === 'compliant' ? 'compliant' : 'noncompliant',
		results
	};
}

function readCustomerProfile(
	body: unknown,
	sidPattern: RegExp,
	code: string
): CreatedCustomerProfile {
	const sid = requireSid(readString(body, 'sid'), sidPattern, code);
	const status = readString(body, 'status') ?? 'draft';
	return { sid, status: status as CustomerProfileStatus };
}

function readErrorsSummary(body: unknown): string | null {
	const direct = readString(body, 'failure_reason');
	if (direct) return direct;
	const errors =
		body && typeof body === 'object' && Array.isArray((body as { errors?: unknown }).errors)
			? ((body as { errors: unknown[] }).errors as unknown[])
			: [];
	const messages = errors
		.map((entry) => readString(entry, 'message'))
		.filter((message): message is string => Boolean(message));
	return messages.length > 0 ? messages.join('; ') : null;
}

function readBrandRegistration(body: unknown): CreatedBrandRegistration {
	const sid = requireSid(
		readString(body, 'sid'),
		BRAND_REGISTRATION_SID,
		'twilio_trust_hub_missing_brand_sid'
	);
	const status = readString(body, 'status') ?? 'PENDING';
	return {
		sid,
		status: status as CreatedBrandRegistration['status'],
		failureReason: readErrorsSummary(body)
	};
}

function readCampaign(body: unknown): CreatedCampaign {
	const sid = requireSid(
		readString(body, 'sid'),
		CAMPAIGN_SID,
		'twilio_trust_hub_missing_campaign_sid'
	);
	const status = readString(body, 'campaign_status') ?? 'PENDING';
	return {
		sid,
		status: status as CampaignStatus,
		failureReason: readErrorsSummary(body)
	};
}

/** The live Trust Hub / Brand Registration adapter. */
export function createTwilioTrustHubClient(
	platform: TwilioPlatformEnv = getTwilioPlatformEnv()
): TwilioTrustHubClient {
	const auth = basicAuthHeader(
		platform.TWILIO_PROVISIONING_KEY_SID,
		platform.TWILIO_PROVISIONING_KEY_SECRET
	);

	return {
		async createCustomerProfile({ friendlyName, email, statusCallback, policySid }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: '/v1/CustomerProfiles',
				method: 'POST',
				auth,
				form: {
					FriendlyName: friendlyName,
					Email: email,
					PolicySid: policySid,
					...(statusCallback ? { StatusCallback: statusCallback } : {})
				}
			});
			return readCustomerProfile(
				body,
				CUSTOMER_PROFILE_SID,
				'twilio_trust_hub_missing_profile_sid'
			);
		},

		async createTrustProduct({ friendlyName, email, statusCallback, policySid }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: '/v1/TrustProducts',
				method: 'POST',
				auth,
				form: {
					FriendlyName: friendlyName,
					Email: email,
					PolicySid: policySid,
					...(statusCallback ? { StatusCallback: statusCallback } : {})
				}
			});
			return readCustomerProfile(
				body,
				TRUST_PRODUCT_SID,
				'twilio_trust_hub_missing_trust_product_sid'
			);
		},

		async createEndUser({ friendlyName, type, attributes }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: '/v1/EndUsers',
				method: 'POST',
				auth,
				form: { FriendlyName: friendlyName, Type: type, Attributes: JSON.stringify(attributes) }
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					END_USER_SID,
					'twilio_trust_hub_missing_end_user_sid'
				)
			};
		},

		async createAddress(input) {
			const { body } = await trustHubRequest({
				base: TWILIO_API_BASE,
				path: `/2010-04-01/Accounts/${platform.TWILIO_ACCOUNT_SID}/Addresses.json`,
				method: 'POST',
				auth,
				form: {
					CustomerName: input.customerName,
					Street: input.street,
					...(input.streetSecondary ? { StreetSecondary: input.streetSecondary } : {}),
					City: input.city,
					Region: input.region,
					PostalCode: input.postalCode,
					IsoCountry: input.isoCountry,
					FriendlyName: input.friendlyName
				}
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					ADDRESS_SID,
					'twilio_trust_hub_missing_address_sid'
				)
			};
		},

		async createSupportingDocument({ friendlyName, type, attributes }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: '/v1/SupportingDocuments',
				method: 'POST',
				auth,
				form: { FriendlyName: friendlyName, Type: type, Attributes: JSON.stringify(attributes) }
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					SUPPORTING_DOCUMENT_SID,
					'twilio_trust_hub_missing_supporting_document_sid'
				)
			};
		},

		async createCustomerProfileEntityAssignment({ customerProfileSid, objectSid }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: `/v1/CustomerProfiles/${customerProfileSid}/EntityAssignments`,
				method: 'POST',
				auth,
				form: { ObjectSid: objectSid }
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					ASSIGNMENT_SID,
					'twilio_trust_hub_missing_assignment_sid'
				),
				objectSid
			};
		},

		async createTrustProductEntityAssignment({ trustProductSid, objectSid }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: `/v1/TrustProducts/${trustProductSid}/EntityAssignments`,
				method: 'POST',
				auth,
				form: { ObjectSid: objectSid }
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					ASSIGNMENT_SID,
					'twilio_trust_hub_missing_assignment_sid'
				),
				objectSid
			};
		},

		async evaluateCustomerProfile({ customerProfileSid, policySid }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: `/v1/CustomerProfiles/${customerProfileSid}/Evaluations`,
				method: 'POST',
				auth,
				form: { PolicySid: policySid }
			});
			return readEvaluation(body);
		},

		async evaluateTrustProduct({ trustProductSid, policySid }) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: `/v1/TrustProducts/${trustProductSid}/Evaluations`,
				method: 'POST',
				auth,
				form: { PolicySid: policySid }
			});
			return readEvaluation(body);
		},

		async submitCustomerProfileForReview(customerProfileSid) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: `/v1/CustomerProfiles/${customerProfileSid}`,
				method: 'POST',
				auth,
				form: { Status: 'pending-review' }
			});
			return readCustomerProfile(
				body,
				CUSTOMER_PROFILE_SID,
				'twilio_trust_hub_missing_profile_sid'
			);
		},

		async submitTrustProductForReview(trustProductSid) {
			const { body } = await trustHubRequest({
				base: TRUSTHUB_BASE,
				path: `/v1/TrustProducts/${trustProductSid}`,
				method: 'POST',
				auth,
				form: { Status: 'pending-review' }
			});
			return readCustomerProfile(
				body,
				TRUST_PRODUCT_SID,
				'twilio_trust_hub_missing_trust_product_sid'
			);
		},

		async createBrandRegistration({
			customerProfileBundleSid,
			a2pProfileBundleSid,
			brandType,
			skipAutomaticSecVet,
			mock
		}) {
			const { body } = await trustHubRequest({
				base: MESSAGING_BASE,
				path: '/v1/a2p/BrandRegistrations',
				method: 'POST',
				auth,
				form: {
					CustomerProfileBundleSid: customerProfileBundleSid,
					A2PProfileBundleSid: a2pProfileBundleSid,
					...(brandType ? { BrandType: brandType } : {}),
					...(skipAutomaticSecVet !== undefined
						? { SkipAutomaticSecVet: String(skipAutomaticSecVet) }
						: {}),
					...(mock !== undefined ? { Mock: String(mock) } : {})
				}
			});
			return readBrandRegistration(body);
		},

		async fetchBrandRegistration(brandRegistrationSid) {
			const { body } = await trustHubRequest({
				base: MESSAGING_BASE,
				path: `/v1/a2p/BrandRegistrations/${brandRegistrationSid}`,
				method: 'GET',
				auth
			});
			return readBrandRegistration(body);
		},

		async createCampaign({
			messagingServiceSid,
			brandRegistrationSid,
			description,
			messageFlow,
			messageSamples,
			usAppToPersonUsecase,
			hasEmbeddedLinks,
			hasEmbeddedPhone
		}) {
			const { body } = await trustHubRequest({
				base: MESSAGING_BASE,
				path: `/v1/Services/${messagingServiceSid}/Compliance/Usa2p`,
				method: 'POST',
				auth,
				form: {
					BrandRegistrationSid: brandRegistrationSid,
					Description: description,
					MessageFlow: messageFlow,
					MessageSamples: messageSamples,
					UsAppToPersonUsecase: usAppToPersonUsecase,
					HasEmbeddedLinks: String(hasEmbeddedLinks),
					HasEmbeddedPhone: String(hasEmbeddedPhone)
				}
			});
			return readCampaign(body);
		},

		async fetchCampaign({ messagingServiceSid, campaignSid }) {
			const { body } = await trustHubRequest({
				base: MESSAGING_BASE,
				path: `/v1/Services/${messagingServiceSid}/Compliance/Usa2p/${campaignSid}`,
				method: 'GET',
				auth
			});
			return readCampaign(body);
		}
	};
}
