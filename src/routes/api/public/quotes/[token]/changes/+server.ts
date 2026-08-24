import type { RequestHandler } from './$types';
import { handleCustomerDecision } from '$lib/server/quotes/customer-decision';
import { quoteCustomerChangeRequestSchema } from '$lib/server/validation/quotes.schema';

// "Not quite - here is what I would like different." The message is required, because a change request
// with nothing in it leaves the office guessing.
export const POST: RequestHandler = (event) =>
	handleCustomerDecision(event, 'changes_requested', quoteCustomerChangeRequestSchema);
