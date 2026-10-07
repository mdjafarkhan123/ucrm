import { z } from 'zod';
import {
	CONTACT_METHOD_KINDS,
	LEAD_CONTACT_METHODS_MAX,
	LEAD_COUNTRY_FILTER_MAX,
	LEAD_SEARCH_MAX,
	LEAD_SORTS,
	LEAD_SOURCES,
	LEAD_STATUSES,
	isCountryCode
} from '$lib/jafar/leads';
import { calendarDate } from './owner.schema';

// A list arrives as one comma-separated value: `?status=new,later`. Every item must be allowed and none repeated,
// so a bad link is refused rather than half-applied.
function list<Value extends string>(allowed: readonly [Value, ...Value[]]) {
	return z
		.string()
		.max(1000)
		.transform((raw) => raw.split(',').map((part) => part.trim()))
		.pipe(z.array(z.enum(allowed)).min(1).max(allowed.length))
		.transform((items) => [...new Set(items)]);
}

const countryCode = z.string().trim().toUpperCase().refine(isCountryCode, 'Choose the country.');

export const leadListQuerySchema = z.object({
	search: z.string().trim().max(LEAD_SEARCH_MAX).optional(),
	status: list(LEAD_STATUSES).optional(),
	country: z
		.string()
		.max(1000)
		.transform((raw) => raw.split(',').map((part) => part.trim().toUpperCase()))
		.pipe(z.array(z.string().refine(isCountryCode)).min(1).max(LEAD_COUNTRY_FILTER_MAX))
		.transform((items) => [...new Set(items)])
		.optional(),
	source: list(LEAD_SOURCES).optional(),
	sort: z.enum(LEAD_SORTS).optional(),
	/** Opaque cursor from the previous page's `next_cursor`. */
	cursor: z.string().max(300).optional(),
	limit: z.coerce.number().int().min(1).max(100).optional()
});

export type LeadListQuery = z.infer<typeof leadListQuerySchema>;

// Empty text in a form field means "not given".
const optionalText = (max: number, message?: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullish()
		.transform((value) => (value ? value : null));

export const leadContactMethodSchema = z.object({
	kind: z.enum(CONTACT_METHOD_KINDS),
	value: z.string().trim().min(1, 'Enter the contact detail.').max(300),
	found_at: z.string().trim().min(1, 'Say where you found this detail.').max(300)
});

export const leadCreateSchema = z
	.object({
		business_name: z.string().trim().min(1, 'Enter the business name.').max(200),
		country_code: countryCode,
		trade: z.string().trim().min(1, 'Enter the trade.').max(120),
		source: z.enum(LEAD_SOURCES, { message: 'Choose how you found this business.' }),
		source_detail: optionalText(300),
		website: optionalText(300),
		contact_name: optionalText(120),
		fit_notes: optionalText(4000),
		lead_status: z.enum(LEAD_STATUSES).default('new'),
		next_action: optionalText(200),
		next_action_due_on: calendarDate.nullish().transform((value) => value ?? null),
		contact_methods: z
			.array(leadContactMethodSchema)
			.max(LEAD_CONTACT_METHODS_MAX, `Add at most ${LEAD_CONTACT_METHODS_MAX} contact details.`)
			.default([])
	})
	.superRefine((lead, context) => {
		// A next action is a dated step: both or neither.
		if (lead.next_action && !lead.next_action_due_on)
			context.addIssue({
				code: 'custom',
				path: ['next_action_due_on'],
				message: 'Choose when the next action is due.'
			});
		if (!lead.next_action && lead.next_action_due_on)
			context.addIssue({
				code: 'custom',
				path: ['next_action'],
				message: 'Say what the next action is.'
			});
		lead.contact_methods.forEach((method, index) => {
			if (method.kind === 'email' && !z.email().safeParse(method.value).success)
				context.addIssue({
					code: 'custom',
					path: ['contact_methods', index, 'value'],
					message: 'Enter a valid email address.'
				});
			if (
				(method.kind === 'phone' || method.kind === 'whatsapp') &&
				method.value.replace(/\D/g, '').length < 7
			)
				context.addIssue({
					code: 'custom',
					path: ['contact_methods', index, 'value'],
					message: 'Enter the full phone number, with its country code.'
				});
		});
	});

export type LeadCreateInput = z.infer<typeof leadCreateSchema>;

// What the add form sends while someone types, to warn about a business already on file.
export const leadDuplicateCheckSchema = z.object({
	business_name: z.string().trim().max(200).optional(),
	country_code: z
		.string()
		.trim()
		.toUpperCase()
		.refine((value) => value === '' || isCountryCode(value))
		.optional(),
	website: z.string().trim().max(300).optional(),
	emails: z.array(z.string().trim().max(300)).max(LEAD_CONTACT_METHODS_MAX).default([]),
	phones: z.array(z.string().trim().max(300)).max(LEAD_CONTACT_METHODS_MAX).default([])
});
