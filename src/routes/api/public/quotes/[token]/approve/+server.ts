import type { RequestHandler } from './$types';
import { handleCustomerDecision } from '$lib/server/quotes/customer-decision';
import { quoteCustomerApprovalSchema } from '$lib/server/validation/quotes.schema';

// "Yes, go ahead." A note is welcome but never required - nobody should have to write a sentence to say
// yes.
export const POST: RequestHandler = (event) =>
	handleCustomerDecision(event, 'approved', quoteCustomerApprovalSchema);
