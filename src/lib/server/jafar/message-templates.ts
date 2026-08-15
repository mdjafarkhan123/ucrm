export const TEMPLATE_KEYS = [
	'received_page',
	'application_receipt',
	'password_setup',
	'account_created_contact',
	'organization_closure_started',
	'organization_closure_fourteen_day_reminder',
	'organization_closure_three_day_reminder',
	'organization_closure_completed'
] as const;

export type TemplateKey = (typeof TEMPLATE_KEYS)[number];

export type PlaceholderDefinition = { key: string; label: string; required: boolean };

export const TEMPLATE_ROW_SELECT =
	'template_key, subject_draft, body_draft, subject_published, body_published, published_version, published_at, published_by_owner_email';

/**
 * Which merge tags each template may use, and which of those are required to stay in the
 * draft before it can publish. Required tags are exactly the ones the onboarding contract
 * calls out as protected (setup link, price, payment instructions) -- everything else,
 * including the plain-text safety wording in the password-setup email, stays freely editable.
 */
export const TEMPLATE_PLACEHOLDERS: Record<TemplateKey, PlaceholderDefinition[]> = {
	received_page: [
		{ key: 'package_name', label: 'Package name', required: true },
		{ key: 'price', label: 'Price', required: true },
		{ key: 'payment_instructions', label: 'Payment instructions', required: true }
	],
	application_receipt: [
		{ key: 'package_name', label: 'Package name', required: true },
		{ key: 'price', label: 'Price', required: true },
		{ key: 'payment_instructions', label: 'Payment instructions', required: true }
	],
	password_setup: [
		{ key: 'business_name', label: 'Business name', required: false },
		{ key: 'setup_link', label: 'Password setup link', required: true }
	],
	account_created_contact: [{ key: 'business_name', label: 'Business name', required: false }],
	organization_closure_started: [{ key: 'business_name', label: 'Business name', required: false }],
	organization_closure_fourteen_day_reminder: [
		{ key: 'business_name', label: 'Business name', required: false },
		{ key: 'closure_deadline_at', label: 'Closure deadline', required: true }
	],
	organization_closure_three_day_reminder: [
		{ key: 'business_name', label: 'Business name', required: false },
		{ key: 'closure_deadline_at', label: 'Closure deadline', required: true }
	],
	organization_closure_completed: [{ key: 'business_name', label: 'Business name', required: false }]
};

/** Returns the required tag keys missing from the given draft subject/body, e.g. `['price']`. */
export function missingRequiredPlaceholders(
	templateKey: TemplateKey,
	subject: string | null,
	body: string
) {
	const haystack = `${subject ?? ''}\n${body}`;
	return TEMPLATE_PLACEHOLDERS[templateKey]
		.filter((placeholder) => placeholder.required)
		.filter((placeholder) => !haystack.includes(`{{${placeholder.key}}}`))
		.map((placeholder) => placeholder.key);
}

/** Replaces `{{tag}}` merge tags with the given values. An unknown tag is left as-is. */
export function renderTemplate(text: string, values: Record<string, string>) {
	return text.replace(/{{\s*([a-z0-9_]+)\s*}}/gi, (match, key: string) =>
		Object.prototype.hasOwnProperty.call(values, key) ? values[key] : match
	);
}

/** Converts a rendered HTML email body into a readable plain-text fallback for Brevo's textContent field. */
export function htmlToPlainText(html: string) {
	return html
		.replace(/<br\s*\/?>/gi, '\n')
		.replace(/<\/p>/gi, '\n\n')
		.replace(/<[^>]+>/g, '')
		.replace(/&nbsp;/g, ' ')
		.replace(/&amp;/g, '&')
		.replace(/&lt;/g, '<')
		.replace(/&gt;/g, '>')
		.replace(/\n{3,}/g, '\n\n')
		.trim();
}
