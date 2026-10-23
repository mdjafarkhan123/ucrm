import { describe, expect, it, vi } from 'vitest';
import {
	sendTollfreeCheck,
	syncTollfreeCheck,
	tollfreeVerificationForm,
	TollfreeCheckError,
	type TollfreeCheckDeps
} from './sms-tollfree-verification';
import type {
	StoredTollfreeCheck,
	TollfreeCheckOutcome,
	TollfreeCheckStatus,
	TollfreeCheckStore
} from './sms-tollfree-verification-store';
import { TwilioRegulatoryError } from './twilio-regulatory';
import type { TollfreeVerification, TwilioTollfreeClient } from './twilio-tollfree';
import {
	smsTollfreeAnswersSchema,
	type SmsTollfreeAnswers
} from '$lib/server/validation/communications-sms-tollfree.schema';

const SID = 'HH' + 'a'.repeat(32);
const NEW_SID = 'HH' + 'b'.repeat(32);
const PHONE_SID = 'PN' + 'c'.repeat(32);
const ACCOUNT = { subaccountSid: 'AC' + 'd'.repeat(32), authToken: 'token' };

const answers: SmsTollfreeAnswers = {
	business: {
		legal_business_name: 'Raad LTD',
		business_type: 'limited_liability_company',
		business_registration_id_type: 'ein',
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
			description: 'Job updates, quotes and invoices for our contracting customers.',
			consent_method: 'website_form',
			consent_description:
				'Customers tick a box on our booking form agreeing to texts about their job.',
			sample_messages: [
				'Raad LTD: your quote is ready. Reply STOP to opt out.',
				'Raad LTD: your job is booked for tomorrow at 9am.'
			],
			privacy_policy_url: 'https://raad.example.com/privacy',
			terms_url: undefined,
			estimated_monthly_messages: '500_2000'
		}
	},
	opt_in_image_urls: ['https://app.example.com/optin/1.png']
};

function verification(overrides: Partial<TollfreeVerification> = {}): TollfreeVerification {
	return {
		sid: SID,
		status: 'PENDING_REVIEW',
		rejectionReason: null,
		errorCode: null,
		editAllowed: null,
		editExpiration: null,
		...overrides
	};
}

function setup(
	options: { status?: TollfreeCheckStatus; sid?: string | null; claim?: boolean } = {}
) {
	const check: StoredTollfreeCheck = {
		id: 'check-1',
		organizationId: 'org-1',
		senderIdentityId: 'sender-1',
		status: options.status ?? 'draft',
		answers: answers as unknown as Record<string, unknown>,
		revision: 3,
		providerVerificationSid: options.sid ?? null,
		submittedAt: null
	};
	const finished: TollfreeCheckOutcome[] = [];
	const recorded: TollfreeCheckOutcome[] = [];
	const events: string[] = [];
	const savedSids: (string | null)[] = [];
	const store: TollfreeCheckStore = {
		get: vi.fn(async () => ({
			check,
			number: { phoneNumber: '+18335550199', phoneNumberSid: PHONE_SID }
		})),
		claimSending: vi.fn(async () =>
			options.claim === false ? null : { token: 'tok', previousStatus: check.status }
		),
		saveProviderSid: vi.fn(async (_id, _token, sid) => {
			savedSids.push(sid);
		}),
		finishSending: vi.fn(async (_id, _token, outcome) => {
			finished.push(outcome);
		}),
		recordOutcome: vi.fn(async (_id, outcome) => {
			recorded.push(outcome);
		}),
		recordEvent: vi.fn(async (input) => {
			events.push(input.action);
		}),
		listUnderReview: vi.fn(async () => []),
		findByProviderSid: vi.fn(async () => null)
	};
	const twilio: TwilioTollfreeClient = {
		create: vi.fn(async () => verification({ sid: NEW_SID })),
		update: vi.fn(async () => verification({ status: 'PENDING_REVIEW' })),
		fetch: vi.fn(async () => verification()),
		findForNumber: vi.fn(async () => null),
		remove: vi.fn(async () => undefined)
	};
	const switchOnNumbers = vi.fn(async () => 1);
	const deps: TollfreeCheckDeps = {
		store,
		twilio,
		existingSubaccount: async () => ACCOUNT,
		notificationEmail: () => 'ops@uplift.example.com',
		switchOnNumbers,
		now: () => new Date('2026-10-22T12:00:00Z')
	};
	const send = () =>
		sendTollfreeCheck(deps, {
			organizationId: 'org-1',
			verificationId: 'check-1',
			expectedRevision: 3,
			actorUserId: 'user-1'
		});
	return { deps, store, twilio, finished, recorded, events, savedSids, switchOnNumbers, send };
}

describe('tollfreeVerificationForm', () => {
	it("describes the business itself from its own answers, in Twilio's fields", () => {
		const form = tollfreeVerificationForm(answers, {
			phoneNumberSid: PHONE_SID,
			notificationEmail: 'ops@uplift.example.com',
			externalReferenceId: 'check-1'
		});
		expect(form).toMatchObject({
			TollfreePhoneNumberSid: PHONE_SID,
			BusinessName: 'Raad LTD',
			BusinessType: 'PRIVATE_PROFIT',
			BusinessRegistrationNumber: '12-3456789',
			BusinessRegistrationAuthority: 'EIN',
			BusinessRegistrationCountry: 'US',
			BusinessContactEmail: 'owner@raad.example.com',
			UseCaseCategories: ['CUSTOMER_CARE', 'ACCOUNT_NOTIFICATIONS'],
			OptInType: 'WEB_FORM',
			OptInImageUrls: ['https://app.example.com/optin/1.png'],
			MessageVolume: '10,000',
			ProductionMessageSample: 'Raad LTD: your quote is ready. Reply STOP to opt out.',
			PrivacyPolicyUrl: 'https://raad.example.com/privacy',
			ExternalReferenceId: 'check-1'
		});
		expect(form).not.toHaveProperty('BusinessStreetAddress2');
		expect(form).not.toHaveProperty('TermsAndConditionsUrl');
	});

	it('sends a sole proprietor with no registration number as one, without registration fields', () => {
		const form = tollfreeVerificationForm(
			{
				...answers,
				business: {
					...answers.business,
					business_type: 'sole_proprietorship',
					business_registration_id: undefined,
					business_registration_id_type: undefined
				}
			},
			{ phoneNumberSid: PHONE_SID, notificationEmail: 'ops@x.com', externalReferenceId: 'c' }
		);
		expect(form.BusinessType).toBe('SOLE_PROPRIETOR');
		expect(form).not.toHaveProperty('BusinessRegistrationNumber');
	});

	it('refuses answers with no opt-in picture or an agreement method Twilio has no name for', () => {
		const result = smsTollfreeAnswersSchema.safeParse({
			business: {
				...answers.business,
				messaging: { ...answers.business.messaging, consent_method: 'other' }
			},
			opt_in_image_urls: []
		});
		expect(result.success).toBe(false);
		const paths = result.error!.issues.map((issue) => issue.path.join('.'));
		expect(paths).toContain('opt_in_image_urls');
		expect(paths).toContain('business.messaging.consent_method');
	});

	it('accepts the form without the contact title, position or number type Twilio never reads', () => {
		const { business_title, job_position, ...contact } = answers.business.authorized_representative;
		void business_title;
		void job_position;
		const result = smsTollfreeAnswersSchema.safeParse({
			...answers,
			business: {
				...answers.business,
				business_registration_id_type: undefined,
				authorized_representative: contact
			}
		});
		expect(result.success).toBe(true);
		const form = tollfreeVerificationForm(result.data!, {
			phoneNumberSid: PHONE_SID,
			notificationEmail: 'ops@x.com',
			externalReferenceId: 'c'
		});
		expect(form.BusinessRegistrationAuthority).toBe('EIN');
	});

	it('files the number under the country it was registered in, not the address', () => {
		const form = tollfreeVerificationForm(
			{
				...answers,
				business: {
					...answers.business,
					business_registration_id_type: undefined,
					business_registration_country: 'CA'
				}
			},
			{ phoneNumberSid: PHONE_SID, notificationEmail: 'ops@x.com', externalReferenceId: 'c' }
		);
		expect(form.BusinessRegistrationCountry).toBe('CA');
		expect(form.BusinessRegistrationAuthority).toBe('OTHER');
		expect(form.BusinessCountry).toBe('US');
	});

	it('refuses a business without a registration number, and a sole trader outside the US or Canada', () => {
		const business = smsTollfreeAnswersSchema.safeParse({
			...answers,
			business: { ...answers.business, business_registration_id: '' }
		});
		expect(business.error!.issues.map((issue) => issue.path.join('.'))).toEqual([
			'business.business_registration_id'
		]);
		const abroad = smsTollfreeAnswersSchema.safeParse({
			...answers,
			business: {
				...answers.business,
				business_type: 'sole_proprietorship',
				business_registration_id: '',
				business_address: { ...answers.business.business_address, country_code: 'GB' }
			}
		});
		expect(abroad.error!.issues.map((issue) => issue.path.join('.'))).toEqual([
			'business.business_address.country_code'
		]);
	});
});

describe('sendTollfreeCheck', () => {
	it('makes a new check, keeps its record at once and waits for carriers', async () => {
		const run = setup();
		await expect(run.send()).resolves.toEqual({ status: 'under_review' });
		expect(run.twilio.findForNumber).toHaveBeenCalledWith(ACCOUNT, PHONE_SID);
		expect(run.twilio.create).toHaveBeenCalledTimes(1);
		expect(run.savedSids).toEqual([NEW_SID]);
		expect(run.finished).toEqual([
			expect.objectContaining({
				status: 'under_review',
				providerVerificationSid: NEW_SID,
				submitted: true,
				decided: false
			})
		]);
		expect(run.events).toEqual(['sent']);
	});

	it('finds the check made before a dropped connection instead of making a second one', async () => {
		const run = setup();
		vi.mocked(run.twilio.findForNumber).mockResolvedValue(verification({ status: 'IN_REVIEW' }));
		await expect(run.send()).resolves.toEqual({ status: 'under_review' });
		expect(run.twilio.create).not.toHaveBeenCalled();
		expect(run.savedSids).toEqual([SID]);
	});

	it('edits a turned-down check in place while Twilio still allows it', async () => {
		const run = setup({ status: 'needs_fix', sid: SID });
		vi.mocked(run.twilio.fetch).mockResolvedValue(
			verification({
				status: 'TWILIO_REJECTED',
				editAllowed: true,
				editExpiration: '2026-10-28T00:00:00Z'
			})
		);
		await expect(run.send()).resolves.toEqual({ status: 'under_review' });
		const [, sid, form] = vi.mocked(run.twilio.update).mock.calls[0];
		expect(sid).toBe(SID);
		expect(form).not.toHaveProperty('TollfreePhoneNumberSid');
		expect(form.EditReason).toBeTruthy();
		expect(run.twilio.create).not.toHaveBeenCalled();
		expect(run.twilio.remove).not.toHaveBeenCalled();
	});

	it('deletes a turned-down check that can no longer be edited and sends a new one', async () => {
		const run = setup({ status: 'needs_fix', sid: SID });
		vi.mocked(run.twilio.fetch).mockResolvedValue(
			verification({
				status: 'TWILIO_REJECTED',
				editAllowed: true,
				editExpiration: '2026-10-20T00:00:00Z'
			})
		);
		await expect(run.send()).resolves.toEqual({ status: 'under_review' });
		expect(run.twilio.remove).toHaveBeenCalledWith(ACCOUNT, SID);
		expect(run.twilio.create).toHaveBeenCalledTimes(1);
		expect(run.savedSids).toEqual([SID, null, NEW_SID]);
		expect(run.events).toEqual(['replaced', 'sent']);
	});

	it("keeps Twilio's reason when it refuses what was sent", async () => {
		const run = setup();
		vi.mocked(run.twilio.create).mockRejectedValue(
			new TwilioRegulatoryError(
				'refused',
				400,
				'twilio_regulatory_rejected',
				false,
				'21608',
				'Opt-in image URL is not reachable.'
			)
		);
		await expect(run.send()).resolves.toEqual({ status: 'needs_fix' });
		expect(run.finished).toEqual([
			{
				status: 'needs_fix',
				failureReason: 'Opt-in image URL is not reachable.',
				errorCode: 21608
			}
		]);
		expect(run.events).toEqual(['refused']);
	});

	it('puts the check back as it was when Twilio cannot be reached', async () => {
		const run = setup({ status: 'needs_fix' });
		vi.mocked(run.twilio.findForNumber).mockRejectedValue(
			new TwilioRegulatoryError('down', null, 'twilio_regulatory_unknown', true)
		);
		await expect(run.send()).rejects.toMatchObject({ code: 'provider_unavailable' });
		expect(run.finished).toEqual([{ status: 'needs_fix' }]);
	});

	it('refuses a check that changed or is already being sent', async () => {
		const run = setup({ claim: false });
		await expect(run.send()).rejects.toBeInstanceOf(TollfreeCheckError);
		expect(run.twilio.create).not.toHaveBeenCalled();
	});

	it('sends nothing while answers are missing', async () => {
		const run = setup();
		vi.mocked(run.store.get).mockResolvedValue({
			check: {
				id: 'check-1',
				organizationId: 'org-1',
				senderIdentityId: 'sender-1',
				status: 'draft',
				answers: { business: answers.business, opt_in_image_urls: [] },
				revision: 3,
				providerVerificationSid: null,
				submittedAt: null
			},
			number: { phoneNumber: '+18335550199', phoneNumberSid: PHONE_SID }
		});
		await expect(run.send()).rejects.toMatchObject({ code: 'incomplete' });
		expect(run.twilio.findForNumber).not.toHaveBeenCalled();
		expect(run.finished).toEqual([{ status: 'draft' }]);
	});
});

describe('syncTollfreeCheck', () => {
	const sync = (run: ReturnType<typeof setup>) =>
		syncTollfreeCheck(run.deps, { organizationId: 'org-1', verificationId: 'check-1' });

	it('records an approval and switches the number on', async () => {
		const run = setup({ status: 'under_review', sid: SID });
		vi.mocked(run.twilio.fetch).mockResolvedValue(verification({ status: 'TWILIO_APPROVED' }));
		await expect(sync(run)).resolves.toEqual({ status: 'approved', changed: true });
		expect(run.recorded[0]).toMatchObject({ status: 'approved', decided: true });
		expect(run.switchOnNumbers).toHaveBeenCalledWith('org-1');
		expect(run.events).toEqual(['approved']);
	});

	it("records carriers' reason and how long a fix may be sent", async () => {
		const run = setup({ status: 'under_review', sid: SID });
		vi.mocked(run.twilio.fetch).mockResolvedValue(
			verification({
				status: 'TWILIO_REJECTED',
				rejectionReason: 'Business email must use an official domain.',
				errorCode: 30482,
				editAllowed: true,
				editExpiration: '2026-10-28T00:00:00Z'
			})
		);
		await expect(sync(run)).resolves.toEqual({ status: 'needs_fix', changed: true });
		expect(run.recorded[0]).toMatchObject({
			status: 'needs_fix',
			failureReason: 'Business email must use an official domain.',
			errorCode: 30482,
			editAllowed: true,
			editExpiresAt: '2026-10-28T00:00:00Z'
		});
		expect(run.switchOnNumbers).not.toHaveBeenCalled();
	});

	it('leaves a check still with carriers unchanged and a draft alone', async () => {
		const waiting = setup({ status: 'under_review', sid: SID });
		await expect(sync(waiting)).resolves.toEqual({ status: 'under_review', changed: false });
		expect(waiting.events).toEqual([]);

		const draft = setup({ status: 'draft' });
		await expect(sync(draft)).resolves.toEqual({ skipped: 'draft' });
		expect(draft.twilio.fetch).not.toHaveBeenCalled();
	});
});
