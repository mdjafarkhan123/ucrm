import { z } from 'zod';

const onboardingApplicationFieldsSchema = z.object({
	business_name: z.string().trim().min(1, 'Enter your business name.').max(160),
	main_contact_name: z.string().trim().min(1, 'Enter the main contact name.').max(160),
	main_contact_email: z
		.string()
		.trim()
		.toLowerCase()
		.email('Enter a valid contact email address.')
		.max(254),
	main_contact_phone: z.string().trim().min(1, 'Enter the main contact phone number.').max(40),
	is_administrator_same_as_contact: z.boolean(),
	initial_administrator_name: z.string().trim().min(1).max(160).nullish(),
	initial_administrator_email: z
		.string()
		.trim()
		.toLowerCase()
		.email('Enter a valid administrator email address.')
		.max(254)
		.nullish(),
	trade: z.string().trim().min(1, 'Enter your trade.').max(120),
	city_country: z.string().trim().min(1, 'Enter your city and country.').max(160),
	time_zone: z.string().trim().min(1, 'Enter your time zone.').max(64),
	note: z.string().trim().max(2000).nullish(),
	package_version_id: z.string().uuid('Choose a package.'),
	privacy_policy_agreed: z
		.boolean()
		.refine((value) => value === true, 'You must agree to the privacy policy to continue.'),
	turnstile_token: z.string().trim().optional().default('')
});

// The browser form hides the administrator fields while the contact is the administrator, so the
// server has to be the one that insists on them when they differ. Without this an application could
// be saved with nobody to send the account setup link to, and only fail much later at provisioning.
export const onboardingApplicationSubmissionSchema = onboardingApplicationFieldsSchema.superRefine(
	(value, ctx) => {
		if (value.is_administrator_same_as_contact) return;
		if (!value.initial_administrator_name)
			ctx.addIssue({
				code: 'custom',
				path: ['initial_administrator_name'],
				message: 'Enter the administrator name.'
			});
		if (!value.initial_administrator_email)
			ctx.addIssue({
				code: 'custom',
				path: ['initial_administrator_email'],
				message: 'Enter the administrator email address.'
			});
	}
);

export type OnboardingApplicationSubmission = z.infer<typeof onboardingApplicationSubmissionSchema>;

export function zodOnboardingApplicationFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
