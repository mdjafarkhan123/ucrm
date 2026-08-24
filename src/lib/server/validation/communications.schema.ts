import { z } from 'zod';

const senderConfiguration = {
	display_name: z.string().trim().min(1, 'Enter a sender name.').max(160),
	assigned_user_id: z.string().uuid('Choose an active team member.').nullable(),
	is_organization_default: z.boolean(),
	allows_manual: z.boolean(),
	allows_automated: z.boolean()
};

export const communicationSenderCreateSchema = z
	.object({
		domain_id: z.string().uuid('Choose a verified sending domain.'),
		email_address: z.string().trim().toLowerCase().email('Enter a valid email address.').max(320),
		...senderConfiguration,
		idempotency_key: z.string().uuid('Start a new sender attempt and try again.')
	})
	.refine((value) => value.allows_manual || value.allows_automated, {
		message: 'Allow manual or automated email.',
		path: ['allows_manual']
	});

export const communicationSenderUpdateSchema = z
	.object({
		...senderConfiguration,
		enabled: z.boolean(),
		idempotency_key: z.string().uuid('Start a new sender change and try again.')
	})
	.refine((value) => !value.enabled || value.allows_manual || value.allows_automated, {
		message: 'An enabled sender must allow manual or automated email.',
		path: ['allows_manual']
	});

export function communicationFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}

export const manualCommunicationEmailSchema = z.object({
	contact_method_id: z.string().uuid('Choose an email address for this customer.'),
	subject: z.string().trim().min(1, 'Enter a subject.').max(998),
	body: z.string().trim().min(1, 'Enter a message.').max(20_000),
	idempotency_key: z.string().uuid('Start a new email attempt and try again.')
});
