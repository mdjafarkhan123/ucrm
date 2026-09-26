// Google review campaign Part 1: read and save one organization's review setup.
//
// The row is read only here, through the owner client, after the API route has checked the member's
// permission. No row means the organization is still on UCRM's defaults ($lib/reviews/settings.ts).

import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { Json } from '$lib/database.types';
import {
	SMS_REGISTRATION_COUNTRY_CODE,
	SMS_REGISTRATION_SENDER_TYPE,
	SMS_REGISTRATION_USE_CASE
} from '$lib/server/communications/sms-registration';
import {
	DEFAULT_REVIEW_FEEDBACK_FORM,
	DEFAULT_REVIEW_MESSAGE_STYLES,
	DEFAULT_REVIEW_REQUEST_PLAN,
	DEFAULT_ROUTING_GOOGLE_MIN_RATING,
	type ReviewChannelReadiness,
	type ReviewFeedbackForm,
	type ReviewMessageStyles,
	type ReviewRequestPlan,
	type ReviewSettingsInput,
	type ReviewSettingsView
} from '$lib/reviews/settings';

export class ReviewSettingsConflictError extends Error {}
export class ReviewSettingsForbiddenError extends Error {}
export class ReviewSettingsRuleError extends Error {}

type ReviewSettingsRow = {
	revision: number;
	google_review_url: string | null;
	routing_enabled: boolean;
	routing_google_min_rating: number;
	routing_acknowledged_at: string | null;
	feedback_form: ReviewFeedbackForm;
	message_styles: ReviewMessageStyles;
	// Null for a row saved before reminders existed: still on the ready-made plan.
	request_plan: ReviewRequestPlan | null;
	updated_at: string;
};

// Whether each channel can send an automated customer message right now. Email mirrors the sender rule of
// the automated send path (private.enqueue_automation_inquiry_email): an enabled default sender that allows
// automated sending, on a verified, authenticated sending domain. SMS uses Communications' own readiness.
export async function loadReviewChannelReadiness(
	organizationId: string
): Promise<ReviewChannelReadiness> {
	const owner = getOwnerSupabaseClient();
	const [smsResult, senderResult] = await Promise.all([
		owner.rpc('communication_sms_readiness', {
			p_organization_id: organizationId,
			p_country_code: SMS_REGISTRATION_COUNTRY_CODE,
			p_sender_type: SMS_REGISTRATION_SENDER_TYPE,
			p_use_case: SMS_REGISTRATION_USE_CASE
		}),
		owner
			.from('communication_email_senders')
			.select('domain_id')
			.eq('organization_id', organizationId)
			.eq('lifecycle_state', 'enabled')
			.eq('allows_automated', true)
			.eq('is_organization_default', true)
			.limit(1)
			.maybeSingle()
	]);
	if (smsResult.error) throw smsResult.error;
	if (senderResult.error) throw senderResult.error;

	const smsRow = Array.isArray(smsResult.data) ? smsResult.data[0] : smsResult.data;

	let emailReady = false;
	if (senderResult.data) {
		const domain = await owner
			.from('communication_email_domains')
			.select('id')
			.eq('organization_id', organizationId)
			.eq('id', senderResult.data.domain_id)
			.eq('purpose', 'sending')
			.eq('lifecycle_state', 'verified')
			.eq('provider_verified', true)
			.eq('provider_authenticated', true)
			.eq('ownership_status', 'passing')
			.eq('dkim_status', 'passing')
			.maybeSingle();
		if (domain.error) throw domain.error;
		emailReady = Boolean(domain.data);
	}

	return {
		sms_ready: (smsRow as { readiness_state?: string } | null)?.readiness_state === 'ready',
		email_ready: emailReady
	};
}

export async function loadReviewSettings(organizationId: string): Promise<ReviewSettingsView> {
	const [row, readiness] = await Promise.all([
		getOwnerSupabaseClient()
			.from('review_settings')
			.select(
				'revision, google_review_url, routing_enabled, routing_google_min_rating, routing_acknowledged_at, feedback_form, message_styles, request_plan, updated_at'
			)
			.eq('organization_id', organizationId)
			.maybeSingle(),
		loadReviewChannelReadiness(organizationId)
	]);
	if (row.error) throw row.error;

	const saved = row.data as ReviewSettingsRow | null;
	if (!saved) {
		return {
			revision: 0,
			google_review_url: null,
			routing_enabled: false,
			routing_google_min_rating: DEFAULT_ROUTING_GOOGLE_MIN_RATING,
			routing_acknowledged_at: null,
			feedback_form: DEFAULT_REVIEW_FEEDBACK_FORM,
			message_styles: DEFAULT_REVIEW_MESSAGE_STYLES,
			request_plan: DEFAULT_REVIEW_REQUEST_PLAN,
			readiness,
			updated_at: null
		};
	}
	return { ...saved, request_plan: saved.request_plan ?? DEFAULT_REVIEW_REQUEST_PLAN, readiness };
}

export async function saveReviewSettings(
	organizationId: string,
	actorId: string,
	input: ReviewSettingsInput
) {
	const { error } = await getOwnerSupabaseClient().rpc('save_review_settings', {
		p_organization_id: organizationId,
		p_actor_id: actorId,
		p_expected_revision: input.expected_revision,
		p_google_review_url: input.google_review_url ?? '',
		p_routing_enabled: input.routing_enabled,
		p_routing_google_min_rating: input.routing_google_min_rating,
		p_acknowledge_routing: input.acknowledge_routing,
		p_feedback_form: input.feedback_form as unknown as Json,
		p_message_styles: input.message_styles as unknown as Json,
		p_request_plan: input.request_plan as unknown as Json
	});
	if (error) {
		if (error.code === 'P0409') throw new ReviewSettingsConflictError(error.message);
		if (error.code === '42501') throw new ReviewSettingsForbiddenError(error.message);
		if (error.code === '23514') throw new ReviewSettingsRuleError(error.message);
		throw error;
	}
}
