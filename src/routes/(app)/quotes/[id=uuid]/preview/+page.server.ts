import { error as httpError } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import type { CustomerQuoteDocument } from '$lib/quotes/customer-document';

type QuotePreview = {
	document: CustomerQuoteDocument;
	preview: {
		version_status: string;
		version_number: number;
		is_current_published: boolean;
		prices_withheld: boolean;
	};
};

// Preview as client, for the person who is about to send the quote. It reads the customer's document
// from the same database function that builds the customer's document, so what staff check here is what
// the client gets - not a second rendering that agrees with it today and drifts tomorrow.
//
// It creates nothing. No recipient, no link, no token: looking at your own quote is not sending it.
// This page breaks out of the app shell, so it does its own sign-in check rather than inheriting one.
export const load: PageServerLoad = async (event) => {
	await requireContractor(event);

	const { data, error } = await event.locals.supabase.rpc('quote_customer_preview', {
		target_quote_id: event.params.id
	});

	if (error) throw httpError(403, 'You do not have access to this quote.');
	if (!data) throw httpError(404, 'This quote has nothing to show yet.');

	return { preview: data as unknown as QuotePreview };
};
