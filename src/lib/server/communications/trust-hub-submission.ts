import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	A2P_TRUST_PRODUCT_POLICY_SID,
	CUSTOMER_PROFILE_POLICY_SID,
	SOLE_PROPRIETOR_TRUST_POLICY_SID,
	STARTER_CUSTOMER_PROFILE_POLICY_SID,
	createTwilioTrustHubClient,
	type EvaluationOutcome,
	type TwilioTrustHubClient
} from './twilio-trust-hub';
import {
	createSupabaseTrustHubSubmissionStore,
	type StoredTrustHubResource,
	type TrustHubResourceRole,
	type TrustHubResourceStatus,
	type TrustHubSubmissionStore
} from './trust-hub-submission-store';
import type { SmsRegistrationAnswers } from '$lib/server/validation/communications-sms-registration.schema';

// The Twilio Trust Hub submission saga (A2 Stage 9B): the actual API calls that carry a contractor's attested
// registration (Stage 3A) to Twilio as an ISV sub-customer, writing Stage 9A's ledger at every step. A
// desired-state reconciler like the subaccount provisioning saga (twilio-provisioning.ts): every step is
// idempotent against the ledger, no step is retried blindly once its resource row says `created`/`submitted`,
// and a repeated call resumes rather than recreating -- required for `brand_registration`, which carries a real
// Twilio fee and must never be silently recreated (Stage 9A's own table comment).
//
// Two Twilio ISV paths, chosen per registration from the contractor's own attested answers (never guessed):
//   - Standard/Low-Volume Standard: a Secondary Customer Profile + A2P Trust Product, for any business with a
//     registration ID (EIN or equivalent).
//   - Sole Proprietor: a Starter Customer Profile + Sole Proprietor A2P Trust Bundle, for a `sole_proprietorship`
//     with no registration ID -- confirmed against Twilio's separate "New Sole Proprietor A2P 10DLC Registration
//     for ISVs" guide (2026-09-15 research, not memory). Twilio verifies the sole proprietor by texting a one-
//     time code to their own mobile number (the `authorized_representative.phone_number` already collected --
//     Twilio's own docs: "for sole proprietorships, the authorized representative is the sole proprietor") and
//     they reply YES directly to Twilio; no code in this saga is involved in that reply.
// `business_type` values other than these two have no Twilio mapping (Twilio's Standard business_type enum has
// no "Sole Proprietor" option either -- confirmed against the A2P 10DLC "Gather Business Information" page) and
// are refused here with a clear error rather than mapped to the nearest wrong Twilio value.
//
// Twilio's own guide: "rate limit all API requests for Brand and Campaign registration to one request per
// second." This saga makes exactly one Brand-registration call per invocation, so no internal pacing is
// needed; a future caller that runs this saga for many registrations back-to-back owns spacing those calls.
//
// Stage 9C's job, not this saga's: syncing Brand/Campaign status back onto communication_sms_registrations, and
// creating the Campaign once the Brand is approved. This saga stops once the Brand Registration is created.

export class TrustHubSubmissionError extends Error {
	constructor(
		message: string,
		public readonly code: string,
		public readonly retryable: boolean
	) {
		super(message);
		this.name = 'TrustHubSubmissionError';
	}
}

export type TrustHubSubmissionDeps = {
	store: TrustHubSubmissionStore;
	twilio: TwilioTrustHubClient;
};

export type SubmitRegistrationInput = {
	registrationId: string;
	// The ISV's own already-approved Primary Customer Profile bundle SID (Stage 9's hard constraint: this does
	// not exist yet for UCRM's platform account). Required and never defaulted -- there is no safe placeholder.
	isvPrimaryCustomerProfileSid: string;
	// The ISV's own monitoring address and optional webhook, supplied by the caller (mirrors
	// ProvisionInput.statusCallback in twilio-provisioning.ts) rather than a hardcoded or guessed constant.
	monitoringEmail: string;
	statusCallback?: string;
	// Passed straight through to Twilio's BrandRegistrations create call. Whether UCRM's real submissions should
	// ever use Twilio's Mock Brand feature is a product decision for whoever wires up the live caller, not this
	// saga -- defaults to unset (a real, billable Brand) rather than assumed true or false.
	mock?: boolean;
};

export type TrustHubSubmissionSummary = {
	registrationId: string;
	customerProfileSid: string;
	trustProductSid: string;
	brandRegistrationSid: string;
	brandStatus: string;
};

// --- Twilio's fixed enums for the Standard/Low-Volume Standard path (verified against Twilio's docs, 2026) ---

// Every UCRM organization is a contractor business by product definition, so this is a constant, not a
// contractor-facing question.
const BUSINESS_INDUSTRY = 'CONSTRUCTION';

const BUSINESS_TYPE_MAP: Partial<Record<SmsRegistrationAnswers['business_type'], string>> = {
	partnership: 'Partnership',
	limited_liability_company: 'Limited Liability Corporation',
	cooperative: 'Co-operative',
	nonprofit_corporation: 'Non-profit Corporation',
	corporation: 'Corporation'
};

const REGISTRATION_ID_TYPES = ['EIN', 'DUNS', 'CBN', 'CN', 'ACN', 'CIN', 'VAT', 'VATRN', 'RN'];

const JOB_POSITION_MAP: Record<string, string> = {
	ceo: 'CEO',
	'chief executive officer': 'CEO',
	cfo: 'CFO',
	'chief financial officer': 'CFO',
	director: 'Director',
	gm: 'GM',
	'general manager': 'GM',
	vp: 'VP',
	'vice president': 'VP',
	'general counsel': 'General Counsel'
};

function mapBusinessType(businessType: SmsRegistrationAnswers['business_type']): string {
	const mapped = BUSINESS_TYPE_MAP[businessType];
	if (!mapped) {
		// Reached only for a `sole_proprietorship` that has a registration ID (so it did not qualify for the Sole
		// Proprietor path above) or `other`. Twilio's Standard business_type enum has no matching value for
		// either -- a real, rare gap in Twilio's own system, not something this saga can resolve automatically.
		throw new TrustHubSubmissionError(
			`Twilio's Standard onboarding path has no business_type mapping for "${businessType}". This needs ` +
				"manual review against Twilio's current guidance before it can be submitted.",
			'unsupported_business_type',
			false
		);
	}
	return mapped;
}

function mapRegistrationIdType(raw: string): string {
	const normalized = raw.trim().toUpperCase();
	return REGISTRATION_ID_TYPES.includes(normalized) ? normalized : 'Other';
}

function mapJobPosition(raw: string): string {
	return JOB_POSITION_MAP[raw.trim().toLowerCase()] ?? 'Other';
}

function mapRegionOfOperation(countryCode: string): string {
	if (countryCode === 'US' || countryCode === 'CA') return 'USA_AND_CANADA';
	throw new TrustHubSubmissionError(
		`No verified Twilio business_regions_of_operation mapping for country "${countryCode}" yet.`,
		'unsupported_country',
		false
	);
}

function friendlyName(registrationId: string, suffix: string): string {
	return `ucrm-reg-${registrationId}-${suffix}`;
}

function buildBusinessInformationAttributes(answers: SmsRegistrationAnswers, countryCode: string) {
	// business_registration_id_type/id are optional on the shared answers type only because a Sole Proprietor
	// submission omits them -- this builder is only ever called from the Standard path (submitStandardSections),
	// where the schema's superRefine already guarantees both are non-empty.
	return {
		business_name: answers.legal_business_name,
		business_identity: 'direct_customer',
		business_industry: BUSINESS_INDUSTRY,
		business_type: mapBusinessType(answers.business_type),
		business_registration_identifier: mapRegistrationIdType(answers.business_registration_id_type!),
		business_registration_number: answers.business_registration_id!,
		business_regions_of_operation: mapRegionOfOperation(countryCode),
		website_url: answers.website_url
	};
}

function buildAuthorizedRepresentativeAttributes(
	rep: SmsRegistrationAnswers['authorized_representative']
) {
	return {
		first_name: rep.first_name,
		last_name: rep.last_name,
		email: rep.email,
		phone_number: rep.phone_number,
		business_title: rep.business_title,
		job_position: mapJobPosition(rep.job_position)
	};
}

function buildMessagingProfileAttributes(answers: SmsRegistrationAnswers) {
	// Twilio's own docs disagree on the exact literal for the non-profit value ("non-profit" on the field's own
	// page vs "non_profit" on a separate onboarding guide). Using the field's own page's spelling; must be
	// verified against a live response (or the OpenAPI schema) before this saga ever runs against real Twilio.
	return {
		company_type: answers.business_type === 'nonprofit_corporation' ? 'non-profit' : 'private'
	};
}

// --- Sole Proprietor path attribute builders (verified against Twilio's Sole Proprietor ISV guide, 2026) ---

function buildStarterProfileEndUserAttributes(answers: SmsRegistrationAnswers) {
	// Twilio's own docs: "for sole proprietorships, the authorized representative is the sole proprietor" -- so
	// the same contact already collected in Stage 3A is reused rather than asking a second time.
	const rep = answers.authorized_representative;
	return {
		email: rep.email,
		first_name: rep.first_name,
		last_name: rep.last_name,
		phone_number: rep.phone_number
	};
}

function buildSoleProprietorAttributes(answers: SmsRegistrationAnswers) {
	return {
		// "usually the proprietor's first and last name, but a DBA is also accepted" -- legal_business_name is
		// always collected (Stage 3A requires it for every business_type), so it is reused rather than assuming
		// the representative's name doubles as the brand name.
		brand_name: answers.legal_business_name,
		// The Sole Proprietor `vertical` enum is a different, shorter list than the Standard `business_industry`
		// enum above, but 'CONSTRUCTION' is a valid value on both (checked against Twilio's docs for this enum
		// specifically, not assumed from the Standard one) -- every UCRM organization is a contractor business.
		vertical: BUSINESS_INDUSTRY,
		// Twilio sends a one-time SMS passcode to this exact number and needs a YES reply from its owner -- must
		// be the contractor's own real mobile number, never a Twilio-provisioned number.
		mobile_phone_number: answers.authorized_representative.phone_number
	};
}

type Ctx = { organizationId: string; registrationId: string };

async function ensureResourceCreated(
	store: TrustHubSubmissionStore,
	ctx: Ctx,
	role: TrustHubResourceRole,
	step: string,
	create: () => Promise<{ sid: string; status?: string | null }>
): Promise<StoredTrustHubResource> {
	const existing = await store.getResource(ctx.registrationId, role);
	if (existing?.providerSid) {
		await store.recordEvent({
			...ctx,
			resourceRole: role,
			operation: 'submit_registration',
			step,
			result: 'skipped'
		});
		return existing;
	}
	const created = await create();
	const stored = await store.upsertResource({
		...ctx,
		resourceRole: role,
		providerSid: created.sid,
		providerStatus: created.status ?? null,
		status: 'created'
	});
	await store.recordEvent({
		...ctx,
		resourceRole: role,
		operation: 'submit_registration',
		step,
		result: 'succeeded',
		detail: { provider_sid: created.sid }
	});
	return stored;
}

/** Attach `child`'s provider object to a parent bundle exactly once, tracked via the child's own resource row
 *  (status `created` -> `submitted` means "attached"). Twilio has no idempotency key for entity assignments, so
 *  the ledger -- not a Twilio-side list call -- is the resumability source of truth, matching how every other
 *  saga step in this codebase works. */
async function ensureAssignedToParent(
	store: TrustHubSubmissionStore,
	ctx: Ctx,
	child: StoredTrustHubResource,
	step: string,
	assign: () => Promise<unknown>
): Promise<void> {
	if (child.status === 'submitted' || child.status === 'approved') {
		await store.recordEvent({
			...ctx,
			resourceRole: child.resourceRole,
			operation: 'submit_registration',
			step,
			result: 'skipped'
		});
		return;
	}
	await assign();
	await store.upsertResource({
		...ctx,
		resourceRole: child.resourceRole,
		providerSid: child.providerSid,
		providerStatus: child.providerStatus,
		status: 'submitted' satisfies TrustHubResourceStatus
	});
	await store.recordEvent({
		...ctx,
		resourceRole: child.resourceRole,
		operation: 'submit_registration',
		step,
		result: 'succeeded'
	});
}

/** Evaluate a bundle; on failure, mark its resource row `failed` with a sanitized reason (requirement names
 *  only, never the raw evaluation body) and throw so the caller stops rather than submitting non-compliant
 *  data for review. */
async function evaluateOrFail(
	store: TrustHubSubmissionStore,
	ctx: Ctx,
	role: TrustHubResourceRole,
	step: string,
	evaluate: () => Promise<EvaluationOutcome>
): Promise<void> {
	const outcome = await evaluate();
	if (outcome.status === 'compliant') {
		await store.recordEvent({
			...ctx,
			resourceRole: role,
			operation: 'submit_registration',
			step,
			result: 'succeeded',
			detail: { evaluation_sid: outcome.sid }
		});
		return;
	}
	const failing = outcome.results.filter((result) => !result.passed);
	const failureReason =
		failing.map((result) => result.requirementName).join(', ') || 'evaluation failed';
	await store.upsertResource({
		...ctx,
		resourceRole: role,
		status: 'failed',
		failureReason: failureReason.slice(0, 2000)
	});
	await store.recordEvent({
		...ctx,
		resourceRole: role,
		operation: 'submit_registration',
		step,
		result: 'needs_review',
		detail: {
			evaluation_sid: outcome.sid,
			failing_requirements: failing.map((result) => result.requirementName)
		}
	});
	throw new TrustHubSubmissionError(
		`Twilio's compliance evaluation failed: ${failureReason}`,
		'twilio_trust_hub_evaluation_failed',
		false
	);
}

type PathResult = {
	customerProfile: StoredTrustHubResource;
	trustProduct: StoredTrustHubResource;
};

/** Standard/Low-Volume Standard path: Secondary Customer Profile + A2P Trust Product, for any business with a
 *  registration ID. Sections 1 and 2 of Twilio's Standard ISV onboarding guide. */
async function submitStandardSections(
	store: TrustHubSubmissionStore,
	twilio: TwilioTrustHubClient,
	ctx: Ctx,
	input: SubmitRegistrationInput,
	answers: SmsRegistrationAnswers,
	countryCode: string
): Promise<PathResult> {
	// --- Section 1: Secondary Customer Profile ---
	let customerProfile = await ensureResourceCreated(
		store,
		ctx,
		'customer_profile',
		'create_customer_profile',
		() =>
			twilio.createCustomerProfile({
				friendlyName: friendlyName(input.registrationId, 'business-profile'),
				email: input.monitoringEmail,
				statusCallback: input.statusCallback,
				policySid: CUSTOMER_PROFILE_POLICY_SID
			})
	);

	const businessInfo = await ensureResourceCreated(
		store,
		ctx,
		'end_user_business_information',
		'create_business_information_end_user',
		() =>
			twilio.createEndUser({
				friendlyName: friendlyName(input.registrationId, 'business-info'),
				type: 'customer_profile_business_information',
				attributes: buildBusinessInformationAttributes(answers, countryCode)
			})
	);

	const authorizedRep = await ensureResourceCreated(
		store,
		ctx,
		'end_user_authorized_representative',
		'create_authorized_representative_end_user',
		() =>
			twilio.createEndUser({
				friendlyName: friendlyName(input.registrationId, 'authorized-rep'),
				type: 'authorized_representative_1',
				attributes: buildAuthorizedRepresentativeAttributes(answers.authorized_representative)
			})
	);

	// Address + the SupportingDocument that wraps it are created together as one step. A crash between the two
	// Twilio calls can leave an orphan Address with no local record (Twilio does not bill or expose Addresses in
	// a way that makes this costly), which a retry would recreate rather than reconcile -- accepted for now,
	// unlike Brand Registration below where a duplicate is never acceptable.
	const address = await ensureResourceCreated(
		store,
		ctx,
		'supporting_document_address',
		'create_address_supporting_document',
		async () => {
			const businessAddress = answers.business_address;
			const createdAddress = await twilio.createAddress({
				customerName: answers.legal_business_name,
				street: businessAddress.line1,
				streetSecondary: businessAddress.line2,
				city: businessAddress.city,
				region: businessAddress.region,
				postalCode: businessAddress.postal_code,
				isoCountry: businessAddress.country_code,
				friendlyName: friendlyName(input.registrationId, 'address')
			});
			const supportingDocument = await twilio.createSupportingDocument({
				friendlyName: friendlyName(input.registrationId, 'address-document'),
				type: 'customer_profile_address',
				attributes: { address_sids: createdAddress.sid }
			});
			return { sid: supportingDocument.sid };
		}
	);

	await ensureAssignedToParent(store, ctx, businessInfo, 'attach_business_information', () =>
		twilio.createCustomerProfileEntityAssignment({
			customerProfileSid: customerProfile.providerSid!,
			objectSid: businessInfo.providerSid!
		})
	);
	await ensureAssignedToParent(store, ctx, authorizedRep, 'attach_authorized_representative', () =>
		twilio.createCustomerProfileEntityAssignment({
			customerProfileSid: customerProfile.providerSid!,
			objectSid: authorizedRep.providerSid!
		})
	);
	await ensureAssignedToParent(store, ctx, address, 'attach_address', () =>
		twilio.createCustomerProfileEntityAssignment({
			customerProfileSid: customerProfile.providerSid!,
			objectSid: address.providerSid!
		})
	);

	if (customerProfile.status !== 'submitted') {
		// Attaching the ISV's own Primary Customer Profile has no resource row of its own (nothing is created at
		// Twilio for it, only a link to an already-existing SID), so it re-runs on every retry until this whole
		// section completes. Harmless: the same low-cost redundancy tradeoff as the Address step above.
		await twilio.createCustomerProfileEntityAssignment({
			customerProfileSid: customerProfile.providerSid!,
			objectSid: input.isvPrimaryCustomerProfileSid
		});
		await evaluateOrFail(store, ctx, 'customer_profile', 'evaluate_customer_profile', () =>
			twilio.evaluateCustomerProfile({
				customerProfileSid: customerProfile.providerSid!,
				policySid: CUSTOMER_PROFILE_POLICY_SID
			})
		);
		const submitted = await twilio.submitCustomerProfileForReview(customerProfile.providerSid!);
		customerProfile = await store.upsertResource({
			...ctx,
			resourceRole: 'customer_profile',
			providerSid: submitted.sid,
			providerStatus: submitted.status,
			status: 'submitted'
		});
		await store.recordEvent({
			...ctx,
			resourceRole: 'customer_profile',
			operation: 'submit_registration',
			step: 'submit_customer_profile_for_review',
			result: 'succeeded',
			detail: { provider_status: submitted.status }
		});
	}

	// --- Section 2: A2P Trust Product ---
	let trustProduct = await ensureResourceCreated(
		store,
		ctx,
		'a2p_trust_product',
		'create_trust_product',
		() =>
			twilio.createTrustProduct({
				friendlyName: friendlyName(input.registrationId, 'a2p-profile'),
				email: input.monitoringEmail,
				statusCallback: input.statusCallback,
				policySid: A2P_TRUST_PRODUCT_POLICY_SID
			})
	);

	const messagingProfile = await ensureResourceCreated(
		store,
		ctx,
		'end_user_a2p_messaging_profile',
		'create_a2p_messaging_profile_end_user',
		() =>
			twilio.createEndUser({
				friendlyName: friendlyName(input.registrationId, 'a2p-messaging-profile'),
				type: 'us_a2p_messaging_profile_information',
				attributes: buildMessagingProfileAttributes(answers)
			})
	);

	await ensureAssignedToParent(store, ctx, messagingProfile, 'attach_a2p_messaging_profile', () =>
		twilio.createTrustProductEntityAssignment({
			trustProductSid: trustProduct.providerSid!,
			objectSid: messagingProfile.providerSid!
		})
	);

	if (trustProduct.status !== 'submitted') {
		// Attaching the Secondary Customer Profile to the Trust Product is how Twilio carries the business
		// information through without duplicating the business-info/authorized-rep/address End Users a second
		// time (confirmed against the guide's own step 2.4). Same re-runs-until-done tradeoff as above.
		await twilio.createTrustProductEntityAssignment({
			trustProductSid: trustProduct.providerSid!,
			objectSid: customerProfile.providerSid!
		});
		await evaluateOrFail(store, ctx, 'a2p_trust_product', 'evaluate_trust_product', () =>
			twilio.evaluateTrustProduct({
				trustProductSid: trustProduct.providerSid!,
				policySid: A2P_TRUST_PRODUCT_POLICY_SID
			})
		);
		const submitted = await twilio.submitTrustProductForReview(trustProduct.providerSid!);
		trustProduct = await store.upsertResource({
			...ctx,
			resourceRole: 'a2p_trust_product',
			providerSid: submitted.sid,
			providerStatus: submitted.status,
			status: 'submitted'
		});
		await store.recordEvent({
			...ctx,
			resourceRole: 'a2p_trust_product',
			operation: 'submit_registration',
			step: 'submit_trust_product_for_review',
			result: 'succeeded',
			detail: { provider_status: submitted.status }
		});
	}

	return { customerProfile, trustProduct };
}

/** Sole Proprietor path: Starter Customer Profile + Sole Proprietor A2P Trust Bundle, for a `sole_proprietorship`
 *  with no registration ID. Mirrors submitStandardSections' structure exactly (same ledger roles, same
 *  ensureResourceCreated/ensureAssignedToParent/evaluateOrFail helpers) -- only the bundle policies, end-user
 *  types/attributes, and the single end user per bundle (instead of two) differ, per Twilio's separate Sole
 *  Proprietor ISV guide. */
async function submitSoleProprietorSections(
	store: TrustHubSubmissionStore,
	twilio: TwilioTrustHubClient,
	ctx: Ctx,
	input: SubmitRegistrationInput,
	answers: SmsRegistrationAnswers
): Promise<PathResult> {
	// --- Section 1: Starter Customer Profile ---
	let customerProfile = await ensureResourceCreated(
		store,
		ctx,
		'customer_profile',
		'create_starter_customer_profile',
		() =>
			twilio.createCustomerProfile({
				friendlyName: friendlyName(input.registrationId, 'starter-profile'),
				email: input.monitoringEmail,
				statusCallback: input.statusCallback,
				policySid: STARTER_CUSTOMER_PROFILE_POLICY_SID
			})
	);

	const starterContact = await ensureResourceCreated(
		store,
		ctx,
		'end_user_authorized_representative',
		'create_starter_profile_end_user',
		() =>
			twilio.createEndUser({
				friendlyName: friendlyName(input.registrationId, 'starter-profile-contact'),
				type: 'starter_customer_profile_information',
				attributes: buildStarterProfileEndUserAttributes(answers)
			})
	);

	const address = await ensureResourceCreated(
		store,
		ctx,
		'supporting_document_address',
		'create_address_supporting_document',
		async () => {
			const businessAddress = answers.business_address;
			const createdAddress = await twilio.createAddress({
				customerName: answers.legal_business_name,
				street: businessAddress.line1,
				streetSecondary: businessAddress.line2,
				city: businessAddress.city,
				region: businessAddress.region,
				postalCode: businessAddress.postal_code,
				isoCountry: businessAddress.country_code,
				friendlyName: friendlyName(input.registrationId, 'address')
			});
			const supportingDocument = await twilio.createSupportingDocument({
				friendlyName: friendlyName(input.registrationId, 'address-document'),
				type: 'customer_profile_address',
				attributes: { address_sids: createdAddress.sid }
			});
			return { sid: supportingDocument.sid };
		}
	);

	await ensureAssignedToParent(store, ctx, starterContact, 'attach_starter_profile_contact', () =>
		twilio.createCustomerProfileEntityAssignment({
			customerProfileSid: customerProfile.providerSid!,
			objectSid: starterContact.providerSid!
		})
	);
	await ensureAssignedToParent(store, ctx, address, 'attach_address', () =>
		twilio.createCustomerProfileEntityAssignment({
			customerProfileSid: customerProfile.providerSid!,
			objectSid: address.providerSid!
		})
	);

	if (customerProfile.status !== 'submitted') {
		await twilio.createCustomerProfileEntityAssignment({
			customerProfileSid: customerProfile.providerSid!,
			objectSid: input.isvPrimaryCustomerProfileSid
		});
		await evaluateOrFail(store, ctx, 'customer_profile', 'evaluate_starter_customer_profile', () =>
			twilio.evaluateCustomerProfile({
				customerProfileSid: customerProfile.providerSid!,
				policySid: STARTER_CUSTOMER_PROFILE_POLICY_SID
			})
		);
		const submitted = await twilio.submitCustomerProfileForReview(customerProfile.providerSid!);
		customerProfile = await store.upsertResource({
			...ctx,
			resourceRole: 'customer_profile',
			providerSid: submitted.sid,
			providerStatus: submitted.status,
			status: 'submitted'
		});
		await store.recordEvent({
			...ctx,
			resourceRole: 'customer_profile',
			operation: 'submit_registration',
			step: 'submit_starter_customer_profile_for_review',
			result: 'succeeded',
			detail: { provider_status: submitted.status }
		});
	}

	// --- Section 2: Sole Proprietor A2P Trust Bundle ---
	let trustProduct = await ensureResourceCreated(
		store,
		ctx,
		'a2p_trust_product',
		'create_sole_proprietor_trust_bundle',
		() =>
			twilio.createTrustProduct({
				friendlyName: friendlyName(input.registrationId, 'sole-proprietor-trust'),
				email: input.monitoringEmail,
				statusCallback: input.statusCallback,
				policySid: SOLE_PROPRIETOR_TRUST_POLICY_SID
			})
	);

	const soleProprietorInfo = await ensureResourceCreated(
		store,
		ctx,
		'end_user_a2p_messaging_profile',
		'create_sole_proprietor_information_end_user',
		() =>
			twilio.createEndUser({
				friendlyName: friendlyName(input.registrationId, 'sole-proprietor-info'),
				type: 'sole_proprietor_information',
				attributes: buildSoleProprietorAttributes(answers)
			})
	);

	await ensureAssignedToParent(
		store,
		ctx,
		soleProprietorInfo,
		'attach_sole_proprietor_information',
		() =>
			twilio.createTrustProductEntityAssignment({
				trustProductSid: trustProduct.providerSid!,
				objectSid: soleProprietorInfo.providerSid!
			})
	);

	if (trustProduct.status !== 'submitted') {
		// Attaching the Starter Customer Profile to the Trust Bundle carries the contact/address through, exactly
		// mirroring how the Standard path attaches its Secondary Customer Profile (guide step 2.4.2).
		await twilio.createTrustProductEntityAssignment({
			trustProductSid: trustProduct.providerSid!,
			objectSid: customerProfile.providerSid!
		});
		await evaluateOrFail(
			store,
			ctx,
			'a2p_trust_product',
			'evaluate_sole_proprietor_trust_bundle',
			() =>
				twilio.evaluateTrustProduct({
					trustProductSid: trustProduct.providerSid!,
					policySid: SOLE_PROPRIETOR_TRUST_POLICY_SID
				})
		);
		const submitted = await twilio.submitTrustProductForReview(trustProduct.providerSid!);
		trustProduct = await store.upsertResource({
			...ctx,
			resourceRole: 'a2p_trust_product',
			providerSid: submitted.sid,
			providerStatus: submitted.status,
			status: 'submitted'
		});
		await store.recordEvent({
			...ctx,
			resourceRole: 'a2p_trust_product',
			operation: 'submit_registration',
			step: 'submit_sole_proprietor_trust_bundle_for_review',
			result: 'succeeded',
			detail: { provider_status: submitted.status }
		});
	}

	return { customerProfile, trustProduct };
}

/**
 * Submit one contractor's attested SMS registration to Twilio as an ISV sub-customer. Safe to call repeatedly:
 * every already-completed step is skipped by reading Stage 9A's ledger first. Throws TrustHubSubmissionError
 * (non-retryable) when Twilio's own evaluation rejects the submitted data or the registration uses a business
 * type this saga does not yet support; throws TwilioTrustHubError (from the adapter) for a transport-level
 * failure, whose `retryable` flag tells the caller whether re-running is safe.
 */
export async function submitRegistrationToTrustHub(
	deps: TrustHubSubmissionDeps,
	input: SubmitRegistrationInput
): Promise<TrustHubSubmissionSummary> {
	const { store, twilio } = deps;

	const submission = await store.getLatestSubmission(input.registrationId);
	if (!submission) {
		throw new TrustHubSubmissionError(
			'This registration has no attested submission to send to Twilio.',
			'no_submission',
			false
		);
	}
	const ctx: Ctx = {
		organizationId: submission.organizationId,
		registrationId: input.registrationId
	};
	const { answers, countryCode } = submission;

	// Chosen from the contractor's own attested answers, never guessed: a `sole_proprietorship` with no
	// registration ID is only eligible for Twilio's Sole Proprietor path (enforced by the Zod schema's
	// superRefine, which also requires a US/Canada address for this branch). Everyone else goes Standard.
	const isSoleProprietor =
		answers.business_type === 'sole_proprietorship' && !answers.business_registration_id;

	const { customerProfile, trustProduct } = isSoleProprietor
		? await submitSoleProprietorSections(store, twilio, ctx, input, answers)
		: await submitStandardSections(store, twilio, ctx, input, answers, countryCode);

	// --- Section 3: Brand Registration (shared) ---
	const brand = await ensureResourceCreated(
		store,
		ctx,
		'brand_registration',
		'create_brand_registration',
		() =>
			twilio
				.createBrandRegistration({
					customerProfileBundleSid: customerProfile.providerSid!,
					a2pProfileBundleSid: trustProduct.providerSid!,
					brandType: isSoleProprietor ? 'SOLE_PROPRIETOR' : undefined,
					mock: input.mock
				})
				.then((brandRegistration) => ({
					sid: brandRegistration.sid,
					status: brandRegistration.status
				}))
	);

	return {
		registrationId: input.registrationId,
		customerProfileSid: customerProfile.providerSid!,
		trustProductSid: trustProduct.providerSid!,
		brandRegistrationSid: brand.providerSid!,
		brandStatus: brand.providerStatus ?? 'PENDING'
	};
}

/** Wire the real Supabase store and live Twilio adapter. */
export function createTrustHubSubmissionDeps(): TrustHubSubmissionDeps {
	return {
		store: createSupabaseTrustHubSubmissionStore(getOwnerSupabaseClient()),
		twilio: createTwilioTrustHubClient()
	};
}
