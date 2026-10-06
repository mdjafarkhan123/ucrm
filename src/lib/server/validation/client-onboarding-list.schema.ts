import { z } from 'zod';
import { ONBOARDING_FILTERS } from '$lib/setup/onboarding-list';

export const clientOnboardingListQuerySchema = z.object({
	search: z.string().trim().max(200).optional(),
	waiting_on: z.enum(ONBOARDING_FILTERS).optional(),
	/** Opaque cursor from the previous page's `next_cursor`. */
	cursor: z.string().max(200).optional(),
	limit: z.coerce.number().int().min(1).max(100).optional(),
	/** E6: '1' lists delivered clients too; they are hidden by default. */
	delivered: z
		.enum(['0', '1'])
		.optional()
		.transform((value) => value === '1')
});
