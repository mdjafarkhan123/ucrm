import { describe, it, expect, beforeEach } from 'vitest';
import {
	submitRegistrationToTrustHub,
	syncTrustHubRegistrationStatus,
	TrustHubSubmissionError
} from './trust-hub-submission';
import type {
	RegistrationSubmissionForSaga,
	StoredTrustHubResource,
	TrustHubEventInput,
	TrustHubResourceRole,
	TrustHubResourceStatus,
	TrustHubSubmissionStore,
	UpsertResourceInput
} from './trust-hub-submission-store';
import type {
	CreatedEntityAssignment,
	EvaluationOutcome,
	TwilioTrustHubClient
} from './twilio-trust-hub';

const REGISTRATION_ID = 'a2700000-0000-4000-8000-000000000011';
const ORG_ID = 'a2600000-0000-4000-8000-000000000011';

const VALID_SUBMISSION: RegistrationSubmissionForSaga = {
	registrationId: REGISTRATION_ID,
	organizationId: ORG_ID,
	countryCode: 'US',
	senderType: 'long_code',
	answers: {
		legal_business_name: 'Raad LTD',
		business_type: 'limited_liability_company',
		business_registration_id_type: 'EIN',
		business_registration_id: '12-3456789',
		website_url: 'https://raad.example.com',
		business_address: {
			line1: '1 Main St',
			line2: undefined,
			city: 'Austin',
			region: 'TX',
			postal_code: '78701',
			country_code: 'US'
		},
		authorized_representative: {
			first_name: 'Jafar',
			last_name: 'Khan',
			business_title: 'Owner',
			job_position: 'ceo',
			email: 'owner@raad.example.com',
			phone_number: '+15005550006'
		},
		messaging: {
			description: 'Job updates and quotes for contracting customers.',
			consent_method: 'website_form',
			consent_description: 'Customers opt in at checkout.',
			sample_messages: ['Your quote is ready.', 'Your job is scheduled for tomorrow.'],
			estimated_monthly_messages: 'under_500'
		}
	}
};

function createFakeStore() {
	const resources = new Map<string, StoredTrustHubResource>();
	const events: TrustHubEventInput[] = [];
	const registrationOutcomes: Array<{
		registrationId: string;
		status: 'approved' | 'action_needed';
		providerOutcome?: string | null;
		requiredFixes?: string | null;
	}> = [];
	const registrationChecks: Array<{ registrationId: string; detail?: string | null }> = [];
	let submission: RegistrationSubmissionForSaga | null = VALID_SUBMISSION;
	let messagingServiceSid: string | null = 'MG'.padEnd(34, '1');
	let seq = 0;

	const key = (registrationId: string, role: TrustHubResourceRole) => `${registrationId}:${role}`;

	const store: TrustHubSubmissionStore = {
		async getLatestSubmission(registrationId) {
			return submission && submission.registrationId === registrationId ? submission : null;
		},
		async getResource(registrationId, resourceRole) {
			return resources.get(key(registrationId, resourceRole)) ?? null;
		},
		async upsertResource(input: UpsertResourceInput) {
			const existing = resources.get(key(input.registrationId, input.resourceRole));
			const stored: StoredTrustHubResource = {
				id: existing?.id ?? `res-${++seq}`,
				registrationId: input.registrationId,
				resourceRole: input.resourceRole,
				providerSid: input.providerSid ?? existing?.providerSid ?? null,
				providerStatus: input.providerStatus ?? existing?.providerStatus ?? null,
				status: input.status,
				failureReason: input.failureReason ?? null
			};
			resources.set(key(input.registrationId, input.resourceRole), stored);
			return stored;
		},
		async recordEvent(input) {
			events.push(input);
		},
		async getMessagingServiceSid() {
			return messagingServiceSid;
		},
		async recordRegistrationOutcome(input) {
			registrationOutcomes.push(input);
		},
		async recordRegistrationCheck(input) {
			registrationChecks.push(input);
		}
	};

	return {
		store,
		events,
		resources,
		registrationOutcomes,
		registrationChecks,
		setSubmission: (value: RegistrationSubmissionForSaga | null) => {
			submission = value;
		},
		setMessagingServiceSid: (value: string | null) => {
			messagingServiceSid = value;
		}
	};
}

function compliant(sid: string): EvaluationOutcome {
	return { sid, status: 'compliant', results: [] };
}

function createFakeTwilio() {
	let sidSeq = 0;
	const nextSid = (prefix: string) => `${prefix}${String(++sidSeq).padStart(32, '0')}`;
	const calls: string[] = [];

	const twilio: TwilioTrustHubClient = {
		async createCustomerProfile() {
			calls.push('createCustomerProfile');
			return { sid: nextSid('BU'), status: 'draft' };
		},
		async createTrustProduct() {
			calls.push('createTrustProduct');
			return { sid: nextSid('BU'), status: 'draft' };
		},
		async createEndUser({ type }) {
			calls.push(`createEndUser:${type}`);
			return { sid: nextSid('IT') };
		},
		async createAddress() {
			calls.push('createAddress');
			return { sid: nextSid('AD') };
		},
		async createSupportingDocument() {
			calls.push('createSupportingDocument');
			return { sid: nextSid('RD') };
		},
		async createCustomerProfileEntityAssignment({ objectSid }): Promise<CreatedEntityAssignment> {
			calls.push('createCustomerProfileEntityAssignment');
			return { sid: nextSid('RA'), objectSid };
		},
		async createTrustProductEntityAssignment({ objectSid }): Promise<CreatedEntityAssignment> {
			calls.push('createTrustProductEntityAssignment');
			return { sid: nextSid('RA'), objectSid };
		},
		async evaluateCustomerProfile({ customerProfileSid }) {
			calls.push('evaluateCustomerProfile');
			return compliant(customerProfileSid);
		},
		async evaluateTrustProduct({ trustProductSid }) {
			calls.push('evaluateTrustProduct');
			return compliant(trustProductSid);
		},
		async submitCustomerProfileForReview(sid) {
			calls.push('submitCustomerProfileForReview');
			return { sid, status: 'pending-review' };
		},
		async submitTrustProductForReview(sid) {
			calls.push('submitTrustProductForReview');
			return { sid, status: 'pending-review' };
		},
		async createBrandRegistration() {
			calls.push('createBrandRegistration');
			return { sid: nextSid('BN'), status: 'PENDING', failureReason: null };
		},
		async fetchBrandRegistration(sid) {
			calls.push('fetchBrandRegistration');
			return { sid, status: 'APPROVED', failureReason: null };
		},
		async createCampaign() {
			calls.push('createCampaign');
			return { sid: nextSid('QE'), status: 'PENDING', failureReason: null };
		},
		async fetchCampaign({ campaignSid }) {
			calls.push('fetchCampaign');
			return { sid: campaignSid, status: 'VERIFIED', failureReason: null };
		}
	};

	return { twilio, calls };
}

const baseInput = {
	registrationId: REGISTRATION_ID,
	isvPrimaryCustomerProfileSid: 'BU'.padEnd(34, '9'),
	monitoringEmail: 'platform@ucrm.example.com'
};

const SOLE_PROPRIETOR_SUBMISSION: RegistrationSubmissionForSaga = {
	...VALID_SUBMISSION,
	answers: {
		...VALID_SUBMISSION.answers,
		business_type: 'sole_proprietorship',
		business_registration_id_type: undefined,
		business_registration_id: undefined
	}
};

describe('submitRegistrationToTrustHub', () => {
	let fakeStore: ReturnType<typeof createFakeStore>;
	let fakeTwilio: ReturnType<typeof createFakeTwilio>;

	beforeEach(() => {
		fakeStore = createFakeStore();
		fakeTwilio = createFakeTwilio();
	});

	it('walks the full Customer Profile -> Trust Product -> Brand sequence and returns the created SIDs', async () => {
		const summary = await submitRegistrationToTrustHub(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			baseInput
		);

		expect(summary.registrationId).toBe(REGISTRATION_ID);
		expect(summary.customerProfileSid).toMatch(/^BU/);
		expect(summary.trustProductSid).toMatch(/^BU/);
		expect(summary.brandRegistrationSid).toMatch(/^BN/);
		expect(summary.brandStatus).toBe('PENDING');

		// Every resource role Stage 9B owns ends up recorded, in the right terminal state.
		const roles: [TrustHubResourceRole, TrustHubResourceStatus][] = [
			['customer_profile', 'submitted'],
			['end_user_business_information', 'submitted'],
			['end_user_authorized_representative', 'submitted'],
			['supporting_document_address', 'submitted'],
			['a2p_trust_product', 'submitted'],
			['end_user_a2p_messaging_profile', 'submitted'],
			['brand_registration', 'created']
		];
		for (const [role, status] of roles) {
			expect(fakeStore.resources.get(`${REGISTRATION_ID}:${role}`)?.status).toBe(status);
		}

		expect(fakeTwilio.calls).toContain('createBrandRegistration');
	});

	it('is idempotent: re-running after full completion makes no further Twilio calls except the brand-registration skip check', async () => {
		await submitRegistrationToTrustHub(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			baseInput
		);
		fakeTwilio.calls.length = 0;

		const summary = await submitRegistrationToTrustHub(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			baseInput
		);

		expect(fakeTwilio.calls).toEqual([]);
		expect(summary.brandRegistrationSid).toMatch(/^BN/);
	});

	it('never creates a second Brand Registration once one exists, even if earlier sections re-run', async () => {
		await submitRegistrationToTrustHub(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			baseInput
		);
		const firstBrandSid = fakeStore.resources.get(
			`${REGISTRATION_ID}:brand_registration`
		)?.providerSid;

		// Simulate a resumed run where the customer_profile row was somehow reset to `created` (not `submitted`)
		// -- the saga must still refuse to create a second Brand.
		const customerProfile = fakeStore.resources.get(`${REGISTRATION_ID}:customer_profile`)!;
		fakeStore.resources.set(`${REGISTRATION_ID}:customer_profile`, {
			...customerProfile,
			status: 'created'
		});
		fakeTwilio.calls.length = 0;

		await submitRegistrationToTrustHub(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			baseInput
		);

		expect(fakeTwilio.calls.filter((call) => call === 'createBrandRegistration')).toHaveLength(0);
		expect(fakeStore.resources.get(`${REGISTRATION_ID}:brand_registration`)?.providerSid).toBe(
			firstBrandSid
		);
	});

	it('rejects a registration with no attested submission', async () => {
		fakeStore.setSubmission(null);
		await expect(
			submitRegistrationToTrustHub({ store: fakeStore.store, twilio: fakeTwilio.twilio }, baseInput)
		).rejects.toMatchObject({ code: 'no_submission' });
	});

	it('rejects a sole-proprietor business type rather than guessing a Twilio mapping', async () => {
		fakeStore.setSubmission({
			...VALID_SUBMISSION,
			answers: { ...VALID_SUBMISSION.answers, business_type: 'sole_proprietorship' }
		});

		await expect(
			submitRegistrationToTrustHub({ store: fakeStore.store, twilio: fakeTwilio.twilio }, baseInput)
		).rejects.toBeInstanceOf(TrustHubSubmissionError);
		await expect(
			submitRegistrationToTrustHub({ store: fakeStore.store, twilio: fakeTwilio.twilio }, baseInput)
		).rejects.toMatchObject({ code: 'unsupported_business_type' });
	});

	it('marks the Customer Profile failed and stops when Twilio evaluation is noncompliant', async () => {
		fakeTwilio.twilio.evaluateCustomerProfile = async ({ customerProfileSid }) => ({
			sid: customerProfileSid,
			status: 'noncompliant',
			results: [{ requirementName: 'business_name', passed: false, failureReason: 'missing' }]
		});

		await expect(
			submitRegistrationToTrustHub({ store: fakeStore.store, twilio: fakeTwilio.twilio }, baseInput)
		).rejects.toMatchObject({ code: 'twilio_trust_hub_evaluation_failed' });

		const customerProfile = fakeStore.resources.get(`${REGISTRATION_ID}:customer_profile`);
		expect(customerProfile?.status).toBe('failed');
		expect(customerProfile?.failureReason).toContain('business_name');
		// The Trust Product section must never start once the Customer Profile fails evaluation.
		expect(fakeTwilio.calls).not.toContain('createTrustProduct');
	});

	describe('sole proprietor path', () => {
		beforeEach(() => {
			fakeStore.setSubmission(SOLE_PROPRIETOR_SUBMISSION);
		});

		it('walks the Starter Profile -> Sole Proprietor Trust Bundle -> Brand sequence with brandType SOLE_PROPRIETOR', async () => {
			const brandCalls: Array<{ brandType?: string }> = [];
			const originalCreateBrandRegistration = fakeTwilio.twilio.createBrandRegistration;
			fakeTwilio.twilio.createBrandRegistration = async (input) => {
				brandCalls.push({ brandType: input.brandType });
				return originalCreateBrandRegistration(input);
			};

			const summary = await submitRegistrationToTrustHub(
				{ store: fakeStore.store, twilio: fakeTwilio.twilio },
				baseInput
			);

			expect(summary.customerProfileSid).toMatch(/^BU/);
			expect(summary.trustProductSid).toMatch(/^BU/);
			expect(summary.brandRegistrationSid).toMatch(/^BN/);
			expect(brandCalls).toEqual([{ brandType: 'SOLE_PROPRIETOR' }]);

			// The Sole Proprietor path never creates a business_information end user (no separate business-info
			// object exists in that flow) -- only these five roles.
			const roles: [TrustHubResourceRole, TrustHubResourceStatus][] = [
				['customer_profile', 'submitted'],
				['end_user_authorized_representative', 'submitted'],
				['supporting_document_address', 'submitted'],
				['a2p_trust_product', 'submitted'],
				['end_user_a2p_messaging_profile', 'submitted'],
				['brand_registration', 'created']
			];
			for (const [role, status] of roles) {
				expect(fakeStore.resources.get(`${REGISTRATION_ID}:${role}`)?.status).toBe(status);
			}
			expect(fakeStore.resources.has(`${REGISTRATION_ID}:end_user_business_information`)).toBe(
				false
			);

			expect(fakeTwilio.calls).toContain('createEndUser:starter_customer_profile_information');
			expect(fakeTwilio.calls).toContain('createEndUser:sole_proprietor_information');
			expect(fakeTwilio.calls).not.toContain('createEndUser:customer_profile_business_information');
		});

		it('is idempotent: re-running after full completion makes no further Twilio calls', async () => {
			await submitRegistrationToTrustHub(
				{ store: fakeStore.store, twilio: fakeTwilio.twilio },
				baseInput
			);
			fakeTwilio.calls.length = 0;

			await submitRegistrationToTrustHub(
				{ store: fakeStore.store, twilio: fakeTwilio.twilio },
				baseInput
			);

			expect(fakeTwilio.calls).toEqual([]);
		});
	});
});

describe('syncTrustHubRegistrationStatus', () => {
	let fakeStore: ReturnType<typeof createFakeStore>;
	let fakeTwilio: ReturnType<typeof createFakeTwilio>;

	beforeEach(async () => {
		fakeStore = createFakeStore();
		fakeTwilio = createFakeTwilio();
		// A submitted Brand is this function's precondition -- get there via the real saga rather than
		// hand-rolling a ledger row, so these tests exercise the same shape Stage 9B actually produces.
		await submitRegistrationToTrustHub(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			baseInput
		);
		fakeTwilio.calls.length = 0;
	});

	it('rejects a registration with no attested submission', async () => {
		fakeStore.setSubmission(null);
		await expect(
			syncTrustHubRegistrationStatus(
				{ store: fakeStore.store, twilio: fakeTwilio.twilio },
				{ registrationId: REGISTRATION_ID }
			)
		).rejects.toMatchObject({ code: 'no_submission' });
	});

	it('rejects a registration that was never submitted to Twilio', async () => {
		const freshStore = createFakeStore();
		await expect(
			syncTrustHubRegistrationStatus(
				{ store: freshStore.store, twilio: fakeTwilio.twilio },
				{ registrationId: REGISTRATION_ID }
			)
		).rejects.toMatchObject({ code: 'not_submitted' });
	});

	it('leaves the registration under review while the Brand is still pending, and never checks for a Campaign', async () => {
		fakeTwilio.twilio.fetchBrandRegistration = async (sid) => ({
			sid,
			status: 'IN_REVIEW',
			failureReason: null
		});

		const result = await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);

		expect(result).toMatchObject({
			brandStatus: 'IN_REVIEW',
			campaignStatus: null,
			registrationStatus: 'under_review'
		});
		expect(fakeStore.registrationChecks).toHaveLength(1);
		expect(fakeStore.registrationOutcomes).toHaveLength(0);
		expect(fakeTwilio.calls).not.toContain('createCampaign');
	});

	it('marks the registration action_needed with a sanitized reason when the Brand fails', async () => {
		fakeTwilio.twilio.fetchBrandRegistration = async (sid) => ({
			sid,
			status: 'FAILED',
			failureReason: 'invalid_address'
		});

		const result = await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);

		expect(result.registrationStatus).toBe('action_needed');
		expect(fakeStore.registrationOutcomes).toEqual([
			{ registrationId: REGISTRATION_ID, status: 'action_needed', requiredFixes: 'invalid_address' }
		]);
		expect(fakeStore.resources.get(`${REGISTRATION_ID}:brand_registration`)?.status).toBe('failed');
	});

	it('refuses to register a Campaign when the organization has no Messaging Service yet', async () => {
		fakeStore.setMessagingServiceSid(null);
		await expect(
			syncTrustHubRegistrationStatus(
				{ store: fakeStore.store, twilio: fakeTwilio.twilio },
				{ registrationId: REGISTRATION_ID }
			)
		).rejects.toMatchObject({ code: 'no_messaging_service' });
	});

	it("creates the Campaign from the contractor's own attested messaging answers once the Brand is approved", async () => {
		const createCalls: Array<{
			description: string;
			messageSamples: string[];
			usAppToPersonUsecase: string;
		}> = [];
		fakeTwilio.twilio.createCampaign = async (input) => {
			createCalls.push(input);
			return { sid: 'QE'.padEnd(34, '0'), status: 'PENDING', failureReason: null };
		};

		const result = await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);

		expect(createCalls).toEqual([
			{
				messagingServiceSid: 'MG'.padEnd(34, '1'),
				brandRegistrationSid: expect.stringMatching(/^BN/),
				description: VALID_SUBMISSION.answers.messaging.description,
				messageFlow: expect.stringContaining(
					VALID_SUBMISSION.answers.messaging.consent_description
				),
				messageSamples: VALID_SUBMISSION.answers.messaging.sample_messages,
				usAppToPersonUsecase: 'CUSTOMER_CARE',
				// Neither sample message in VALID_SUBMISSION mentions a link or a phone number.
				hasEmbeddedLinks: false,
				hasEmbeddedPhone: false
			}
		]);
		expect(result.registrationStatus).toBe('under_review');
		expect(fakeStore.resources.get(`${REGISTRATION_ID}:campaign`)?.status).toBe('submitted');
	});

	it('detects an embedded link from a sample message even when it is a merge-field placeholder, not a real URL', async () => {
		fakeStore.setSubmission({
			...VALID_SUBMISSION,
			answers: {
				...VALID_SUBMISSION.answers,
				messaging: {
					...VALID_SUBMISSION.answers.messaging,
					sample_messages: [
						'Hi {FirstName}, your invoice is ready. Pay securely here: {PaymentLink}',
						'Reply STOP to opt out of these updates any time.'
					]
				}
			}
		});
		const createCalls: Array<{ hasEmbeddedLinks: boolean; hasEmbeddedPhone: boolean }> = [];
		fakeTwilio.twilio.createCampaign = async (input) => {
			createCalls.push(input);
			return { sid: 'QE'.padEnd(34, '0'), status: 'PENDING', failureReason: null };
		};

		await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);

		expect(createCalls[0]).toMatchObject({ hasEmbeddedLinks: true, hasEmbeddedPhone: false });
	});

	it('uses the Sole Proprietor use case for a sole-proprietor registration', async () => {
		const soleProprietorFakeStore = createFakeStore();
		soleProprietorFakeStore.setSubmission(SOLE_PROPRIETOR_SUBMISSION);
		await submitRegistrationToTrustHub(
			{ store: soleProprietorFakeStore.store, twilio: fakeTwilio.twilio },
			baseInput
		);
		fakeTwilio.calls.length = 0;
		const createCalls: Array<{ usAppToPersonUsecase: string }> = [];
		fakeTwilio.twilio.createCampaign = async (input) => {
			createCalls.push(input);
			return { sid: 'QE'.padEnd(34, '0'), status: 'PENDING', failureReason: null };
		};

		await syncTrustHubRegistrationStatus(
			{ store: soleProprietorFakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);

		expect(createCalls[0].usAppToPersonUsecase).toBe('SOLE_PROPRIETOR');
	});

	it('approves the registration once the Campaign is verified, and never creates a second Campaign', async () => {
		// First sync creates the Campaign (PENDING); second sync fetches it and finds it VERIFIED.
		await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);
		fakeTwilio.calls.length = 0;

		const result = await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);

		expect(fakeTwilio.calls).toEqual(['fetchBrandRegistration', 'fetchCampaign']);
		expect(result.registrationStatus).toBe('approved');
		expect(fakeStore.registrationOutcomes).toEqual([
			{
				registrationId: REGISTRATION_ID,
				status: 'approved',
				providerOutcome: 'Twilio approved this business for SMS (Brand and Campaign both verified).'
			}
		]);
		expect(fakeStore.resources.get(`${REGISTRATION_ID}:campaign`)?.status).toBe('approved');
	});

	it('marks the registration action_needed with a sanitized reason when the Campaign fails', async () => {
		await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);
		fakeTwilio.twilio.fetchCampaign = async ({ campaignSid }) => ({
			sid: campaignSid,
			status: 'FAILED',
			failureReason: 'carrier rejected: inconsistent sample messages'
		});

		const result = await syncTrustHubRegistrationStatus(
			{ store: fakeStore.store, twilio: fakeTwilio.twilio },
			{ registrationId: REGISTRATION_ID }
		);

		expect(result.registrationStatus).toBe('action_needed');
		expect(fakeStore.registrationOutcomes.at(-1)).toEqual({
			registrationId: REGISTRATION_ID,
			status: 'action_needed',
			requiredFixes: 'carrier rejected: inconsistent sample messages'
		});
	});
});
