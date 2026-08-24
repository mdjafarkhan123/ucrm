import type { RequestHandler } from './$types';
import { runQuoteCommand } from '$lib/server/quotes/commands';
import { quoteVersionAttachmentsSchema } from '$lib/server/validation/quotes.schema';

// Which files already uploaded to this quote belong in the customer's copy. Nothing is copied and nothing
// is made public: this records references, and the database refuses any file from another record.
export const PATCH: RequestHandler = (event) =>
	runQuoteCommand(event, quoteVersionAttachmentsSchema, (input, quoteId) => ({
		name: 'replace_quote_version_attachments',
		args: {
			target_quote_id: quoteId,
			expected_revision: input.expected_revision,
			new_attachments: input.attachments
		}
	}));
