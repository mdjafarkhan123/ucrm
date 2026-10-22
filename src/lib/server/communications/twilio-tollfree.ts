import {
	TwilioRegulatoryError,
	basicAuth,
	readString,
	regulatoryRequest,
	type SubaccountCredentials
} from './twilio-regulatory';

// Twilio Toll-Free Verification adapter (Stage 10 Part 4b): the only module that sends a toll-free number's
// carrier check to Twilio. Verified against Twilio's Toll-Free Verification resource and API onboarding guide
// (2026-10-22): https://messaging.twilio.com/v1/Tollfree/Verifications — create, fetch, list by number, edit a
// turned-down check while `edit_allowed`, and delete one that can no longer be edited.
//
// Calls run inside the business's own subaccount, which owns the number, so the check belongs to that account.
// Twilio's ISV guidance: the check describes the business that texts its customers, never Uplift.
//
// Twilio has no sandbox for this resource, so every call is real when it runs. Tests drive the callers against a
// fake of the port below.

const MESSAGING_BASE = 'https://messaging.twilio.com';
const VERIFICATION_SID = /^HH[0-9A-Fa-f]{32}$/;

export type TollfreeVerificationStatus =
	'PENDING_REVIEW' | 'IN_REVIEW' | 'TWILIO_APPROVED' | 'TWILIO_REJECTED';

const STATUSES = new Set<TollfreeVerificationStatus>([
	'PENDING_REVIEW',
	'IN_REVIEW',
	'TWILIO_APPROVED',
	'TWILIO_REJECTED'
]);

export type TollfreeVerification = {
	sid: string;
	status: TollfreeVerificationStatus;
	rejectionReason: string | null;
	errorCode: number | null;
	editAllowed: boolean | null;
	editExpiration: string | null;
};

/** Twilio's request fields by their own names; a list goes as the key repeated. */
export type TollfreeVerificationForm = Record<string, string | string[]>;

export type TwilioTollfreeClient = {
	create(
		account: SubaccountCredentials,
		form: TollfreeVerificationForm
	): Promise<TollfreeVerification>;
	/** Edit and send again a turned-down check that Twilio still allows to be edited. */
	update(
		account: SubaccountCredentials,
		sid: string,
		form: TollfreeVerificationForm
	): Promise<TollfreeVerification>;
	fetch(account: SubaccountCredentials, sid: string): Promise<TollfreeVerification>;
	/** The check already made for a number, if any: how a dropped connection after create is recovered. */
	findForNumber(
		account: SubaccountCredentials,
		phoneNumberSid: string
	): Promise<TollfreeVerification | null>;
	remove(account: SubaccountCredentials, sid: string): Promise<void>;
};

function readVerification(body: unknown): TollfreeVerification {
	const sid = readString(body, 'sid');
	if (!sid || !VERIFICATION_SID.test(sid)) {
		throw new TwilioRegulatoryError(
			'Twilio returned an unexpected identifier.',
			null,
			'twilio_tollfree_missing_sid',
			false
		);
	}
	const status = readString(body, 'status');
	if (!status || !STATUSES.has(status as TollfreeVerificationStatus)) {
		throw new TwilioRegulatoryError(
			'Twilio returned an unknown toll-free check status.',
			null,
			'twilio_tollfree_unknown_status',
			false
		);
	}
	const record = body as Record<string, unknown>;
	const reasons = Array.isArray(record.rejection_reasons) ? record.rejection_reasons : [];
	const firstReason = reasons
		.map((item) => readString(item, 'reason'))
		.find((reason): reason is string => Boolean(reason));
	return {
		sid,
		status: status as TollfreeVerificationStatus,
		rejectionReason: readString(body, 'rejection_reason') ?? firstReason ?? null,
		errorCode: typeof record.error_code === 'number' ? record.error_code : null,
		editAllowed: typeof record.edit_allowed === 'boolean' ? record.edit_allowed : null,
		editExpiration: readString(body, 'edit_expiration')
	};
}

function requireVerificationSid(sid: string) {
	if (!VERIFICATION_SID.test(sid)) {
		throw new TwilioRegulatoryError(
			'The toll-free check identifier is not valid.',
			null,
			'twilio_tollfree_bad_sid',
			false
		);
	}
	return sid;
}

export function createTwilioTollfreeClient(): TwilioTollfreeClient {
	return {
		async create(account, form) {
			return readVerification(
				await regulatoryRequest({
					base: MESSAGING_BASE,
					path: '/v1/Tollfree/Verifications',
					method: 'POST',
					auth: basicAuth(account),
					form
				})
			);
		},

		async update(account, sid, form) {
			return readVerification(
				await regulatoryRequest({
					base: MESSAGING_BASE,
					path: `/v1/Tollfree/Verifications/${requireVerificationSid(sid)}`,
					method: 'POST',
					auth: basicAuth(account),
					form
				})
			);
		},

		async fetch(account, sid) {
			return readVerification(
				await regulatoryRequest({
					base: MESSAGING_BASE,
					path: `/v1/Tollfree/Verifications/${requireVerificationSid(sid)}`,
					method: 'GET',
					auth: basicAuth(account)
				})
			);
		},

		async findForNumber(account, phoneNumberSid) {
			const body = await regulatoryRequest({
				base: MESSAGING_BASE,
				path: '/v1/Tollfree/Verifications',
				method: 'GET',
				auth: basicAuth(account),
				query: { TollfreePhoneNumberSid: phoneNumberSid, PageSize: '20' }
			});
			// Twilio's list pages hold their records under the resource's plural name ("verifications") beside
			// `meta`; the docs do not print it for this resource, so the one array on the page is taken.
			const list =
				body && typeof body === 'object'
					? (Object.entries(body as Record<string, unknown>).find(
							([key, value]) => key !== 'meta' && Array.isArray(value)
						)?.[1] as unknown[] | undefined)
					: undefined;
			return list?.length ? readVerification(list[0]) : null;
		},

		async remove(account, sid) {
			await regulatoryRequest({
				base: MESSAGING_BASE,
				path: `/v1/Tollfree/Verifications/${requireVerificationSid(sid)}`,
				method: 'DELETE',
				auth: basicAuth(account)
			});
		}
	};
}
