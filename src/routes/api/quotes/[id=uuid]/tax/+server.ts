import type { RequestHandler } from './$types';
import { runQuoteCommand } from '$lib/server/quotes/commands';
import { quoteTaxSchema } from '$lib/server/validation/quotes.schema';

// Re-resolve the effective default, freeze one saved rate, say No tax, or freeze a one-off custom rate —
// and optionally save that custom rate to the shared list.
export const PATCH: RequestHandler = (event) =>
	runQuoteCommand(event, quoteTaxSchema, (input, quoteId) => ({
		name: 'set_quote_draft_tax',
		args: {
			target_quote_id: quoteId,
			expected_revision: input.expected_revision,
			new_source: input.source,
			new_rate_id: input.rate_id,
			new_custom_name: input.custom_name,
			new_custom_rate_basis_points: input.custom_rate_basis_points,
			save_as_reusable: input.save_as_reusable
		}
	}));
