import { z } from 'zod';

// Time clock (docs/time-clock-behavior-contract.md). Whose timer it is never travels from the browser: the
// commands time the signed-in person, so there is nothing here to name someone else with.

export const startVisitTimerSchema = z.object({
	job_id: z.string().uuid('Choose the job to time.'),
	visit_id: z.string().uuid('Choose the visit to time.')
});

export type StartVisitTimerInput = z.infer<typeof startVisitTimerSchema>;

// Stop carries nothing — it always means "my running timer" — but an unexpected body is refused rather
// than ignored, so a caller that thinks it can name a timer finds out.
export const stopTimerSchema = z.object({}).strict();
