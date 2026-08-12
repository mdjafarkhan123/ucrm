import { z } from 'zod';
import { TEMPLATE_KEYS } from '$lib/server/jafar/message-templates';

export const templateKeySchema = z.enum(TEMPLATE_KEYS);

export const templateDraftSchema = z.object({
	subject_draft: z.string().trim().max(300).nullable().optional(),
	body_draft: z.string().max(20000)
});

export const restoreVersionSchema = z.object({
	version: z.number().int().min(1).optional()
});
