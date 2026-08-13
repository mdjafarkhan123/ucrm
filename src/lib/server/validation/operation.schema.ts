import { z } from 'zod';

export const operationStatusSchema = z.enum([
	'pending',
	'retrying',
	'succeeded',
	'acknowledged',
	'manually_resolved'
]);

export const operationIdSchema = z.string().uuid();

export const operationListQuerySchema = z.object({
	/**
	 * No status means the working view: everything that has not succeeded. `all` is the
	 * explicit opt-in to see succeeded attempts too, which is what a link into one specific
	 * operation needs, since it may well have succeeded on retry before Jafar opened it.
	 */
	status: z.union([operationStatusSchema, z.literal('all')]).optional(),
	target_id: z.string().uuid().optional()
});

export const operationResolveSchema = z.object({
	note: z
		.string()
		.trim()
		.min(1, 'Enter a resolution note.')
		.max(500, 'Keep the note under 500 characters.')
});
