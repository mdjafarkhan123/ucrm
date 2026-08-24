import type { RequestHandler } from './$types';
import { runQuoteCommand } from '$lib/server/quotes/commands';
import { quoteVisibilitySchema } from '$lib/server/validation/quotes.schema';

// How much of the arithmetic the customer's copy shows. It changes nothing about what the quote costs.
export const PATCH: RequestHandler = (event) =>
	runQuoteCommand(event, quoteVisibilitySchema, (input, quoteId) => ({
		name: 'set_quote_draft_visibility',
		args: {
			target_quote_id: quoteId,
			expected_revision: input.expected_revision,
			new_show_quantities: input.show_quantities,
			new_show_unit_prices: input.show_unit_prices,
			new_show_line_totals: input.show_line_totals,
			new_show_totals: input.show_totals
		}
	}));
