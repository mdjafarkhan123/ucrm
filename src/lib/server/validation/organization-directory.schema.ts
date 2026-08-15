import { z } from 'zod';

export const organizationAttentionReasons = [
	'access_overdue',
	'expiring_soon',
	'administrator_missing',
	'administrator_ownership_unclear',
	'setup_or_recovery_failed',
	'legacy_review'
] as const;

export const organizationDirectoryQuerySchema = z.object({
	search: z.string().trim().max(200).optional(),
	attention_reason: z.enum(organizationAttentionReasons).optional(),
	/** Opaque cursor from the previous page's `next_cursor`, base64 of `created_at|id`. */
	cursor: z.string().max(200).optional(),
	limit: z.coerce.number().int().min(1).max(100).optional()
});
