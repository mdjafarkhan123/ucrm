import type { RequestHandler } from './$types';
import { handleCustomerDecision } from '$lib/server/quotes/customer-decision';
import { quoteCustomerDeclineSchema } from '$lib/server/validation/quotes.schema';

// "No thanks." The reason and the message are both optional; the card becomes Lost as Customer declined
// and the team is told inside the database command.
export const POST: RequestHandler = (event) =>
	handleCustomerDecision(event, 'declined', quoteCustomerDeclineSchema);
