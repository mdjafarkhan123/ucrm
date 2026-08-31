import { z } from 'zod';

// Contractor Settings Part 6D-5b: the write envelopes for the Quote record-level Automation controls. Access
// (feature entitlement, the automations.control_enrollment permission, and platform authority) is decided by
// requireAutomationAccess before any of these parse; the atomic SECURITY DEFINER commands re-check ownership,
// state, and the idempotency key themselves (supabase/migrations/20260831055152_automation_enrollment_controls.sql).

const idempotencyKey = z.string().uuid();

// Read-only eligibility for one active recipe against this quote, shown before a manual enroll is confirmed.
export const previewEnrollmentSchema = z.object({ recipe_id: z.string().uuid() }).strict();

// Confirm a manual enroll. The browser mints a fresh idempotency key per confirm so a double-submit replays
// the first result rather than stacking a second enrollment.
export const manualEnrollSchema = z
	.object({
		recipe_id: z.string().uuid(),
		idempotency_key: idempotencyKey
	})
	.strict();

// The per-enrollment controls. Stop is the one reasoned action; its reason is optional and clamped short (the
// command trims and truncates to 200 and supplies a default when blank).
export const controlEnrollmentSchema = z.discriminatedUnion('action', [
	z.object({ action: z.literal('pause'), idempotency_key: idempotencyKey }).strict(),
	z.object({ action: z.literal('resume'), idempotency_key: idempotencyKey }).strict(),
	z.object({ action: z.literal('skip'), idempotency_key: idempotencyKey }).strict(),
	z
		.object({
			action: z.literal('stop'),
			reason: z.string().trim().max(200).optional(),
			idempotency_key: idempotencyKey
		})
		.strict()
]);

export type ControlEnrollmentBody = z.infer<typeof controlEnrollmentSchema>;
