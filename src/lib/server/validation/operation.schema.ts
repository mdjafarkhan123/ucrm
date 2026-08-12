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
	status: operationStatusSchema.optional(),
	target_id: z.string().uuid().optional()
});

export const operationResolveSchema = z.object({
	note: z
		.string()
		.trim()
		.min(1, 'Enter a resolution note.')
		.max(500, 'Keep the note under 500 characters.')
});
