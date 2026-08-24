import { z } from 'zod';

const optionalText = z.string().trim().max(500).optional().or(z.literal(''));

export const propertyAddressSchema = z.object({
	label: z.string().trim().min(2, 'Enter a property label.').max(120).optional().or(z.literal('')),
	address_line1: z.string().trim().min(2, 'Enter an address.').max(160),
	address_line2: optionalText,
	city: z.string().trim().min(2, 'Enter a city.').max(80),
	state_region: z.string().trim().max(80).optional().or(z.literal('')),
	postal_code: z.string().trim().max(20).optional().or(z.literal('')),
	country: z.string().trim().length(2).default('US'),
	access_notes: optionalText,
	// No default. A missing flag means "leave it alone", so editing an address cannot silently clear which
	// property the bills go to.
	is_billing_address: z.boolean().optional(),
	// Null means inherit the Business default; a saved rate's id pins this property to it. Omitted means
	// "leave it alone"; the composite FK is what actually stops a rate from another org.
	tax_rate_id: z.string().uuid().nullable().optional()
});

// The simple contact policy the office sees first. It sits on top of the detailed choices below and
// never erases them, so switching to "Do not disturb" and back restores exactly what was saved.
export const contactPolicySchema = z.enum(['allow', 'no_marketing', 'do_not_disturb']);

export const clientPreferencesSchema = z.object({
	contact_policy: contactPolicySchema.default('allow'),
	quote_follow_ups: z.boolean().default(true),
	invoice_reminders: z.boolean().default(true),
	appointment_reminders: z.boolean().default(true),
	job_follow_ups: z.boolean().default(true),
	review_requests: z.boolean().default(true),
	// Marketing stays off until valid consent exists.
	marketing: z.boolean().default(false)
});

export const clientWriteSchema = z
	.object({
		client_type: z.enum(['person', 'company']).default('person'),
		lifecycle_status: z.enum(['lead', 'customer']).default('lead'),
		first_name: optionalText,
		last_name: optionalText,
		company_name: optionalText,
		email: z.string().trim().email('Enter a valid email.').max(254).optional().or(z.literal('')),
		phone: z.string().trim().max(40).optional().or(z.literal('')),
		lead_source: z.string().trim().max(80).optional().or(z.literal('')),
		lead_temperature: z.enum(['hot', 'warm', 'cold']).optional(),
		initial_note: optionalText,
		property: propertyAddressSchema.optional(),
		preferences: clientPreferencesSchema.default({
			contact_policy: 'allow',
			quote_follow_ups: true,
			invoice_reminders: true,
			appointment_reminders: true,
			job_follow_ups: true,
			review_requests: true,
			marketing: false
		}),
		tag_ids: z.array(z.string().uuid()).max(30).default([])
	})
	.superRefine((value, context) => {
		if (value.client_type === 'person') {
			if (!value.first_name)
				context.addIssue({ code: 'custom', path: ['first_name'], message: 'Enter a first name.' });
			if (!value.last_name)
				context.addIssue({ code: 'custom', path: ['last_name'], message: 'Enter a last name.' });
			return;
		}
		if (!value.company_name)
			context.addIssue({
				code: 'custom',
				path: ['company_name'],
				message: 'Enter a company name.'
			});
	});

export type ClientWriteInput = z.infer<typeof clientWriteSchema>;

// One place decides what a client is called, so the list, the header, and search never disagree.
export function deriveClientDisplayName(input: ClientWriteInput) {
	if (input.client_type === 'company') return (input.company_name ?? '').trim();
	return [input.first_name, input.last_name]
		.map((part) => (part ?? '').trim())
		.filter(Boolean)
		.join(' ');
}

// Creating a property needs a client and nothing more than editing one does. The name stays optional here
// too — the route falls back to the street so the list still reads well.
export const propertySchema = propertyAddressSchema.extend({
	client_id: z.string().uuid('Choose a client.')
});

export const requestSchema = z.object({
	client_id: z.string().uuid('Choose a client.'),
	property_id: z.string().uuid('Choose a property.'),
	title: z.string().trim().min(2, 'Enter a request title.').max(160),
	description: optionalText,
	service_type: z.string().trim().max(120).optional().or(z.literal('')),
	source: z.string().trim().min(1).max(80).default('staff'),
	preferred_time: z.string().trim().max(120).optional().or(z.literal(''))
});

// The six values requests actually store. `upcoming`, `today`, and `overdue` are never stored — they are
// worked out from the assessment's start time when the request is read.
export const requestStatusSchema = z.enum([
	'new',
	'unscheduled',
	'assessment_completed',
	'completed',
	'converted',
	'archived'
]);

// Every field optional: each block on the request detail page saves only what it owns. Client and
// property move together, so changing one without the other is rejected in the route.
export const requestPatchSchema = z
	.object({
		client_id: z.string().uuid('Choose a client.'),
		property_id: z.string().uuid('Choose a property.'),
		title: z.string().trim().min(2, 'Enter a request title.').max(160),
		description: optionalText,
		service_type: z.string().trim().max(120).or(z.literal('')),
		preferred_time: z.string().trim().max(120).or(z.literal('')),
		status: requestStatusSchema
	})
	.partial()
	.refine((value) => Object.keys(value).length > 0, { message: 'Nothing to save.' })
	.refine((value) => value.status !== 'archived', {
		path: ['status'],
		message: 'Archiving now happens from the sales pipeline (Mark as lost).'
	});

// Booking, rescheduling, and unscheduling all go through this one shape. Both times null is Jobber's
// "unscheduled" state, which is a legitimate save, not a missing field.
export const assessmentWriteSchema = z
	.object({
		starts_at: z.iso.datetime({ offset: true }).nullable().default(null),
		ends_at: z.iso.datetime({ offset: true }).nullable().default(null),
		all_day: z.boolean().default(false),
		instructions: z.string().trim().max(2000).nullable().default(null),
		assignee_ids: z.array(z.string().uuid()).max(20).default([])
	})
	.refine((value) => (value.starts_at === null) === (value.ends_at === null), {
		path: ['starts_at'],
		message: 'Set both a start and an end time, or leave the assessment unscheduled.'
	})
	.refine(
		(value) =>
			value.starts_at === null ||
			value.ends_at === null ||
			Date.parse(value.ends_at) > Date.parse(value.starts_at),
		{ path: ['ends_at'], message: 'The end time has to come after the start time.' }
	);

export const assessmentCompleteSchema = z.object({
	// False reopens an assessment marked complete by mistake.
	complete: z.boolean().default(true)
});

export function zodFieldErrors(error: z.ZodError) {
	return Object.fromEntries(issueEntries(error));
}

// Nested paths keep their full name ("property.city") so a form can highlight the exact field that
// failed instead of marking the whole address block.
function issueEntries(error: z.ZodError) {
	return error.issues.map(
		(issue) => [issue.path.length > 0 ? issue.path.join('.') : 'form', issue.message] as const
	);
}
