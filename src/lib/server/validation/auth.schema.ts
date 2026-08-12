import { z } from 'zod';

export const contractorLoginSchema = z.object({
	email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254),
	password: z.string().min(1, 'Enter your password.').max(256)
});

const contractorPassword = z
	.string()
	.min(8, 'Use at least 8 characters for the password.')
	.max(72, 'Use no more than 72 characters for the password.');

export const passwordResetRequestSchema = z.object({
	email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254)
});

export const passwordUpdateSchema = z
	.object({
		password: contractorPassword,
		password_confirmation: z.string().min(1, 'Confirm your new password.').max(72),
		current_password: z.string().max(256).optional()
	})
	.refine((value) => value.password === value.password_confirmation, {
		path: ['password_confirmation'],
		message: 'Passwords do not match.'
	});

export function zodAuthFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
