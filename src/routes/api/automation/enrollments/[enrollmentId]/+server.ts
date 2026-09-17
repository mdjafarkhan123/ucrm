import type { RequestHandler } from './$types';
import { handleEnrollmentControl } from '$lib/server/automation/enrollment-controls';

// CRM launch readiness Part 4 Stage 6: pause, resume, skip next step, or stop a website inquiry's follow-up from
// its Request or chat conversation. Same command path as the Quote detail.
export const POST: RequestHandler = (event) =>
	handleEnrollmentControl(event, event.params.enrollmentId);
