// Contractor Settings Part 6D-3 (email) + Stage 7 (SMS): the allow-listed variables an automation message may
// contain.
//
// A contractor authors the follow-up copy as plain text. The only dynamic values they may insert are fixed
// tokens; the send path (private.render_automation_email / private.render_automation_sms) fills them from
// current truth, so no authored or customer text can become markup or an unresolved placeholder. Any other
// `{{...}}` token is rejected at save time — the builder offers only these, and the server validator enforces
// the same lists so the two cannot drift.

import { z } from 'zod';

// key = the token a contractor types; label = how the builder's insert menu names it.
export const AUTOMATION_EMAIL_VARIABLES = [
	{ token: 'customer_name', label: 'Customer name' },
	{ token: 'business_name', label: 'Your business name' },
	{ token: 'quote_number', label: 'Quote number' },
	{ token: 'quote_link', label: 'Quote link' }
] as const;

// SMS shares the same business-fact tokens minus quote_link: the SMS send path does not mint a customer
// access link yet (docs/communications-a2-implementation-plan.md §7 leaves this for a follow-up), so a text
// can never promise a link it cannot fill. If a contractor types {{quote_link}} in a text it must be
// rejected at save time, never sent out as a literal, broken placeholder.
export const AUTOMATION_SMS_VARIABLES = AUTOMATION_EMAIL_VARIABLES.filter(
	(variable) => variable.token !== 'quote_link'
);

export type AutomationEmailVariableToken = (typeof AUTOMATION_EMAIL_VARIABLES)[number]['token'];
export type AutomationSmsVariableToken = (typeof AUTOMATION_SMS_VARIABLES)[number]['token'];

// Matches every `{{...}}` placeholder, capturing the inner name. Deliberately strict: no inner whitespace, so
// the SQL renderer's exact `replace('{{customer_name}}', …)` always matches what was validated here.
const TOKEN_PATTERN = /\{\{([^}]*)\}\}/g;

// Returns the list of placeholder names in a string that are NOT in `allowed` (deduped, in order seen). An
// empty list means every placeholder is safe.
function unknownVariablesAgainst(allowed: ReadonlySet<string>, text: string): string[] {
	const unknown: string[] = [];
	const seen = new Set<string>();
	for (const match of text.matchAll(TOKEN_PATTERN)) {
		const name = match[1];
		if (!allowed.has(name) && !seen.has(name)) {
			seen.add(name);
			unknown.push(name);
		}
	}
	return unknown;
}

const EMAIL_ALLOWED_TOKENS = new Set<string>(AUTOMATION_EMAIL_VARIABLES.map((v) => v.token));
const SMS_ALLOWED_TOKENS = new Set<string>(AUTOMATION_SMS_VARIABLES.map((v) => v.token));

export function unknownEmailVariables(text: string): string[] {
	return unknownVariablesAgainst(EMAIL_ALLOWED_TOKENS, text);
}

export function unknownSmsVariables(text: string): string[] {
	return unknownVariablesAgainst(SMS_ALLOWED_TOKENS, text);
}

// A Zod refinement usable on any authored string. Rejects unknown placeholders with a plain message naming
// the first offender.
function withKnownVariablesOnly<T extends z.ZodType<string>>(
	schema: T,
	unknownVariables: (text: string) => string[]
) {
	return schema.superRefine((value, ctx) => {
		const unknown = unknownVariables(value);
		if (unknown.length > 0) {
			ctx.addIssue({
				code: 'custom',
				message: `"{{${unknown[0]}}}" is not a variable you can use here.`
			});
		}
	});
}

// Subject: single line, so a newline is rejected (it would break the email header). Body: multi-line allowed.
export const automationEmailSubjectSchema = withKnownVariablesOnly(
	z
		.string()
		.trim()
		.min(1)
		.max(300)
		.refine((value) => !/[\r\n]/.test(value), {
			message: 'The subject cannot span multiple lines.'
		}),
	unknownEmailVariables
);

export const automationEmailBodySchema = withKnownVariablesOnly(
	z.string().trim().min(1).max(5000),
	unknownEmailVariables
);

// Stage 7: the Send SMS action's body. The smaller SMS token set above; no subject. A shorter cap than email
// since the enqueue command already refuses anything over 10 segments — this just keeps the editor sane.
export const automationSmsBodySchema = withKnownVariablesOnly(
	z.string().trim().min(1).max(1000),
	unknownSmsVariables
);

// CRM launch readiness Part 4, Stage 6: a website inquiry has no quote yet, so its "Reply by text or email"
// copy may only use the business facts. private.enqueue_automation_inquiry_message renders the quote tokens as
// empty strings, which is why they are refused here rather than sent out blank.
export const AUTOMATION_INQUIRY_VARIABLES = AUTOMATION_EMAIL_VARIABLES.filter(
	(variable) => variable.token === 'customer_name' || variable.token === 'business_name'
);

const INQUIRY_ALLOWED_TOKENS = new Set<string>(AUTOMATION_INQUIRY_VARIABLES.map((v) => v.token));

export function unknownInquiryVariables(text: string): string[] {
	return unknownVariablesAgainst(INQUIRY_ALLOWED_TOKENS, text);
}

export const automationInquiryEmailSubjectSchema = withKnownVariablesOnly(
	z
		.string()
		.trim()
		.min(1)
		.max(300)
		.refine((value) => !/[\r\n]/.test(value), {
			message: 'The subject cannot span multiple lines.'
		}),
	unknownInquiryVariables
);

export const automationInquiryEmailBodySchema = withKnownVariablesOnly(
	z.string().trim().min(1).max(5000),
	unknownInquiryVariables
);

export const automationInquirySmsBodySchema = withKnownVariablesOnly(
	z.string().trim().min(1).max(1000),
	unknownInquiryVariables
);

// Client reminders Part 3: a visit or assessment reminder has no quote; it names the visit instead.
// private.enqueue_automation_appointment_email fills these from the visit's current date, time and address.
export const AUTOMATION_APPOINTMENT_VARIABLES = [
	{ token: 'customer_name', label: 'Customer name' },
	{ token: 'business_name', label: 'Your business name' },
	{ token: 'appointment_when', label: 'Visit date and time' },
	{ token: 'appointment_address', label: 'Visit address' }
] as const;

const APPOINTMENT_ALLOWED_TOKENS = new Set<string>(
	AUTOMATION_APPOINTMENT_VARIABLES.map((v) => v.token)
);

export function unknownAppointmentVariables(text: string): string[] {
	return unknownVariablesAgainst(APPOINTMENT_ALLOWED_TOKENS, text);
}

export const automationAppointmentEmailSubjectSchema = withKnownVariablesOnly(
	z
		.string()
		.trim()
		.min(1)
		.max(300)
		.refine((value) => !/[\r\n]/.test(value), {
			message: 'The subject cannot span multiple lines.'
		}),
	unknownAppointmentVariables
);

export const automationAppointmentEmailBodySchema = withKnownVariablesOnly(
	z.string().trim().min(1).max(5000),
	unknownAppointmentVariables
);
