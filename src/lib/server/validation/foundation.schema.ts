import { z } from 'zod';

const optionalText = z.string().trim().max(500).optional().or(z.literal(''));

export const contactSchema = z.object({
	display_name: z.string().trim().min(2, 'Enter a customer name.').max(160),
	first_name: optionalText,
	last_name: optionalText,
	company_name: optionalText,
	email: z.string().trim().email('Enter a valid email.').max(254).optional().or(z.literal('')),
	phone: z.string().trim().max(40).optional().or(z.literal('')),
	source: z.string().trim().max(80).optional().or(z.literal('')),
	notes: optionalText
});

export const propertySchema = z.object({
	contact_id: z.string().uuid('Choose a customer.'),
	label: z.string().trim().min(2, 'Enter a property label.').max(120),
	address_line1: z.string().trim().min(2, 'Enter an address.').max(160),
	address_line2: optionalText,
	city: z.string().trim().min(2, 'Enter a city.').max(80),
	state_region: z.string().trim().max(80).optional().or(z.literal('')),
	postal_code: z.string().trim().max(20).optional().or(z.literal('')),
	country: z.string().trim().length(2).default('US'),
	access_notes: optionalText
});

export const requestSchema = z.object({
	contact_id: z.string().uuid('Choose a customer.'),
	property_id: z.string().uuid('Choose a property.'),
	title: z.string().trim().min(2, 'Enter a request title.').max(160),
	description: optionalText,
	service_type: z.string().trim().max(120).optional().or(z.literal('')),
	source: z.string().trim().min(1).max(80).default('staff'),
	preferred_time: z.string().trim().max(120).optional().or(z.literal(''))
});

export function zodFieldErrors(error: z.ZodError) {
	return Object.fromEntries(issueEntries(error));
}

function issueEntries(error: z.ZodError) {
	return error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const);
}
