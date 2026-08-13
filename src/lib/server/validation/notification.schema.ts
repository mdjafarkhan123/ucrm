import { z } from 'zod';

export const notificationListQuerySchema = z.object({
	status: z.enum(['unread', 'all']).optional(),
	search: z.string().trim().max(200).optional(),
	limit: z.coerce.number().int().min(1).max(100).optional()
});

export const notificationTargetKinds = [
	'onboarding_application',
	'organization',
	'operation_attempt',
	'platform'
] as const;

/**
 * Three ways read state changes, all the same update from the database's point of view:
 * the bell's "Mark all read", the history page's per-row toggle, and opening a record that
 * a notification points at (which clears everything unread about that one record, so an
 * alert email you acted on stops nagging from the bell).
 */
export const notificationReadSchema = z.union([
	z.object({
		all: z.literal(true),
		read: z.literal(true).optional()
	}),
	z.object({
		ids: z.array(z.string().uuid()).min(1).max(100),
		read: z.boolean()
	}),
	z.object({
		target_kind: z.enum(notificationTargetKinds),
		target_id: z.string().uuid()
	})
]);
