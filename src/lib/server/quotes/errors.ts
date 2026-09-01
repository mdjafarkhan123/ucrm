import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';

const REQUEST_NOT_FOUND = 'That request could not be found.';

type DatabaseError = { code?: string; message?: string };

// A stale save is not a failure, it is two people editing the same price table. 409 tells the browser to
// reload the lines and show what the other person did, rather than dropping either version on the floor.
function staleConflict(message: string) {
	return json({ error: message, reason: 'stale' }, { status: 409 });
}

// `replace_request_pricing_lines` refuses in four ways, and each one already carries the sentence a
// person should read. A missing request and somebody else's request come back as the same
// insufficient_privilege on purpose: a stranger learns nothing either way.
export function requestPricingWriteError(error: DatabaseError) {
	if (error.code === '42501') return notFound(REQUEST_NOT_FOUND);
	if (error.code === 'P0409')
		return staleConflict(
			error.message ?? 'Someone else changed this pricing while you were editing.'
		);
	if (error.code === '54000')
		return validationError({ lines: error.message ?? 'That is too many lines.' });
	if (error.code === '23514')
		return validationError({ form: error.message ?? 'That pricing is not allowed.' });
	return databaseError();
}

// Conversion refuses the same three ways, but its P0409 means "this request already became a quote under
// a different key", which is a conflict to show, not a reload prompt.
export function convertRequestError(error: DatabaseError) {
	if (error.code === '42501') return notFound(REQUEST_NOT_FOUND);
	if (error.code === 'P0409')
		return json(
			{ error: error.message ?? 'This request already has a quote.', reason: 'already_converted' },
			{ status: 409 }
		);
	if (error.code === '23514')
		return validationError({ form: error.message ?? 'This request cannot become a quote yet.' });
	return databaseError();
}

const QUOTE_NOT_FOUND = 'That quote could not be found.';

// The four quote commands refuse the same four ways as the pricing one, and each already carries the
// sentence a person should read. A missing quote and somebody else's quote are the same answer on
// purpose: a stranger learns nothing either way.
export function quoteWriteError(error: DatabaseError) {
	if (error.code === '42501') return notFound(QUOTE_NOT_FOUND);
	if (error.code === 'P0409')
		return staleConflict(
			error.message ?? 'Someone else changed this quote while you were editing.'
		);
	if (error.code === '54000')
		return validationError({ lines: error.message ?? 'That is too many lines.' });
	if (error.code === '23514')
		return validationError({ form: error.message ?? 'That change is not allowed.' });
	return databaseError();
}

// Catalog rows are written straight through PostgREST, so row level security answers with 42501 and the
// table's own checks answer with 23514 or 23505. There is no write function in between to phrase these.
export function catalogWriteError(error: DatabaseError) {
	if (error.code === '42501')
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{
				status: 403
			}
		);
	if (error.code === '23514')
		return validationError({ form: 'Check the name, price, and cost on this item.' });
	return databaseError();
}

// The three Price Book management commands raise rather than return: `settings.price_book.manage` is
// already checked at the route, so 42501 here only ever means the route's own check and the command's
// disagreed. A stale edit or delete comes back as `P0409`, the same code every other revision-protected
// command in the app uses -- deliberately not `serialization_failure` (40001): PostgREST retries that one,
// and a stale revision cannot become current through retrying (see the migration this replaced,
// 20260902110000_stale_revision_conflicts_are_not_retryable.sql). A duplicate active name gets its own case
// so the browser can point at the Name field instead of a generic form banner; "not found" and the
// name-length check both come back as `check_violation` (23514), matching Taxes.
export function catalogManageWriteError(error: DatabaseError) {
	if (error.code === '42501')
		return json(
			{ error: 'You do not have access to manage the Price Book.', reason: 'permission_denied' },
			{ status: 403 }
		);

	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'Someone else changed this item while you were editing.',
				reason: 'stale'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);

	if (error.code === '23505')
		return validationError({ name: error.message ?? 'That name is already in use.' });

	if (error.code === '23514')
		return validationError({ form: error.message ?? 'That change is not allowed.' });

	return databaseError();
}

// Conversion to a job refuses in three ways. A quote that already has one is a conflict to show — the
// browser sends the person to the job that exists rather than asking them to reload and press again.
export function convertQuoteToJobError(error: DatabaseError) {
	if (error.code === '42501') return notFound(QUOTE_NOT_FOUND);
	if (error.code === 'P0409')
		return json(
			{ error: error.message ?? 'This quote already has a job.', reason: 'already_converted' },
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '23514')
		return validationError({ form: error.message ?? 'This quote cannot become a job yet.' });
	return databaseError();
}
