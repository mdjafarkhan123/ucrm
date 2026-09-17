import type { RequestHandler } from './$types';
import { handleEnrollmentControl } from '$lib/server/automation/enrollment-controls';

// Contractor Settings Part 6D-5b: pause, resume, skip next step, or stop one enrollment shown on the Quote detail.
export const POST: RequestHandler = (event) =>
	handleEnrollmentControl(event, event.params.enrollmentId);
