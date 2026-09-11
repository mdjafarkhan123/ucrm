import { z } from 'zod';

export const globalSearchQuerySchema = z.object({
	q: z
		.string()
		.trim()
		.min(2, 'Enter at least 2 characters.')
		.max(100, 'Search must be 100 characters or fewer.')
});
