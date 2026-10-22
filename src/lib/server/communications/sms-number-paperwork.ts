import {
	chosenDocumentKinds,
	choiceLabel,
	documentLabel,
	documentNeedsFile,
	fieldKind,
	fieldLabel,
	isAskedEndUserField,
	isPersonField,
	paperworkProblems,
	PLATFORM_ANSWERS,
	resolveDocumentChoices,
	type EndUserType,
	type FormField,
	type FormRequirement,
	type PaperworkFix,
	type PaperworkForm,
	type PaperworkStatus
} from '$lib/communications/number-paperwork';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getServerEnv } from '$lib/server/env';
import { getObjectBytes } from '$lib/server/storage/r2';
import { getSmsCountryCatalog, type SmsCountryCatalog } from './sms-country-catalog';
import { ensureTwilioSubaccount, NumberPurchaseError } from './sms-number-purchase';
import {
	createTwilioProvisioningDeps,
	getSubaccountAccess,
	type SubaccountAccess
} from './twilio-provisioning';
import { getTwilioNumberPaperworkWebhookUrl } from './twilio-webhook';
import type { NumberRegulation, NumberType, RequirementField } from './twilio-country-catalog';
import {
	createSupabaseNumberPaperworkStore,
	type NumberPaperworkStore,
	type StoredPaperwork,
	type StoredPaperworkDocument
} from './sms-number-paperwork-store';
import {
	createTwilioRegulatoryClient,
	TwilioRegulatoryError,
	type BundleEvaluationProblem,
	type SubaccountCredentials,
	type TwilioRegulatoryClient
} from './twilio-regulatory';

// Number paperwork (Stage 10 Part 3, docs/global-sms-behavior-contract.md § Part 3): the form a country asks
// for, sending it to Twilio as a Regulatory Bundle, and following Twilio's review.
//
// Sending follows Twilio's own sequence -- address, End-User, Supporting Documents, Bundle, Item Assignments,
// Evaluation, then `pending-review` -- and records each Twilio record as soon as it exists, so a send that
// drops part-way picks up from what Twilio already has instead of making a second set. A rejected set is fixed
// and sent again on the same Bundle, as Twilio asks ("do not create a new bundle").

export type PaperworkErrorCode = 'not_sendable' | 'incomplete' | 'provider_unavailable';

export class PaperworkError extends Error {
	constructor(
		public readonly code: PaperworkErrorCode,
		message: string,
		public readonly problems: PaperworkFix[] = []
	) {
		super(message);
		this.name = 'PaperworkError';
	}
}

export type NumberPaperworkDeps = {
	store: NumberPaperworkStore;
	catalog: Pick<SmsCountryCatalog, 'getRegulation'>;
	twilio: TwilioRegulatoryClient;
	/** The business's Twilio subaccount, set up first if it has none. */
	subaccount(organizationId: string): Promise<SubaccountCredentials>;
	/** The subaccount if it exists; never sets one up. */
	existingSubaccount(organizationId: string): Promise<SubaccountCredentials | null>;
	readFileBytes(objectKey: string): Promise<Uint8Array>;
	statusCallbackUrl(): string;
	/** Twilio emails status changes here; Uplift's own monitored address. */
	notificationEmail(): string;
};

// --- The form ------------------------------------------------------------------------------------------------

function toFormField(field: RequirementField): FormField {
	return {
		name: field.name,
		label: fieldLabel(field.name, field.label),
		hint: field.description,
		required: field.required,
		choices: field.choices ? field.choices.map((value) => [value, choiceLabel(value)]) : null,
		pattern: field.pattern,
		kind: fieldKind(field.name, field.pattern)
	};
}

function endUserFieldNames(regulation: NumberRegulation): Set<string> {
	return new Set(
		regulation.endUser.flatMap((requirement) => requirement.fields.map((field) => field.name))
	);
}

// A document field is copied rather than asked when it is the address, must equal an answer, or has the same
// name as one (Twilio checks a document's business_name against the End-User's).
function isCopiedDocumentField(field: RequirementField, answerNames: Set<string>): boolean {
	return field.name === 'address_sids' || field.mustMatch !== null || answerNames.has(field.name);
}

/** The form for a country and number kind, from Twilio's live Regulation. Null regulation = address only. */
export function buildPaperworkForm(
	regulation: NumberRegulation | null,
	query: { countryCode: string; numberType: NumberType; endUserType: EndUserType }
): PaperworkForm {
	if (!regulation) {
		return {
			...query,
			regulationSid: null,
			businessFields: [],
			personFields: [],
			needsAddress: true,
			addressRule: '',
			requirements: []
		};
	}
	const answerNames = endUserFieldNames(regulation);
	const asked = regulation.endUser
		.flatMap((requirement) => requirement.fields)
		.filter((field) => isAskedEndUserField(field.name))
		.map(toFormField);
	const requirements: FormRequirement[] = regulation.documents.map((requirement) => ({
		requirementName: requirement.requirementName,
		label: requirement.label,
		hint: requirement.description,
		kinds: requirement.acceptedDocuments.map((document) => ({
			documentType: document.documentType,
			label: documentLabel(document.documentType, document.label),
			needsFile: documentNeedsFile(document.documentType),
			fields: document.fields
				.filter((field) => !isCopiedDocumentField(field, answerNames))
				.map(toFormField)
		}))
	}));
	const addressRequirement = regulation.documents.find((requirement) =>
		requirement.acceptedDocuments.some((document) =>
			document.fields.some((field) => field.name === 'address_sids')
		)
	);
	return {
		...query,
		regulationSid: regulation.regulationSid,
		businessFields:
			query.endUserType === 'business' ? asked.filter((field) => !isPersonField(field.name)) : [],
		personFields:
			query.endUserType === 'business' ? asked.filter((field) => isPersonField(field.name)) : asked,
		needsAddress: addressRequirement !== undefined,
		addressRule: addressRequirement?.description.trim() ?? '',
		requirements
	};
}

export async function loadPaperworkForm(
	catalog: Pick<SmsCountryCatalog, 'getRegulation'>,
	query: { countryCode: string; numberType: NumberType; endUserType: EndUserType }
): Promise<{ form: PaperworkForm; regulation: NumberRegulation | null }> {
	const regulation = await catalog.getRegulation(query);
	return { form: buildPaperworkForm(regulation, query), regulation };
}

// --- What goes to Twilio -------------------------------------------------------------------------------------

export function endUserAttributes(
	regulation: NumberRegulation,
	answers: Record<string, string>
): Record<string, string> {
	const attributes: Record<string, string> = {};
	for (const field of regulation.endUser.flatMap((requirement) => requirement.fields)) {
		const value = PLATFORM_ANSWERS[field.name] ?? answers[field.name]?.trim();
		if (value) attributes[field.name] = value;
	}
	return attributes;
}

export function documentAttributes(
	regulation: NumberRegulation,
	documentType: string,
	input: {
		answers: Record<string, string>;
		fields: Record<string, string>;
		addressSid: string | null;
	}
): Record<string, unknown> {
	const attributes: Record<string, unknown> = {};
	const fields = regulation.documents
		.flatMap((requirement) => requirement.acceptedDocuments)
		.filter((document) => document.documentType === documentType)
		.flatMap((document) => document.fields);
	for (const field of fields) {
		if (field.name in attributes) continue;
		if (field.name === 'address_sids') {
			if (input.addressSid) attributes.address_sids = [input.addressSid];
			continue;
		}
		const value = (
			field.mustMatch
				? input.answers[field.mustMatch]
				: (input.fields[field.name] ?? input.answers[field.name])
		)?.trim();
		if (value) attributes[field.name] = value;
	}
	return attributes;
}

function sameAttributes(a: Record<string, unknown> | null, b: Record<string, unknown>): boolean {
	if (!a) return false;
	const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
	for (const key of keys) if (JSON.stringify(a[key]) !== JSON.stringify(b[key])) return false;
	return true;
}

function countryLabel(paperwork: StoredPaperwork): string {
	return `${paperwork.countryCode} ${paperwork.numberType.replace('_', ' ')} · ${paperwork.id.slice(0, 8)}`;
}

/** Twilio's evaluation, pointed at the step and field the business fixes it in. */
export function fixesFromEvaluation(
	form: PaperworkForm,
	choices: Record<string, string>,
	problems: BundleEvaluationProblem[]
): PaperworkFix[] {
	const fields = new Map(
		[...form.businessFields, ...form.personFields].map((field) => [field.name, field])
	);
	return problems.map((problem) => {
		const requirement = form.requirements.find(
			(r) => r.requirementName === problem.requirementName
		);
		if (!requirement) {
			const field = problem.field ? fields.get(problem.field) : undefined;
			return {
				step: 'details',
				target: field?.name ?? 'details',
				label: field?.label ?? problem.requirementLabel,
				reason: problem.reason
			};
		}
		if (problem.field === 'address_sids') {
			return { step: 'details', target: 'address', label: 'Address', reason: problem.reason };
		}
		const type = choices[requirement.requirementName] ?? requirement.kinds[0]?.documentType ?? '';
		const kind = requirement.kinds.find((candidate) => candidate.documentType === type);
		const field = kind?.fields.find((candidate) => candidate.name === problem.field);
		return {
			step: 'documents',
			target: field ? `document:${type}:${field.name}` : `document:${type}`,
			label: field?.label ?? kind?.label ?? requirement.label,
			reason: problem.reason
		};
	});
}

// --- Sending -------------------------------------------------------------------------------------------------

export type SendOutcome = { status: Exclude<PaperworkStatus, 'sending'> };

type Step = { step: 'details' | 'documents'; target: string; label: string };

function refusalFix(step: Step, error: TwilioRegulatoryError): PaperworkFix {
	return {
		...step,
		reason:
			error.providerMessage?.trim() ||
			'The phone company could not accept this. Check it and send again.'
	};
}

export async function sendNumberPaperwork(
	deps: NumberPaperworkDeps,
	input: {
		organizationId: string;
		paperworkId: string;
		expectedRevision: number;
		actorUserId: string;
	}
): Promise<SendOutcome> {
	const claim = await deps.store.claimSending(
		input.organizationId,
		input.paperworkId,
		input.expectedRevision
	);
	if (!claim) {
		throw new PaperworkError(
			'not_sendable',
			'This paperwork changed or is already being sent. Reload it and try again.'
		);
	}
	const { token, previousStatus } = claim;
	const event = (action: string, detail: Record<string, unknown> = {}) =>
		deps.store.recordEvent({
			organizationId: input.organizationId,
			paperworkId: input.paperworkId,
			action,
			actorUserId: input.actorUserId,
			detail
		});
	const release = (status: PaperworkStatus) =>
		deps.store.finishSending(input.paperworkId, token, {
			status: status === 'sending' ? 'draft' : status
		});

	let step: Step = { step: 'details', target: 'details', label: 'Business details' };
	try {
		const loaded = await deps.store.get(input.organizationId, input.paperworkId);
		if (!loaded) throw new PaperworkError('not_sendable', 'This paperwork no longer exists.');
		const { paperwork, documents } = loaded;
		const query = {
			countryCode: paperwork.countryCode,
			numberType: paperwork.numberType,
			endUserType: paperwork.endUserType
		};

		let regulation: NumberRegulation | null;
		try {
			regulation = await deps.catalog.getRegulation(query);
		} catch {
			throw new PaperworkError('provider_unavailable', 'The phone company could not be reached.');
		}
		const form = buildPaperworkForm(regulation, query);
		const choices = resolveDocumentChoices(form.requirements, paperwork.documentChoices);
		const files = new Map<string, Awaited<ReturnType<NumberPaperworkStore['readFile']>>>();
		for (const document of documents) {
			if (document.protectedDocumentId) {
				files.set(
					document.documentType,
					await deps.store.readFile(input.organizationId, document.protectedDocumentId)
				);
			}
		}
		const problems = paperworkProblems(form, {
			answers: paperwork.answers,
			address: paperwork.address,
			documentChoices: choices,
			documents: documents.map((document) => ({
				documentType: document.documentType,
				fields: document.fields,
				fileState: files.get(document.documentType)?.state ?? null
			}))
		});
		if (problems.length > 0) {
			throw new PaperworkError('incomplete', 'Some answers are still missing.', problems);
		}

		const account = await deps.subaccount(input.organizationId);

		if (regulation && regulation.regulationSid !== paperwork.regulationSid) {
			await deps.store.saveProvider(paperwork.id, token, {
				regulationSid: regulation.regulationSid
			});
		}

		// A fresh address every send: Twilio never lets an address change country, and addresses cost nothing.
		let addressSid: string | null = null;
		if (form.needsAddress && paperwork.address) {
			step = { step: 'details', target: 'address', label: 'Address' };
			const address = paperwork.address;
			const created = await deps.twilio.createAddress(account, {
				customerName: address.customer_name.trim(),
				street: address.street.trim(),
				streetSecondary: address.street_secondary.trim() || null,
				city: address.city.trim(),
				region: address.region.trim(),
				postalCode: address.postal_code.trim(),
				isoCountry: address.country_code,
				friendlyName: countryLabel(paperwork)
			});
			addressSid = created.sid;
			await deps.store.saveProvider(paperwork.id, token, { providerAddressSid: addressSid });
		}

		if (!regulation) {
			// The country only asks for an address; Twilio has nothing to review.
			await deps.store.finishSending(paperwork.id, token, {
				status: 'approved',
				failureReason: null,
				fixes: [],
				submitted: true,
				decided: true
			});
			await event('approved', { address_only: true });
			return { status: 'approved' };
		}

		step = { step: 'details', target: 'details', label: 'Business details' };
		const attributes = endUserAttributes(regulation, paperwork.answers);
		let endUserSid = paperwork.providerEndUserSid;
		if (endUserSid) {
			await deps.twilio.updateEndUser(account, endUserSid, attributes);
		} else {
			endUserSid = (
				await deps.twilio.createEndUser(account, {
					friendlyName: countryLabel(paperwork),
					type: paperwork.endUserType,
					attributes
				})
			).sid;
			await deps.store.saveProvider(paperwork.id, token, { providerEndUserSid: endUserSid });
		}

		const documentSids: string[] = [];
		for (const kind of chosenDocumentKinds(form.requirements, choices)) {
			step = { step: 'documents', target: `document:${kind.documentType}`, label: kind.label };
			const document = documents.find((candidate) => candidate.documentType === kind.documentType);
			const wanted = documentAttributes(regulation, kind.documentType, {
				answers: paperwork.answers,
				fields: document?.fields ?? {},
				addressSid
			});
			const sid = await ensureDocument(deps, account, paperwork, kind, document, wanted, files);
			documentSids.push(sid);
		}

		step = { step: 'details', target: 'details', label: 'Paperwork' };
		let bundleSid = paperwork.providerBundleSid;
		if (!bundleSid) {
			const bundle = await deps.twilio.createBundle(account, {
				friendlyName: countryLabel(paperwork),
				email: deps.notificationEmail(),
				statusCallback: deps.statusCallbackUrl(),
				regulationSid: regulation.regulationSid,
				isoCountry: paperwork.countryCode,
				numberType: paperwork.numberType,
				endUserType: paperwork.endUserType
			});
			bundleSid = bundle.sid;
			await deps.store.saveProvider(paperwork.id, token, {
				providerBundleSid: bundleSid,
				providerStatus: bundle.status
			});
		} else {
			const bundle = await deps.twilio.fetchBundle(account, bundleSid);
			if (bundle.status === 'twilio-rejected') {
				await deps.twilio.updateBundleStatus(account, bundleSid, 'draft');
			} else if (bundle.status !== 'draft') {
				// Twilio already has it (a send that dropped after submitting): follow Twilio, change nothing.
				const status = bundle.status === 'twilio-approved' ? 'approved' : 'under_review';
				await deps.store.finishSending(paperwork.id, token, {
					status,
					providerStatus: bundle.status,
					submitted: true
				});
				return { status };
			}
		}

		const wantedItems = new Set([endUserSid, ...documentSids]);
		const assigned = await deps.twilio.listItemAssignments(account, bundleSid);
		for (const item of assigned) {
			if (!wantedItems.has(item.objectSid)) {
				await deps.twilio.deleteItemAssignment(account, bundleSid, item.sid);
			}
		}
		const present = new Set(assigned.map((item) => item.objectSid));
		for (const objectSid of wantedItems) {
			if (!present.has(objectSid))
				await deps.twilio.createItemAssignment(account, bundleSid, objectSid);
		}

		const evaluation = await deps.twilio.evaluateBundle(account, bundleSid);
		if (!evaluation.compliant) {
			const fixes = fixesFromEvaluation(form, choices, evaluation.problems);
			await deps.store.finishSending(paperwork.id, token, {
				status: 'needs_fix',
				providerStatus: 'draft',
				failureReason:
					'The phone company’s check found something to fix before it can review this.',
				fixes
			});
			await event('check_failed', { problems: fixes.length });
			return { status: 'needs_fix' };
		}

		const submitted = await deps.twilio.updateBundleStatus(account, bundleSid, 'pending-review');
		await deps.store.finishSending(paperwork.id, token, {
			status: 'under_review',
			providerStatus: submitted.status,
			failureReason: null,
			fixes: [],
			submitted: true
		});
		await event('sent', { bundle: bundleSid });
		return { status: 'under_review' };
	} catch (error) {
		if (error instanceof PaperworkError) {
			await release(previousStatus);
			if (error.code === 'provider_unavailable') await event('provider_unavailable');
			throw error;
		}
		if (error instanceof TwilioRegulatoryError) {
			if (
				error.retryable ||
				error.status === null ||
				error.status === 401 ||
				error.status === 403
			) {
				await release(previousStatus);
				await event('provider_unavailable', {
					code: error.code,
					provider_code: error.providerCode
				});
				throw new PaperworkError('provider_unavailable', 'The phone company could not be reached.');
			}
			// Twilio refused one of the records (an address it could not find, say): the business fixes it.
			const fix = refusalFix(step, error);
			await deps.store.finishSending(input.paperworkId, token, {
				status: 'needs_fix',
				failureReason: fix.reason,
				fixes: [fix]
			});
			await event('refused', { target: step.target, provider_code: error.providerCode });
			return { status: 'needs_fix' };
		}
		await release(previousStatus).catch(() => undefined);
		throw error;
	}
}

async function ensureDocument(
	deps: NumberPaperworkDeps,
	account: SubaccountCredentials,
	paperwork: StoredPaperwork,
	kind: { documentType: string; needsFile: boolean; label: string },
	document: StoredPaperworkDocument | undefined,
	attributes: Record<string, unknown>,
	files: Map<string, Awaited<ReturnType<NumberPaperworkStore['readFile']>>>
): Promise<string> {
	const fileId = kind.needsFile ? (document?.protectedDocumentId ?? null) : null;
	if (
		document?.providerDocumentSid &&
		document.providerProtectedDocumentId === fileId &&
		sameAttributes(document.providerFields, attributes)
	) {
		return document.providerDocumentSid;
	}
	if (!document) {
		// Every chosen kind has its row: the form saves one per choice. A missing row means it changed meanwhile.
		throw new PaperworkError(
			'not_sendable',
			'This paperwork changed while it was being sent. Try again.'
		);
	}
	let file = null;
	if (kind.needsFile) {
		const stored = files.get(kind.documentType);
		if (!stored?.objectKey || stored.state !== 'ready') {
			throw new PaperworkError('incomplete', 'A document is not ready yet.', [
				{
					step: 'documents',
					target: `document:${kind.documentType}`,
					label: kind.label,
					reason: 'Add this document again.'
				}
			]);
		}
		file = {
			name: stored.displayName,
			mimeType: stored.mimeType,
			bytes: await deps.readFileBytes(stored.objectKey)
		};
	}
	const created = await deps.twilio.createSupportingDocument(account, {
		friendlyName: `${kind.label} · ${paperwork.countryCode}`,
		type: kind.documentType,
		attributes,
		file
	});
	await deps.store.saveDocumentProvider(document.id, {
		providerDocumentSid: created.sid,
		providerProtectedDocumentId: fileId,
		providerFields: attributes,
		providerStatus: created.status
	});
	return created.sid;
}

// --- Following Twilio's review -------------------------------------------------------------------------------

export type SyncOutcome = { status: PaperworkStatus; changed: boolean } | { skipped: string };

const PLAIN_REJECTION =
	'The phone company turned this paperwork down. Check the details and documents, then send it again.';

export async function syncNumberPaperwork(
	deps: Pick<NumberPaperworkDeps, 'store' | 'twilio' | 'existingSubaccount'>,
	input: { organizationId: string; paperworkId: string; callbackReason?: string | null }
): Promise<SyncOutcome> {
	const loaded = await deps.store.get(input.organizationId, input.paperworkId);
	if (!loaded) return { skipped: 'missing' };
	const { paperwork, documents } = loaded;
	if (paperwork.status === 'sending' || paperwork.status === 'draft')
		return { skipped: paperwork.status };
	if (!paperwork.providerBundleSid) return { skipped: 'no_bundle' };
	const account = await deps.existingSubaccount(input.organizationId);
	if (!account) return { skipped: 'no_subaccount' };

	const bundle = await deps.twilio.fetchBundle(account, paperwork.providerBundleSid);
	const event = (action: string, detail: Record<string, unknown> = {}) =>
		deps.store.recordEvent({
			organizationId: input.organizationId,
			paperworkId: paperwork.id,
			action,
			detail
		});

	if (bundle.status === 'twilio-approved' || bundle.status === 'provisionally-approved') {
		const changed = paperwork.status !== 'approved';
		await deps.store.recordOutcome(paperwork.id, {
			status: 'approved',
			providerStatus: bundle.status,
			failureReason: null,
			fixes: [],
			validUntil: bundle.validUntil,
			decided: changed
		});
		if (changed) {
			await deps.store.scheduleFileDeletion(paperwork.id);
			await event('approved');
		}
		return { status: 'approved', changed };
	}

	if (bundle.status === 'twilio-rejected') {
		const fixes: PaperworkFix[] = [];
		for (const document of documents) {
			if (!document.providerDocumentSid) continue;
			const review = await deps.twilio.fetchSupportingDocument(
				account,
				document.providerDocumentSid
			);
			await deps.store.recordDocumentReview(document.id, {
				providerStatus: review.status,
				failureReason: review.failureReason
			});
			if (review.failureReason) {
				fixes.push({
					step: 'documents',
					target: `document:${document.documentType}`,
					label: documentLabel(document.documentType, document.documentType),
					reason: review.failureReason
				});
			}
		}
		const reason = input.callbackReason?.trim() || fixes[0]?.reason || PLAIN_REJECTION;
		const changed = paperwork.status !== 'needs_fix';
		await deps.store.recordOutcome(paperwork.id, {
			status: 'needs_fix',
			providerStatus: bundle.status,
			failureReason: reason.slice(0, 4000),
			fixes,
			decided: changed
		});
		if (changed) await event('needs_fix', { documents: fixes.length });
		return { status: 'needs_fix', changed };
	}

	if (bundle.status === 'pending-review' || bundle.status === 'in-review') {
		const changed = paperwork.status !== 'under_review';
		await deps.store.recordOutcome(paperwork.id, {
			status: 'under_review',
			providerStatus: bundle.status
		});
		return { status: 'under_review', changed };
	}
	return { skipped: bundle.status };
}

/** The daily safety net behind Twilio's status callback: re-check every set still under review. */
export async function runPaperworkStatusCheck(
	deps: Pick<NumberPaperworkDeps, 'store' | 'twilio' | 'existingSubaccount'>,
	limit = 200
): Promise<{ checked: number; approved: number; needsFix: number; failed: number }> {
	const result = { checked: 0, approved: 0, needsFix: 0, failed: 0 };
	for (const set of await deps.store.listUnderReview(limit)) {
		result.checked += 1;
		try {
			const outcome = await syncNumberPaperwork(deps, {
				organizationId: set.organizationId,
				paperworkId: set.id
			});
			if ('status' in outcome && outcome.changed) {
				if (outcome.status === 'approved') result.approved += 1;
				if (outcome.status === 'needs_fix') result.needsFix += 1;
			}
		} catch (error) {
			result.failed += 1;
			console.error('Paperwork status check failed for one set.', {
				paperworkId: set.id,
				error: error instanceof Error ? error.message : error
			});
		}
	}
	return result;
}

// --- Live wiring ---------------------------------------------------------------------------------------------

/** The live store, catalog, Twilio adapter, subaccount and file storage. */
export function createNumberPaperworkDeps(): NumberPaperworkDeps {
	const client = getOwnerSupabaseClient();
	const provisioning = createTwilioProvisioningDeps();
	const credentials = (access: SubaccountAccess): SubaccountCredentials => ({
		subaccountSid: access.subaccountSid,
		authToken: access.authToken
	});
	return {
		store: createSupabaseNumberPaperworkStore(client),
		catalog: getSmsCountryCatalog(),
		twilio: createTwilioRegulatoryClient(),
		async subaccount(organizationId) {
			try {
				return credentials(await ensureTwilioSubaccount(organizationId));
			} catch (error) {
				if (error instanceof NumberPurchaseError) {
					throw new PaperworkError('provider_unavailable', error.message);
				}
				throw error;
			}
		},
		async existingSubaccount(organizationId) {
			const access = await getSubaccountAccess(provisioning, organizationId);
			return access ? credentials(access) : null;
		},
		readFileBytes: getObjectBytes,
		statusCallbackUrl: getTwilioNumberPaperworkWebhookUrl,
		notificationEmail() {
			const email = getServerEnv().TWILIO_ISV_MONITORING_EMAIL;
			if (!email)
				throw new PaperworkError(
					'provider_unavailable',
					'Uplift has not finished its texting setup.'
				);
			return email;
		}
	};
}
