import type { RequestHandler } from './$types';
import { runQuoteCommand } from '$lib/server/quotes/commands';
import { quoteCopySchema } from '$lib/server/validation/quotes.schema';

// The introduction above the price table and the message under it. The contract disclaimer stays with the
// title on the draft route, so no field has two owners.
export const PATCH: RequestHandler = (event) =>
	runQuoteCommand(event, quoteCopySchema, (input, quoteId) => ({
		name: 'set_quote_draft_copy',
		args: {
			target_quote_id: quoteId,
			expected_revision: input.expected_revision,
			new_introduction: input.introduction,
			new_client_message: input.client_message
		}
	}));
