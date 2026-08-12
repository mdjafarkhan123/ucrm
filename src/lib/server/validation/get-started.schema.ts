import { z } from 'zod';

export const onboardingApplicationSubmissionSchema = z.object({
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

export type OnboardingApplicationSubmission = z.infer<typeof onboardingApplicationSubmissionSchema>;

export function zodOnboardingApplicationFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
