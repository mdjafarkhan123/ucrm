import { z } from 'zod';

export const ownerLoginSchema = z.object({
	email: z.string().trim().email('Enter a valid email address.').max(254),
	password: z.string().min(1, 'Enter your password.').max(256)
});

export const ownerReconfirmSchema = z.object({
	password: z.string().min(1, 'Enter your password.').max(256)
});

export const organizationLifecycleSchema = z.object({
	status: z.enum(['active', 'suspended'])
});

const calendarDate = z
	.string()
	.regex(/^\d{4}-\d{2}-\d{2}$/, 'Use a valid calendar date.')
	.refine((value) => {
		const date = new Date(`${value}T00:00:00Z`);
		return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
	}, 'Use a valid calendar date.');

export const freeAccessChangeSchema = z
	.object({
		action: z.enum(['grant', 'extend', 'convert_to_forever', 'end']),
		access_until_date: calendarDate.nullish(),
		reason: z.string().trim().min(1, 'Enter a private reason.').max(500)
	})
	.superRefine((value, context) => {
		if (value.action === 'grant' || value.action === 'extend') return;
		if (value.access_until_date) {
			context.addIssue({
				code: 'custom',
				path: ['access_until_date'],
				message: 'This action creates free access forever and cannot include an end date.'
			});
		}
	});

export function zodOwnerFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
