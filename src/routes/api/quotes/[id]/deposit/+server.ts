import type { RequestHandler } from './$types';
import { runQuoteCommand } from '$lib/server/quotes/commands';
import { quoteDepositSchema } from '$lib/server/validation/quotes.schema';

// The whole deposit shape at once: deposit-only, a payment schedule, or none. Sending a null type removes
// it, and every installment goes with it.
export const PATCH: RequestHandler = (event) =>
	runQuoteCommand(event, quoteDepositSchema, (input, quoteId) => ({
		name: 'set_quote_draft_deposit',
		args: {
			target_quote_id: quoteId,
			expected_revision: input.expected_revision,
			new_deposit_type: input.deposit_type,
			new_items: input.items.map((item) => ({
				description: item.description,
				type: item.type,
				value: item.value
			}))
		}
	}));
