import { httpError } from '$lib/http-error';

// Mirrors src/lib/server/validation/communications-sms-registration.schema.ts. A draft may be partially
// filled (every field optional); a submission requires every field the schema itself requires.
export type SmsRegistrationAddress = {
	line1: string;
	line2?: string;
	city: string;
	region: string;
	postal_code: string;
	country_code: string;
};

export type SmsRegistrationRepresentative = {
	first_name: string;
	last_name: string;
	business_title: string;
	job_position: string;
	email: string;
	phone_number: string;
};

export type SmsRegistrationConsentMethod =
	'website_form' | 'paper_form' | 'verbal' | 'text_initiated' | 'other';

export type SmsRegistrationEstimatedVolume = 'under_500' | '500_2000' | '2001_10000' | 'over_10000';

export type SmsRegistrationMessaging = {
	description: string;
	consent_method: SmsRegistrationConsentMethod | '';
	consent_description: string;
	sample_messages: string[];
	privacy_policy_url?: string;
	terms_url?: string;
	estimated_monthly_messages: SmsRegistrationEstimatedVolume | '';
};

export type SmsRegistrationBusinessType =
	| 'sole_proprietorship'
	| 'partnership'
	| 'limited_liability_company'
	| 'cooperative'
	| 'nonprofit_corporation'
	| 'corporation'
	| 'other';

export type SmsRegistrationAnswers = {
	legal_business_name: string;
	business_type: SmsRegistrationBusinessType | '';
	// Only optional for a sole proprietor with no EIN/registration number -- Twilio's separate Sole Proprietor
	// path is for exactly that case. Every other business type still requires both (server-enforced).
	business_registration_id_type: string;
	business_registration_id: string;
	website_url: string;
	business_address: Partial<SmsRegistrationAddress>;
	authorized_representative: Partial<SmsRegistrationRepresentative>;
	messaging: Partial<SmsRegistrationMessaging>;
};

export type SmsRegistrationStatus =
	'waiting_for_info' | 'under_review' | 'action_needed' | 'approved';

export type SmsRegistration = {
	id: string;
	country_code: string;
	sender_type: string;
	use_case: string;
	status: SmsRegistrationStatus;
	required_fixes: string | null;
	draft_questionnaire_version: number;
	draft_answers: Partial<SmsRegistrationAnswers>;
	draft_revision: number;
	draft_updated_at: string | null;
	submitted_at: string | null;
	updated_at: string;
};

export type SmsReadinessState =
	| 'not_included'
	| 'needs_setup'
	| 'waiting_for_info'
	| 'under_review'
	| 'action_needed'
	| 'finishing_setup'
	| 'ready';

export type SmsReadiness = {
	effective_mode: 'off' | 'operational';
	readiness_state: SmsReadinessState;
	live_sender_count: number;
};

export type SmsRegistrationHome = {
	registration: SmsRegistration | null;
	readiness: SmsReadiness;
};

export class SmsRegistrationWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {},
		public readonly reason: string = 'unknown'
	) {
		super(message);
		this.name = 'SmsRegistrationWriteError';
	}
}

// Mirrors src/lib/server/settings/readiness.ts smsRegistrationBadge -- kept as a small client-side copy so
// the Settings home card and this page can render the same badge without importing server-only code.
export function smsRegistrationBadge(readinessState: string): {
	label: string;
	tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
} {
	switch (readinessState) {
		case 'ready':
			return { label: 'Ready', tone: 'success' };
		case 'finishing_setup':
			return { label: 'Finishing setup', tone: 'warning' };
		case 'under_review':
			return { label: 'Pending review', tone: 'informative' };
		case 'action_needed':
			return { label: 'Needs fixes', tone: 'critical' };
		case 'waiting_for_info':
			return { label: 'Draft', tone: 'warning' };
		case 'not_included':
			return { label: 'Not included', tone: 'inactive' };
		default:
			return { label: 'Needs setup', tone: 'warning' };
	}
}

const registrationsUrl = '/api/settings/communications/sms/registrations';

export const smsRegistrationKey = ['settings', 'communications', 'sms', 'registration'] as const;

export async function fetchSmsRegistration(): Promise<SmsRegistrationHome> {
	const response = await fetch(registrationsUrl);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'The registration could not be loaded.');
	return result as SmsRegistrationHome;
}

export async function startSmsRegistration(): Promise<{ registration: SmsRegistration }> {
	const response = await fetch(registrationsUrl, { method: 'POST' });
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsRegistrationWriteError(result.error ?? 'The registration could not be started.');
	return result as { registration: SmsRegistration };
}

export async function saveSmsRegistrationDraft(
	registrationId: string,
	body: {
		expected_revision: number;
		questionnaire_version: number;
		answers: Partial<SmsRegistrationAnswers>;
	}
): Promise<{ registration: SmsRegistration }> {
	const response = await fetch(`${registrationsUrl}/${registrationId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsRegistrationWriteError(
			result.error ?? 'The registration could not be saved.',
			result.field_errors ?? {},
			result.reason ?? 'unknown'
		);
	return result as { registration: SmsRegistration };
}

export async function submitSmsRegistration(
	registrationId: string,
	body: {
		expected_revision: number;
		questionnaire_version: number;
		answers: SmsRegistrationAnswers;
		confirm_authorized_representative: true;
	}
): Promise<{
	registration: Pick<SmsRegistration, 'id' | 'status' | 'submitted_at' | 'draft_revision'>;
}> {
	const response = await fetch(`${registrationsUrl}/${registrationId}/submit`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsRegistrationWriteError(
			result.error ?? 'The registration could not be submitted.',
			result.field_errors ?? {},
			result.reason ?? 'unknown'
		);
	return result as {
		registration: Pick<SmsRegistration, 'id' | 'status' | 'submitted_at' | 'draft_revision'>;
	};
}
