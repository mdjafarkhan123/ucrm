import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getServerEnv } from '$lib/server/env';
import {
	smsTollfreeAnswersSchema,
	type SmsTollfreeAnswers
} from '$lib/server/validation/communications-sms-tollfree.schema';
import type { SmsRegistrationAnswers } from '$lib/server/validation/communications-sms-registration.schema';
import { reconcileSenderReadiness } from './sms-number-readiness';
import {
	createSupabaseTollfreeCheckStore,
	type TollfreeCheckOutcome,
	type TollfreeCheckStatus,
	type TollfreeCheckStore
} from './sms-tollfree-verification-store';
import { createTwilioProvisioningDeps, getSubaccountAccess } from './twilio-provisioning';
import { TwilioRegulatoryError, type SubaccountCredentials } from './twilio-regulatory';
import {
	createTwilioTollfreeClient,
	type TollfreeVerification,
	type TollfreeVerificationForm,
	type TwilioTollfreeClient
} from './twilio-tollfree';

// The toll-free check (Stage 10 Part 4b, docs/global-sms-behavior-contract.md § Part 4): US and Canadian
// toll-free numbers text only once carriers approve the business behind them. GoHighLevel asks for this after a
// toll-free number is bought; Uplift sends it to Twilio's Toll-Free Verification from the business's own
// subaccount, reusing its US registration answers plus pictures of how customers agree to texts.
//
// Sending mirrors number paperwork (sms-number-paperwork.ts): a claim stops double sends, Twilio's record is kept
// the moment it exists, and a send after a dropped connection finds that record instead of making a second one.
// A turned-down check is edited in place while Twilio allows it, otherwise deleted and sent new (Twilio's own
// guidance). Answers arrive by Event Streams (webhooks/twilio/trust-hub-events) with a daily check behind them;
// an approval switches the number on.

export type TollfreeCheckErrorCode = 'not_sendable' | 'incomplete' | 'provider_unavailable';

export class TollfreeCheckError extends Error {
	constructor(
		public readonly code: TollfreeCheckErrorCode,
		message: string
	) {
		super(message);
		this.name = 'TollfreeCheckError';
	}
}

export type TollfreeCheckDeps = {
	store: TollfreeCheckStore;
	twilio: TwilioTollfreeClient;
	/** The business's Twilio subaccount; it exists once the toll-free number was bought. */
	existingSubaccount(organizationId: string): Promise<SubaccountCredentials | null>;
	/** Twilio emails the outcome here; Uplift's own monitored address. */
	notificationEmail(): string;
	/** Switch on the business's numbers whose approval has passed. */
	switchOnNumbers(organizationId: string): Promise<number>;
	now?(): Date;
};

// --- Twilio's fields (verified against the Toll-Free Verification resource, 2026-10-22) -----------------------

// Uplift's texting is customer care and account updates, the same choice as the US registration's
// CUSTOMER_CARE campaign (trust-hub-submission.ts); no marketing mode exists.
const USE_CASE_CATEGORIES = ['CUSTOMER_CARE', 'ACCOUNT_NOTIFICATIONS'];

const OPT_IN_TYPES: Record<
	Exclude<SmsRegistrationAnswers['messaging']['consent_method'], 'other'>,
	string
> = {
	website_form: 'WEB_FORM',
	paper_form: 'PAPER_FORM',
	verbal: 'VERBAL',
	text_initiated: 'VIA_TEXT'
};

// Twilio's monthly volume steps; each estimate rounds up to the step that covers it.
const MESSAGE_VOLUMES: Record<
	SmsRegistrationAnswers['messaging']['estimated_monthly_messages'],
	string
> = {
	under_500: '1,000',
	'500_2000': '10,000',
	'2001_10000': '10,000',
	over_10000: '100,000'
};

const REGISTRATION_AUTHORITIES = [
	'EIN',
	'CBN',
	'CRN',
	'PROVINCIAL_NUMBER',
	'VAT',
	'ACN',
	'ABN',
	'BRN',
	'SIREN',
	'SIRET',
	'NZBN',
	'USt-IdNr',
	'CIF',
	'NIF',
	'CNPJ',
	'UID',
	'NEQ'
];

function businessType(answers: SmsRegistrationAnswers): string {
	if (answers.business_type === 'sole_proprietorship') return 'SOLE_PROPRIETOR';
	if (answers.business_type === 'nonprofit_corporation') return 'NON_PROFIT';
	return 'PRIVATE_PROFIT';
}

function registrationAuthority(raw: string): string {
	const normalized = raw.trim().toUpperCase();
	return REGISTRATION_AUTHORITIES.find((value) => value.toUpperCase() === normalized) ?? 'OTHER';
}

/** The check Twilio is sent, built only from the business's own answers. */
export function tollfreeVerificationForm(
	answers: SmsTollfreeAnswers,
	context: { phoneNumberSid: string; notificationEmail: string; externalReferenceId: string }
): TollfreeVerificationForm {
	const business = answers.business;
	const { messaging, business_address: address, authorized_representative: contact } = business;
	const consent = messaging.consent_method as keyof typeof OPT_IN_TYPES;
	return {
		TollfreePhoneNumberSid: context.phoneNumberSid,
		BusinessName: business.legal_business_name,
		BusinessWebsite: business.website_url,
		BusinessStreetAddress: address.line1,
		...(address.line2 ? { BusinessStreetAddress2: address.line2 } : {}),
		BusinessCity: address.city,
		BusinessStateProvinceRegion: address.region,
		BusinessPostalCode: address.postal_code,
		BusinessCountry: address.country_code,
		BusinessContactFirstName: contact.first_name,
		BusinessContactLastName: contact.last_name,
		BusinessContactEmail: contact.email,
		BusinessContactPhone: contact.phone_number,
		BusinessType: businessType(business),
		// Required for every business type except a sole proprietor, who may have none.
		...(business.business_registration_id
			? {
					BusinessRegistrationNumber: business.business_registration_id,
					BusinessRegistrationAuthority: registrationAuthority(
						business.business_registration_id_type ?? ''
					),
					BusinessRegistrationCountry: address.country_code
				}
			: {}),
		NotificationEmail: context.notificationEmail,
		UseCaseCategories: USE_CASE_CATEGORIES,
		UseCaseSummary: messaging.description,
		ProductionMessageSample: messaging.sample_messages[0],
		OptInType: OPT_IN_TYPES[consent],
		OptInImageUrls: answers.opt_in_image_urls,
		MessageVolume: MESSAGE_VOLUMES[messaging.estimated_monthly_messages],
		AdditionalInformation: messaging.consent_description,
		...(messaging.privacy_policy_url ? { PrivacyPolicyUrl: messaging.privacy_policy_url } : {}),
		...(messaging.terms_url ? { TermsAndConditionsUrl: messaging.terms_url } : {}),
		ExternalReferenceId: context.externalReferenceId
	};
}

// --- Outcomes ------------------------------------------------------------------------------------------------

const PLAIN_REJECTION =
	'Carriers turned down the toll-free check. Check the business details and how customers agree, then send it again.';

function outcomeOf(verification: TollfreeVerification): TollfreeCheckOutcome {
	const base = {
		providerVerificationSid: verification.sid,
		providerStatus: verification.status
	};
	if (verification.status === 'TWILIO_APPROVED') {
		return {
			...base,
			status: 'approved',
			failureReason: null,
			errorCode: null,
			editAllowed: null,
			editExpiresAt: null
		};
	}
	if (verification.status === 'TWILIO_REJECTED') {
		return {
			...base,
			status: 'needs_fix',
			failureReason: verification.rejectionReason?.trim() || PLAIN_REJECTION,
			errorCode: verification.errorCode,
			editAllowed: verification.editAllowed,
			editExpiresAt: verification.editExpiration
		};
	}
	return { ...base, status: 'under_review' };
}

function canEdit(verification: TollfreeVerification, now: Date) {
	return (
		verification.editAllowed === true &&
		(verification.editExpiration === null ||
			Date.parse(verification.editExpiration) > now.getTime())
	);
}

// --- Sending -------------------------------------------------------------------------------------------------

export type TollfreeSendOutcome = { status: Exclude<TollfreeCheckStatus, 'sending' | 'draft'> };

export async function sendTollfreeCheck(
	deps: TollfreeCheckDeps,
	input: {
		organizationId: string;
		verificationId: string;
		expectedRevision: number;
		actorUserId: string;
	}
): Promise<TollfreeSendOutcome> {
	const now = deps.now?.() ?? new Date();
	const claim = await deps.store.claimSending(
		input.organizationId,
		input.verificationId,
		input.expectedRevision
	);
	if (!claim) {
		throw new TollfreeCheckError(
			'not_sendable',
			'This toll-free check changed or is already being sent. Reload it and try again.'
		);
	}
	const { token, previousStatus } = claim;
	const event = (action: string, detail: Record<string, unknown> = {}) =>
		deps.store.recordEvent({
			organizationId: input.organizationId,
			verificationId: input.verificationId,
			action,
			actorUserId: input.actorUserId,
			detail
		});
	const release = () =>
		deps.store.finishSending(input.verificationId, token, {
			status: previousStatus === 'sending' ? 'draft' : previousStatus
		});

	try {
		const loaded = await deps.store.get(input.organizationId, input.verificationId);
		if (!loaded)
			throw new TollfreeCheckError('not_sendable', 'This toll-free check no longer exists.');
		const { check, number } = loaded;
		const parsed = smsTollfreeAnswersSchema.safeParse(check.answers);
		if (!parsed.success) {
			throw new TollfreeCheckError('incomplete', 'Some answers are missing or need a change.');
		}
		if (!number.phoneNumberSid) {
			throw new TollfreeCheckError('not_sendable', 'This number is still being connected.');
		}
		const account = await deps.existingSubaccount(input.organizationId);
		if (!account) {
			throw new TollfreeCheckError('provider_unavailable', 'This number is still being connected.');
		}

		const form = tollfreeVerificationForm(parsed.data, {
			phoneNumberSid: number.phoneNumberSid,
			notificationEmail: deps.notificationEmail(),
			externalReferenceId: check.id
		});

		// The record this check already has at Twilio, including one made before a dropped connection.
		let existing: TollfreeVerification | null = check.providerVerificationSid
			? await deps.twilio.fetch(account, check.providerVerificationSid)
			: await deps.twilio.findForNumber(account, number.phoneNumberSid);
		if (existing) await deps.store.saveProviderSid(check.id, token, existing.sid);

		let sent: TollfreeVerification;
		if (existing && existing.status !== 'TWILIO_REJECTED') {
			// Carriers already have it (or approved it): nothing to send, only the answer to record.
			sent = existing;
		} else if (existing && canEdit(existing, now)) {
			// TollfreePhoneNumberSid is fixed once made; an edit says why it changed.
			const { TollfreePhoneNumberSid: _number, ...edit } = form;
			void _number;
			sent = await deps.twilio.update(account, existing.sid, {
				...edit,
				EditReason: 'Updated the details carriers asked about.'
			});
			await event('sent', { edited: true });
		} else {
			if (existing) {
				await deps.twilio.remove(account, existing.sid);
				await deps.store.saveProviderSid(check.id, token, null);
				await event('replaced', { previous_status: existing.status });
				existing = null;
			}
			sent = await deps.twilio.create(account, form);
			await deps.store.saveProviderSid(check.id, token, sent.sid);
			await event('sent');
		}

		const outcome = outcomeOf(sent);
		await deps.store.finishSending(check.id, token, {
			...outcome,
			submitted: true,
			decided: outcome.status !== 'under_review'
		});
		if (outcome.status === 'approved') await deps.switchOnNumbers(input.organizationId);
		return { status: outcome.status as TollfreeSendOutcome['status'] };
	} catch (error) {
		if (error instanceof TwilioRegulatoryError && !error.retryable && error.status !== null) {
			// Twilio refused what was sent: keep its reason so the business can fix it.
			const reason = error.providerMessage?.trim() || PLAIN_REJECTION;
			await deps.store.finishSending(input.verificationId, token, {
				status: 'needs_fix',
				failureReason: reason,
				errorCode: error.providerCode ? Number(error.providerCode) : null
			});
			await event('refused', { status: error.status, code: error.providerCode });
			return { status: 'needs_fix' };
		}
		await release();
		if (error instanceof TollfreeCheckError) throw error;
		await event('provider_unavailable');
		throw new TollfreeCheckError(
			'provider_unavailable',
			'The phone company could not be reached. Nothing was lost; try again in a minute.'
		);
	}
}

// --- Checking ------------------------------------------------------------------------------------------------

export type TollfreeSyncOutcome =
	| { status: Exclude<TollfreeCheckStatus, 'sending' | 'draft'>; changed: boolean }
	| { skipped: string };

/** Read the check's answer from Twilio and record it; an approval switches the number on. */
export async function syncTollfreeCheck(
	deps: Pick<TollfreeCheckDeps, 'store' | 'twilio' | 'existingSubaccount' | 'switchOnNumbers'>,
	input: { organizationId: string; verificationId: string }
): Promise<TollfreeSyncOutcome> {
	const loaded = await deps.store.get(input.organizationId, input.verificationId);
	if (!loaded) return { skipped: 'missing' };
	const { check } = loaded;
	if (check.status === 'sending' || check.status === 'draft') return { skipped: check.status };
	if (!check.providerVerificationSid) return { skipped: 'no_record' };
	const account = await deps.existingSubaccount(input.organizationId);
	if (!account) return { skipped: 'no_subaccount' };

	const outcome = outcomeOf(await deps.twilio.fetch(account, check.providerVerificationSid));
	const changed = outcome.status !== check.status;
	await deps.store.recordOutcome(check.id, { ...outcome, decided: changed });
	if (changed) {
		await deps.store.recordEvent({
			organizationId: input.organizationId,
			verificationId: check.id,
			action: outcome.status
		});
	}
	if (outcome.status === 'approved') await deps.switchOnNumbers(input.organizationId);
	return { status: outcome.status as 'under_review' | 'approved' | 'needs_fix', changed };
}

/** The daily safety net behind Twilio's status events: re-check every toll-free check still under review. */
export async function runTollfreeStatusCheck(
	deps: Pick<TollfreeCheckDeps, 'store' | 'twilio' | 'existingSubaccount' | 'switchOnNumbers'>,
	limit = 200
): Promise<{ checked: number; approved: number; needsFix: number; failed: number }> {
	const result = { checked: 0, approved: 0, needsFix: 0, failed: 0 };
	for (const item of await deps.store.listUnderReview(limit)) {
		result.checked += 1;
		try {
			const outcome = await syncTollfreeCheck(deps, {
				organizationId: item.organizationId,
				verificationId: item.id
			});
			if ('status' in outcome && outcome.changed) {
				if (outcome.status === 'approved') result.approved += 1;
				if (outcome.status === 'needs_fix') result.needsFix += 1;
			}
		} catch (error) {
			result.failed += 1;
			console.error('Toll-free status check failed for one number.', {
				verificationId: item.id,
				error: error instanceof Error ? error.message : error
			});
		}
	}
	return result;
}

// --- Live wiring ---------------------------------------------------------------------------------------------

export function createTollfreeCheckDeps(): TollfreeCheckDeps {
	const client = getOwnerSupabaseClient();
	const provisioning = createTwilioProvisioningDeps();
	return {
		store: createSupabaseTollfreeCheckStore(client),
		twilio: createTwilioTollfreeClient(),
		async existingSubaccount(organizationId) {
			const access = await getSubaccountAccess(provisioning, organizationId);
			return access ? { subaccountSid: access.subaccountSid, authToken: access.authToken } : null;
		},
		notificationEmail() {
			const email = getServerEnv().TWILIO_ISV_MONITORING_EMAIL;
			if (!email)
				throw new TollfreeCheckError(
					'provider_unavailable',
					'Uplift has not finished its texting setup.'
				);
			return email;
		},
		switchOnNumbers: (organizationId) => reconcileSenderReadiness(client, organizationId)
	};
}
