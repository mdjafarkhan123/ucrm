import { z } from 'zod';

// CRM launch readiness Part 4, Stage 4: the contractor bell and the inquiry-alert recipients setting.

export const teamNotificationReadSchema = z.union([
	z.object({ all: z.literal(true) }).strict(),
	z.object({ ids: z.array(z.string().uuid()).min(1).max(100) }).strict()
]);

export const inquiryAlertRecipientsSchema = z
	.object({ user_ids: z.array(z.string().uuid()).max(50) })
	.strict();
