import { z } from 'zod';

// CRM launch readiness Part 4, Stage 4: the contractor bell and the inquiry-alert recipients setting.

export const teamNotificationReadSchema = z.union([
	z.object({ all: z.literal(true) }).strict(),
	z.object({ ids: z.array(z.string().uuid()).min(1).max(100) }).strict()
]);

export const inquiryAlertRecipientsSchema = z
	.object({ user_ids: z.array(z.string().uuid()).max(50) })
	.strict();

// CRM launch readiness Part 12: My alerts and browser alerts on a computer.

export const alertPreferenceSchema = z
	.object({
		kind: z.string().trim().min(1).max(100),
		channel: z.enum(['email', 'browser']),
		enabled: z.boolean()
	})
	.strict();

export const pushSubscriptionSchema = z
	.object({
		endpoint: z.string().url().max(2048),
		keys: z
			.object({ p256dh: z.string().min(1).max(200), auth: z.string().min(1).max(100) })
			.strict(),
		label: z.string().trim().min(1).max(80)
	})
	.strict();

export const pushSubscriptionRemoveSchema = z.union([
	z.object({ endpoint: z.string().url().max(2048) }).strict(),
	z.object({ id: z.string().uuid() }).strict()
]);
