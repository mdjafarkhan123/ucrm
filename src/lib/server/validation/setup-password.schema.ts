import { z } from 'zod';

const administratorPassword = z
	.string()
	.min(8, 'Use at least 8 characters for the password.')
	.max(72, 'Use no more than 72 characters for the password.');

export const setupPasswordTokenSchema = z.string().trim().min(1, 'This setup link is invalid.');

export const setupPasswordSchema = z
	.object({
		token: setupPasswordTokenSchema,
		email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254),
		password: administratorPassword,
		password_confirmation: z.string().min(1, 'Confirm your new password.').max(72)
	})
	.refine((value) => value.password === value.password_confirmation, {
		path: ['password_confirmation'],
		message: 'Passwords do not match.'
	});

export function zodSetupPasswordFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
