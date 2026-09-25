// Google review campaign Part 1: the shape, limits and ready-made defaults of an organization's review setup.
//
// Product truth: docs/google-review-campaign-owner-brief.md. Shared by the browser editor and the /api Zod
// schema. An organization with no saved row gets these defaults, so they live here and nowhere else.

import { FORM_QUESTION_TYPES, type FormQuestion, type FormQuestionType } from '$lib/forms/types';

export const REVIEW_CHANNELS = ['sms', 'email'] as const;
export type ReviewChannel = (typeof REVIEW_CHANNELS)[number];

export const REVIEW_STYLES = ['friendly', 'professional', 'short'] as const;
export type ReviewStyle = (typeof REVIEW_STYLES)[number];

export const REVIEW_STYLE_LABELS: Record<ReviewStyle, string> = {
	friendly: 'Friendly',
	professional: 'Professional',
	short: 'Short'
};

// Photo upload waits for the feedback page's own upload path; every other request-form answer type works.
export const REVIEW_FEEDBACK_QUESTION_TYPES = FORM_QUESTION_TYPES.filter(
	(type): type is Exclude<FormQuestionType, 'image_upload'> => type !== 'image_upload'
);

export const REVIEW_FEEDBACK_MAX_QUESTIONS = 15;
export const REVIEW_FEEDBACK_HEADING_MAX = 160;
export const REVIEW_FEEDBACK_INTRO_MAX = 1000;
export const REVIEW_THANK_YOU_TITLE_MAX = 160;
export const REVIEW_THANK_YOU_MESSAGE_MAX = 1000;
export const REVIEW_SMS_BODY_MAX = 1000;
export const REVIEW_EMAIL_SUBJECT_MAX = 200;
export const REVIEW_EMAIL_BODY_MAX = 5000;
export const REVIEW_GOOGLE_URL_MAX = 2048;

// The values a review message may contain. {{review_link}} is the customer's own UCRM feedback page, never
// Google directly, and every message must include it.
export const REVIEW_MESSAGE_VARIABLES = [
	{ token: 'customer_first_name', label: 'Customer first name' },
	{ token: 'customer_name', label: 'Customer full name' },
	{ token: 'business_name', label: 'Your business name' },
	{ token: 'review_link', label: 'Review link' }
] as const;

const REVIEW_TOKENS = new Set<string>(REVIEW_MESSAGE_VARIABLES.map((variable) => variable.token));
const TOKEN_PATTERN = /\{\{([^}]*)\}\}/g;

export function unknownReviewVariables(text: string): string[] {
	const unknown = new Set<string>();
	for (const match of text.matchAll(TOKEN_PATTERN)) {
		if (!REVIEW_TOKENS.has(match[1])) unknown.add(match[1]);
	}
	return [...unknown];
}

export function hasReviewLink(text: string) {
	return text.includes('{{review_link}}');
}

export type ReviewFeedbackForm = {
	heading: string;
	intro: string;
	questions: FormQuestion[];
	thank_you_title: string;
	thank_you_message: string;
};

export type ReviewMessageStyles = {
	default_style: ReviewStyle;
	sms: Record<ReviewStyle, { body: string }>;
	email: Record<ReviewStyle, { subject: string; body: string }>;
};

export type ReviewChannelReadiness = {
	sms_ready: boolean;
	email_ready: boolean;
};

export type ReviewSettingsView = {
	// 0 while the organization is still on the defaults below and has never saved.
	revision: number;
	google_review_url: string | null;
	routing_enabled: boolean;
	routing_google_min_rating: number;
	routing_acknowledged_at: string | null;
	feedback_form: ReviewFeedbackForm;
	message_styles: ReviewMessageStyles;
	readiness: ReviewChannelReadiness;
	updated_at: string | null;
};

export type ReviewSettingsInput = {
	expected_revision: number;
	google_review_url: string | null;
	routing_enabled: boolean;
	routing_google_min_rating: number;
	acknowledge_routing: boolean;
	feedback_form: ReviewFeedbackForm;
	message_styles: ReviewMessageStyles;
};

// Google review links come in several official shapes: the g.page short link from Business Profile's "Ask
// for reviews", maps.app.goo.gl share links, and google.<country> search/maps review URLs. The customer
// is sent here from a message the contractor's business signs, so only Google's own hosts are accepted.
const GOOGLE_HOST =
	/^(?:(?:www|maps|search|business)\.)?google\.(?:com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})$/;
const GOOGLE_SHORT_HOSTS = new Set(['g.page', 'maps.app.goo.gl', 'goo.gl']);

export function isGoogleReviewUrl(value: string) {
	if (value.length > REVIEW_GOOGLE_URL_MAX) return false;
	let url: URL;
	try {
		url = new URL(value);
	} catch {
		return false;
	}
	if (url.protocol !== 'https:' || url.username || url.password || url.port) return false;
	const host = url.hostname.toLowerCase();
	return GOOGLE_SHORT_HOSTS.has(host) || GOOGLE_HOST.test(host);
}

// Fixed ids so the default questions keep the same identity once an organization saves them.
export const DEFAULT_REVIEW_FEEDBACK_FORM: ReviewFeedbackForm = {
	heading: 'Tell us about your experience',
	intro:
		'Thank you for taking a moment to tell us how things went. Your answers go only to our team, and we read every one.',
	questions: [
		{
			id: '6b1f3c1e-8f0a-4c52-9d3e-2a7f5b1c0e01',
			type: 'long_text',
			label: 'What happened, and what could we have done better?',
			required: true
		},
		{
			id: '6b1f3c1e-8f0a-4c52-9d3e-2a7f5b1c0e02',
			type: 'yes_no',
			label: 'Would you like us to contact you about this?',
			required: true
		}
	],
	thank_you_title: 'Thank you for your feedback',
	thank_you_message:
		'We have passed this straight to our team. If you asked us to get in touch, we will contact you soon.'
};

export const DEFAULT_REVIEW_MESSAGE_STYLES: ReviewMessageStyles = {
	default_style: 'friendly',
	sms: {
		friendly: {
			body: 'Hi {{customer_first_name}}, thanks for choosing {{business_name}}! We would love to hear how we did. It only takes a minute: {{review_link}}'
		},
		professional: {
			body: 'Hello {{customer_first_name}}, thank you for choosing {{business_name}}. We would appreciate your feedback on the work we completed: {{review_link}}'
		},
		short: {
			body: 'Thanks from {{business_name}}! How did we do? {{review_link}}'
		}
	},
	email: {
		friendly: {
			subject: 'How did we do, {{customer_first_name}}?',
			body: 'Hi {{customer_first_name}},\n\nThank you for choosing {{business_name}}. We hope you are happy with the work.\n\nWould you take a minute to tell us how we did? Your feedback helps us improve and helps other customers find us.\n\n{{review_link}}\n\nThank you,\n{{business_name}}'
		},
		professional: {
			subject: 'Your feedback on your recent work with {{business_name}}',
			body: 'Hello {{customer_first_name}},\n\nThank you for choosing {{business_name}}. We would value your feedback on the work we recently completed for you.\n\nPlease share your experience here:\n{{review_link}}\n\nKind regards,\n{{business_name}}'
		},
		short: {
			subject: 'A quick question from {{business_name}}',
			body: 'Hi {{customer_first_name}},\n\nHow did we do? Let us know here: {{review_link}}\n\nThanks,\n{{business_name}}'
		}
	}
};

export const DEFAULT_ROUTING_GOOGLE_MIN_RATING = 4;
