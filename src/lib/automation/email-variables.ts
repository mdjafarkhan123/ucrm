// Contractor Settings Part 6D-3: the allow-listed variables an automation email may contain.
//
// A contractor authors the follow-up email's subject and body as plain text. The only dynamic values they may
// insert are these fixed tokens; the send path (private.render_automation_email) fills them from current
// truth and escapes everything, so no authored or customer text can become markup. Any other `{{...}}` token
// is rejected at save time — the builder offers only these, and the server validator enforces the same list
// so the two cannot drift.

import { z } from 'zod';

// key = the token a contractor types; label = how the builder's insert menu names it.
export const AUTOMATION_EMAIL_VARIABLES = [
	{ token: 'customer_name', label: 'Customer name' },
	{ token: 'business_name', label: 'Your business name' },
	{ token: 'quote_number', label: 'Quote number' },
	{ token: 'quote_link', label: 'Quote link' }
] as const;

export type AutomationEmailVariableToken = (typeof AUTOMATION_EMAIL_VARIABLES)[number]['token'];

const ALLOWED_TOKENS = new Set<string>(AUTOMATION_EMAIL_VARIABLES.map((v) => v.token));

// Matches every `{{...}}` placeholder, capturing the inner name. Deliberately strict: no inner whitespace, so
// the SQL renderer's exact `replace('{{customer_name}}', …)` always matches what was validated here.
const TOKEN_PATTERN = /\{\{([^}]*)\}\}/g;

// Returns the list of placeholder names in a string that are NOT allow-listed (deduped, in order seen). An
// empty list means every placeholder is safe.
export function unknownEmailVariables(text: string): string[] {
	const unknown: string[] = [];
	const seen = new Set<string>();
	for (const match of text.matchAll(TOKEN_PATTERN)) {
		const name = match[1];
		if (!ALLOWED_TOKENS.has(name) && !seen.has(name)) {
			seen.add(name);
			unknown.push(name);
		}
	}
	return unknown;
}

// A Zod refinement usable on any authored email string. Rejects unknown placeholders with a plain message
// naming the first offender.
function withKnownVariablesOnly<T extends z.ZodType<string>>(schema: T) {
	return schema.superRefine((value, ctx) => {
		const unknown = unknownEmailVariables(value);
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
		})
);

export const automationEmailBodySchema = withKnownVariablesOnly(z.string().trim().min(1).max(5000));
