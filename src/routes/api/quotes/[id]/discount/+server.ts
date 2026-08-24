import type { RequestHandler } from './$types';
import { runQuoteCommand } from '$lib/server/quotes/commands';
import { quoteDiscountSchema } from '$lib/server/validation/quotes.schema';

// One discount on the quote, with the name the customer reads. Sending a null type removes it.
export const PATCH: RequestHandler = (event) =>
	runQuoteCommand(event, quoteDiscountSchema, (input, quoteId) => ({
		name: 'set_quote_draft_discount',
		args: {
			target_quote_id: quoteId,
			expected_revision: input.expected_revision,
			new_name: input.name,
			new_type: input.type,
			new_value: input.value
		}
	}));
