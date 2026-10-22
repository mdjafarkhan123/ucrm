import { describe, expect, it, vi } from 'vitest';
import {
	paperworkProblems,
	prefillAnswers,
	resolveDocumentChoices,
	type PaperworkStatus
} from '$lib/communications/number-paperwork';
import {
	buildPaperworkForm,
	documentAttributes,
	endUserAttributes,
	PaperworkError,
	sendNumberPaperwork,
	syncNumberPaperwork,
	type NumberPaperworkDeps
} from './sms-number-paperwork';
import type {
	NumberPaperworkStore,
	PaperworkOutcome,
	StoredPaperwork,
	StoredPaperworkDocument,
	StoredPaperworkFile
} from './sms-number-paperwork-store';
import type { NumberRegulation, RequirementField } from './twilio-country-catalog';
import {
	readEvaluation,
	TwilioRegulatoryError,
	type BundleStatus,
	type TwilioRegulatoryClient
} from './twilio-regulatory';

const ORG = '11111111-1111-4111-8111-111111111111';
const ACTOR = '22222222-2222-4222-8222-222222222222';
const SET_ID = '33333333-3333-4333-8333-333333333333';
const FILE_ID = '44444444-4444-4444-8444-444444444444';
// Built at run time so secret scanners never see an account-ID-shaped literal.
const ACCOUNT = { subaccountSid: ['A', 'C', 'f'.repeat(32)].join(''), authToken: 'fake-value' };
const sid = (prefix: string, n: number) => prefix + n.toString(16).padStart(32, '0');

function field(name: string, extra: Partial<RequirementField> = {}): RequirementField {
	return {
		name,
		label: name,
		description: '',
		required: true,
		choices: null,
		pattern: null,
		mustMatch: null,
		...extra
	};
}

// Shaped like Twilio's live answers (2026-10-22) for a UK mobile business and an Australian one.
const GB: NumberRegulation = {
	regulationSid: sid('RN', 1),
	label: 'United Kingdom: Mobile - Business',
	countryCode: 'GB',
	numberType: 'mobile',
	endUserType: 'business',
	endUser: [
		{
			requirementName: 'business_info',
			label: 'Business',
			endUserType: 'business',
			fields: [
				field('business_name'),
				field('business_registration_identifier', {
					choices: ['UK:CRN', 'US:EIN', 'CA:CBN', 'AU:ACN', 'OTHER']
				}),
				field('business_registration_number'),
				field('business_website'),
				field('first_name'),
				field('last_name'),
				field('phone_number', { pattern: '^\\+[1-9]\\d{1,14}$' }),
				field('email', { pattern: '^\\S+@\\S+\\.\\S+$' }),
				field('business_identity', { choices: ['DIRECT_CUSTOMER', 'INDEPENDENT_SOFTWARE_VENDOR'] }),
				field('is_subassigned', { choices: ['YES', 'NO'] }),
				field('comments', { required: false })
			]
		}
	],
	documents: [
		{
			requirementName: 'business_address',
			label: 'Business address',
			description: 'May be anywhere in the world; a PO Box is not acceptable.',
			acceptedDocuments: [
				{
					documentType: 'business_address',
					label: 'Business address',
					fields: [field('address_sids')]
				}
			]
		}
	]
};

const AU: NumberRegulation = {
	regulationSid: sid('RN', 2),
	label: 'Australia: Mobile - Business',
	countryCode: 'AU',
	numberType: 'mobile',
	endUserType: 'business',
	endUser: [
		{
			requirementName: 'business_info',
			label: 'Business',
			endUserType: 'business',
			fields: [field('business_name')]
		}
	],
	documents: [
		{
			requirementName: 'business_name_info',
			label: 'Business Name',
			description: '',
			acceptedDocuments: [
				{
					documentType: 'commercial_registrar_excerpt',
					label: 'Commercial register',
					fields: [field('business_name', { mustMatch: 'business_name' })]
				}
			]
		},
		{
			requirementName: 'business_address_proof_of_address_info',
			label: 'Address',
			description: 'May be anywhere in the world',
			acceptedDocuments: [
				{
					documentType: 'commercial_registrar_excerpt',
					label: 'Register',
					fields: [field('address_sids')]
				},
				{ documentType: 'utility_bill', label: 'Utility bill', fields: [field('address_sids')] }
			]
		},
		{
			requirementName: 'business_id_no_info',
			label: 'Business ID',
			description: '',
			acceptedDocuments: [
				{
					documentType: 'commercial_registrar_excerpt',
					label: 'Commercial register',
					fields: [field('document_number')]
				}
			]
		}
	]
};

const GB_ANSWERS = {
	business_name: 'Road LTD',
	business_registration_identifier: 'UK:CRN',
	business_registration_number: '01234567',
	business_website: 'https://road.example',
	first_name: 'Jane',
	last_name: 'Road',
	phone_number: '+447700900123',
	email: 'jane@road.example'
};

const ADDRESS = {
	customer_name: 'Road LTD',
	street: '1 High Street',
	street_secondary: '',
	city: 'London',
	region: 'London',
	postal_code: 'SW1A 1AA',
	country_code: 'GB'
};

function paperwork(overrides: Partial<StoredPaperwork> = {}): StoredPaperwork {
	return {
		id: SET_ID,
		organizationId: ORG,
		countryCode: 'GB',
		numberType: 'mobile',
		endUserType: 'business',
		status: 'draft',
		answers: GB_ANSWERS,
		address: ADDRESS,
		documentChoices: {},
		revision: 3,
		regulationSid: null,
		providerAddressSid: null,
		providerEndUserSid: null,
		providerBundleSid: null,
		providerStatus: null,
		failureReason: null,
		fixes: [],
		validUntil: null,
		submittedAt: null,
		decidedAt: null,
		updatedAt: '2026-10-22T12:00:00Z',
		createdAt: '2026-10-22T12:00:00Z',
		...overrides
	};
}

function documentRow(overrides: Partial<StoredPaperworkDocument> = {}): StoredPaperworkDocument {
	return {
		id: '55555555-5555-4555-8555-555555555555',
		documentType: 'business_address',
		protectedDocumentId: null,
		fields: {},
		providerDocumentSid: null,
		providerProtectedDocumentId: null,
		providerFields: null,
		providerStatus: null,
		failureReason: null,
		...overrides
	};
}

function fakeStore(
	initial: StoredPaperwork,
	documents: StoredPaperworkDocument[],
	file?: StoredPaperworkFile
) {
	let set = { ...initial };
	let claim: string | null = null;
	const events: string[] = [];
	const outcomes: PaperworkOutcome[] = [];
	const store: NumberPaperworkStore = {
		get: async () => ({ paperwork: { ...set }, documents: documents.map((row) => ({ ...row })) }),
		claimSending: async (_org, _id, revision) => {
			if (revision !== set.revision || (set.status !== 'draft' && set.status !== 'needs_fix'))
				return null;
			const previousStatus = set.status;
			claim = crypto.randomUUID();
			set = { ...set, status: 'sending' };
			return { paperwork: { ...set }, token: claim, previousStatus };
		},
		saveProvider: async (_id, token, patch) => {
			expect(token).toBe(claim);
			set = { ...set, ...patch };
		},
		saveDocumentProvider: async (documentId, patch) => {
			const row = documents.find((candidate) => candidate.id === documentId)!;
			Object.assign(row, patch);
		},
		finishSending: async (_id, token, outcome) => {
			expect(token).toBe(claim);
			claim = null;
			outcomes.push(outcome);
			set = {
				...set,
				status: outcome.status,
				failureReason: outcome.failureReason ?? set.failureReason
			};
		},
		recordOutcome: async (_id, outcome) => {
			outcomes.push(outcome);
			set = { ...set, status: outcome.status };
		},
		recordDocumentReview: async (documentId, review) => {
			Object.assign(
				documents.find((candidate) => candidate.id === documentId)!,
				review
			);
		},
		recordEvent: async (input) => {
			events.push(input.action);
		},
		findByBundleSid: async () => null,
		listUnderReview: async () => [],
		findApproved: async () => null,
		readFile: async () => file ?? null,
		scheduleFileDeletion: vi.fn(async () => undefined)
	};
	return { store, events, outcomes, current: () => set };
}

function fakeTwilio(
	options: {
		evaluation?: {
			compliant: boolean;
			problems: [] | ReturnType<typeof readEvaluation>['problems'];
		};
		bundleStatus?: BundleStatus;
	} = {}
) {
	let n = 0;
	const calls: string[] = [];
	const assigned: { sid: string; objectSid: string }[] = [];
	const twilio: TwilioRegulatoryClient = {
		createAddress: async () => (calls.push('address'), { sid: sid('AD', ++n) }),
		updateAddress: async (_a, s) => (calls.push('address-update'), { sid: s }),
		createEndUser: async () => (calls.push('end-user'), { sid: sid('IT', ++n) }),
		updateEndUser: async (_a, s) => (calls.push('end-user-update'), { sid: s }),
		createSupportingDocument: async (_a, input) => (
			calls.push(`document:${input.type}${input.file ? '+file' : ''}`),
			{ sid: sid('RD', ++n), status: 'draft', failureReason: null }
		),
		fetchSupportingDocument: async (_a, s) => ({
			sid: s,
			status: 'twilio-rejected',
			failureReason: 'The document is blurry.'
		}),
		createBundle: async () => (
			calls.push('bundle'),
			{ sid: sid('BU', ++n), status: 'draft', validUntil: null }
		),
		fetchBundle: async (_a, s) => (
			calls.push('bundle-fetch'),
			{ sid: s, status: options.bundleStatus ?? 'draft', validUntil: null }
		),
		updateBundleStatus: async (_a, s, status) => (
			calls.push(`bundle:${status}`),
			{ sid: s, status, validUntil: null }
		),
		listItemAssignments: async () => [...assigned],
		createItemAssignment: async (_a, _b, objectSid) => {
			calls.push('assign');
			const item = { sid: sid('BV', ++n), objectSid };
			assigned.push(item);
			return item;
		},
		deleteItemAssignment: async (_a, _b, assignmentSid) => {
			calls.push('unassign');
			assigned.splice(
				assigned.findIndex((item) => item.sid === assignmentSid),
				1
			);
		},
		evaluateBundle: async () => (
			calls.push('evaluate'),
			options.evaluation ?? { compliant: true, problems: [] }
		)
	};
	return { twilio, calls, assigned };
}

function deps(
	store: NumberPaperworkStore,
	twilio: TwilioRegulatoryClient,
	regulation: NumberRegulation | null = GB
): NumberPaperworkDeps {
	return {
		store,
		twilio,
		catalog: { getRegulation: async () => regulation },
		subaccount: async () => ACCOUNT,
		existingSubaccount: async () => ACCOUNT,
		readFileBytes: async () => new Uint8Array([37, 80, 68, 70]),
		statusCallbackUrl: () => 'https://app.example/api/webhooks/twilio/number-paperwork',
		notificationEmail: () => 'ops@example.com'
	};
}

const send = (d: NumberPaperworkDeps) =>
	sendNumberPaperwork(d, {
		organizationId: ORG,
		paperworkId: SET_ID,
		expectedRevision: 3,
		actorUserId: ACTOR
	});

describe('the paperwork form', () => {
	it('asks only what the business answers, grouped, and never Uplift’s own answers', () => {
		const form = buildPaperworkForm(GB, {
			countryCode: 'GB',
			numberType: 'mobile',
			endUserType: 'business'
		});
		expect(form.businessFields.map((f) => f.name)).toEqual([
			'business_name',
			'business_registration_identifier',
			'business_registration_number',
			'business_website'
		]);
		expect(form.personFields.map((f) => f.name)).toEqual([
			'first_name',
			'last_name',
			'phone_number',
			'email'
		]);
		expect(form.needsAddress).toBe(true);
		expect(form.addressRule).toContain('PO Box');
		expect(form.requirements[0].kinds[0]).toMatchObject({ needsFile: false, fields: [] });
	});

	it('lets one document prove several things, and copies what must match the answers', () => {
		const form = buildPaperworkForm(AU, {
			countryCode: 'AU',
			numberType: 'mobile',
			endUserType: 'business'
		});
		const choices = resolveDocumentChoices(form.requirements, {});
		expect(new Set(Object.values(choices))).toEqual(new Set(['commercial_registrar_excerpt']));
		const register = form.requirements[2].kinds[0];
		expect(register.fields.map((f) => f.name)).toEqual(['document_number']);
		expect(form.requirements[0].kinds[0].fields).toEqual([]);
		expect(
			documentAttributes(AU, 'commercial_registrar_excerpt', {
				answers: { business_name: 'Road Pty' },
				fields: { document_number: '123 456 789' },
				addressSid: sid('AD', 9)
			})
		).toEqual({
			business_name: 'Road Pty',
			address_sids: [sid('AD', 9)],
			document_number: '123 456 789'
		});
	});

	it('fills answers in from the texting registration', () => {
		const form = buildPaperworkForm(GB, {
			countryCode: 'GB',
			numberType: 'mobile',
			endUserType: 'business'
		});
		const answers = prefillAnswers(form, {
			legal_business_name: 'Road LTD',
			website_url: 'https://road.example',
			business_address: { country_code: 'ca' },
			authorized_representative: { first_name: 'Jafar', email: 'jafar@road.example' }
		});
		expect(answers).toEqual({
			business_name: 'Road LTD',
			business_registration_identifier: 'CA:CBN',
			business_website: 'https://road.example',
			first_name: 'Jafar',
			email: 'jafar@road.example'
		});
	});

	it('sends Uplift’s fixed answers with the business’s own', () => {
		expect(endUserAttributes(GB, GB_ANSWERS)).toMatchObject({
			business_name: 'Road LTD',
			business_identity: 'DIRECT_CUSTOMER',
			is_subassigned: 'YES'
		});
	});

	it('lists what is still missing, step by step', () => {
		const form = buildPaperworkForm(AU, {
			countryCode: 'AU',
			numberType: 'mobile',
			endUserType: 'business'
		});
		const problems = paperworkProblems(form, {
			answers: {},
			address: null,
			documentChoices: {},
			documents: [
				{ documentType: 'commercial_registrar_excerpt', fields: {}, fileState: 'checking' }
			]
		});
		expect(problems.map((p) => `${p.step}:${p.target}`)).toEqual([
			'details:business_name',
			'details:address',
			'documents:document:commercial_registrar_excerpt',
			'documents:document:commercial_registrar_excerpt:document_number'
		]);
		expect(problems[2].reason).toBe('Wait for the file to finish its checks.');
	});
});

describe('sending paperwork', () => {
	it('makes every Twilio record once, checks it, and sends it for review', async () => {
		const { store, events, current } = fakeStore(paperwork(), [documentRow()]);
		const { twilio, calls } = fakeTwilio();
		await expect(send(deps(store, twilio))).resolves.toEqual({ status: 'under_review' });
		expect(calls).toEqual([
			'address',
			'end-user',
			'document:business_address',
			'bundle',
			'assign',
			'assign',
			'evaluate',
			'bundle:pending-review'
		]);
		expect(current()).toMatchObject({ status: 'under_review', regulationSid: GB.regulationSid });
		expect(current().providerBundleSid).toMatch(/^BU/);
		expect(events).toEqual(['sent']);
	});

	it('refuses a set that is incomplete and leaves it as it was', async () => {
		const { store, current } = fakeStore(paperwork({ answers: {} }), [documentRow()]);
		const { twilio, calls } = fakeTwilio();
		const error = await send(deps(store, twilio)).catch((caught) => caught);
		expect(error).toBeInstanceOf(PaperworkError);
		expect(error.code).toBe('incomplete');
		expect(error.problems.length).toBeGreaterThan(0);
		expect(calls).toEqual([]);
		expect(current().status).toBe('draft');
	});

	it('refuses a stale revision or a set already being sent', async () => {
		const { store } = fakeStore(paperwork({ revision: 4 }), [documentRow()]);
		await expect(send(deps(store, fakeTwilio().twilio))).rejects.toMatchObject({
			code: 'not_sendable'
		});
	});

	it('picks up after a dropped connection without making a second set', async () => {
		const { store, current } = fakeStore(paperwork(), [documentRow()]);
		const first = fakeTwilio();
		let failOnce = true;
		const flaky: TwilioRegulatoryClient = {
			...first.twilio,
			evaluateBundle: async (...args) => {
				if (failOnce) {
					failOnce = false;
					throw new TwilioRegulatoryError('lost', null, 'twilio_regulatory_unknown', true);
				}
				return first.twilio.evaluateBundle(...args);
			}
		};
		await expect(send(deps(store, flaky))).rejects.toMatchObject({ code: 'provider_unavailable' });
		expect(current().status).toBe('draft');
		await expect(send(deps(store, flaky))).resolves.toEqual({ status: 'under_review' });
		expect(first.calls.filter((call) => call === 'bundle')).toHaveLength(1);
		expect(first.calls.filter((call) => call === 'end-user')).toHaveLength(1);
		expect(first.calls).toContain('end-user-update');
		// The second send made a fresh address, so the address document was remade and swapped in the bundle.
		expect(first.calls.filter((call) => call === 'unassign')).toHaveLength(1);
		expect(first.assigned).toHaveLength(2);
	});

	it('turns a failed check into fixes on the right step', async () => {
		const { store, current, outcomes } = fakeStore(paperwork(), [documentRow()]);
		const { twilio, calls } = fakeTwilio({
			evaluation: {
				compliant: false,
				problems: [
					{
						requirementName: 'business_info',
						requirementLabel: 'Business',
						field: 'email',
						reason: 'Domain should match'
					},
					{
						requirementName: 'business_address',
						requirementLabel: 'Address',
						field: 'address_sids',
						reason: 'PO Box'
					}
				]
			}
		});
		await expect(send(deps(store, twilio))).resolves.toEqual({ status: 'needs_fix' });
		expect(calls).not.toContain('bundle:pending-review');
		expect(current().status).toBe('needs_fix');
		expect(outcomes.at(-1)?.fixes).toEqual([
			{ step: 'details', target: 'email', label: 'Email', reason: 'Domain should match' },
			{ step: 'details', target: 'address', label: 'Address', reason: 'PO Box' }
		]);
	});

	it('shows Twilio’s own words when it refuses a record', async () => {
		const { store, current } = fakeStore(paperwork(), [documentRow()]);
		const { twilio } = fakeTwilio();
		twilio.createAddress = async () => {
			throw new TwilioRegulatoryError(
				'no',
				400,
				'twilio_regulatory_rejected',
				false,
				'21628',
				'Address not found'
			);
		};
		await expect(send(deps(store, twilio))).resolves.toEqual({ status: 'needs_fix' });
		expect(current()).toMatchObject({ status: 'needs_fix', failureReason: 'Address not found' });
	});

	it('fixes a rejected set on the same bundle, as Twilio asks', async () => {
		const { store } = fakeStore(
			paperwork({
				status: 'needs_fix',
				providerBundleSid: sid('BU', 99),
				providerEndUserSid: sid('IT', 98)
			}),
			[documentRow()]
		);
		const { twilio, calls } = fakeTwilio({ bundleStatus: 'twilio-rejected' });
		await expect(send(deps(store, twilio))).resolves.toEqual({ status: 'under_review' });
		expect(calls).not.toContain('bundle');
		expect(calls).toContain('bundle:draft');
		expect(calls.at(-1)).toBe('bundle:pending-review');
	});

	it('uploads a document file and reuses it when nothing changed', async () => {
		const file: StoredPaperworkFile = {
			id: FILE_ID,
			objectKey: `${ORG}/setup-protected/x-register.pdf`,
			displayName: 'register.pdf',
			mimeType: 'application/pdf',
			sizeBytes: 4,
			state: 'ready',
			problem: null
		};
		const row = documentRow({
			documentType: 'commercial_registrar_excerpt',
			protectedDocumentId: FILE_ID,
			fields: { document_number: '123' }
		});
		const { store } = fakeStore(
			paperwork({
				countryCode: 'AU',
				answers: { business_name: 'Road Pty' },
				address: { ...ADDRESS, country_code: 'AU' }
			}),
			[row],
			file
		);
		const { twilio, calls } = fakeTwilio();
		await send(deps(store, twilio, AU));
		expect(calls).toContain('document:commercial_registrar_excerpt+file');
		expect(row.providerProtectedDocumentId).toBe(FILE_ID);
	});

	it('approves an address-only set at once', async () => {
		const { store, current } = fakeStore(paperwork(), []);
		const { twilio, calls } = fakeTwilio();
		await expect(send(deps(store, twilio, null))).resolves.toEqual({ status: 'approved' });
		expect(calls).toEqual(['address']);
		expect(current().providerAddressSid).toMatch(/^AD/);
	});
});

describe('following Twilio’s review', () => {
	const sync = (d: NumberPaperworkDeps, reason?: string) =>
		syncNumberPaperwork(d, { organizationId: ORG, paperworkId: SET_ID, callbackReason: reason });

	it('marks an approved set and schedules its files for deletion', async () => {
		const { store, events } = fakeStore(
			paperwork({ status: 'under_review', providerBundleSid: sid('BU', 7) }),
			[]
		);
		const { twilio } = fakeTwilio({ bundleStatus: 'twilio-approved' });
		await expect(sync(deps(store, twilio))).resolves.toEqual({ status: 'approved', changed: true });
		expect(store.scheduleFileDeletion).toHaveBeenCalledWith(SET_ID);
		expect(events).toEqual(['approved']);
	});

	it('brings back the reason and each document’s problem on a rejection', async () => {
		const { store, outcomes } = fakeStore(
			paperwork({ status: 'under_review', providerBundleSid: sid('BU', 7) }),
			[documentRow({ documentType: 'utility_bill', providerDocumentSid: sid('RD', 3) })]
		);
		const { twilio } = fakeTwilio({ bundleStatus: 'twilio-rejected' });
		await expect(sync(deps(store, twilio), 'The bill is older than 3 months')).resolves.toEqual({
			status: 'needs_fix',
			changed: true
		});
		expect(outcomes.at(-1)).toMatchObject({
			failureReason: 'The bill is older than 3 months',
			fixes: [
				{ step: 'documents', target: 'document:utility_bill', reason: 'The document is blurry.' }
			]
		});
	});

	it('leaves drafts and sets being sent alone', async () => {
		for (const status of ['draft', 'sending'] as PaperworkStatus[]) {
			const { store } = fakeStore(paperwork({ status, providerBundleSid: sid('BU', 7) }), []);
			await expect(sync(deps(store, fakeTwilio().twilio))).resolves.toEqual({ skipped: status });
		}
	});
});

describe('reading Twilio’s evaluation', () => {
	it('lists each failed field, or the requirement when no field is named', () => {
		const evaluation = readEvaluation({
			status: 'noncompliant',
			results: [
				{ requirement_name: 'business_info', passed: true, fields: [] },
				{
					requirement_name: 'business_info_2',
					requirement_friendly_name: 'Business',
					passed: false,
					fields: [
						{ object_field: 'email', passed: false, failure_reason: 'Bad email' },
						{ object_field: 'business_name', passed: true }
					]
				},
				{
					requirement_name: 'proof',
					friendly_name: 'Proof',
					passed: false,
					failure_reason: 'Missing proof',
					fields: []
				}
			]
		});
		expect(evaluation).toEqual({
			compliant: false,
			problems: [
				{
					requirementName: 'business_info_2',
					requirementLabel: 'Business',
					field: 'email',
					reason: 'Bad email'
				},
				{
					requirementName: 'proof',
					requirementLabel: 'Proof',
					field: null,
					reason: 'Missing proof'
				}
			]
		});
	});
});
