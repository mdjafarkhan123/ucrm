import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';

type DatabaseError = { code?: string; message?: string };

// `create_invoice_draft` refuses in a few named ways, and each raise already carries the sentence a person
// should read. A member without invoices.create or invoices.view_price, and a client or organization in
// another tenant, both come back as insufficient_privilege — a stranger learns nothing either way. A repeated
// idempotency key carrying different details is a conflict, not a reload prompt: the browser sends the person
// to the invoice that already started. The table's own checks (a bad subject, no lines, a due date before the
// invoice date) surface as a form error carrying the database's sentence, rather than a raw constraint
// violation.
export function createInvoiceError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That client could not be found.');
	if (error.code === 'P0404')
		return notFound(error.message ?? 'That client or organization could not be found.');
	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'That invoice was already started with different details.',
				reason: 'already_started'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'That invoice cannot be created as entered.' });
	return databaseError();
}

// The editing and lifecycle commands (`update_invoice_details`, `replace_invoice_lines`,
// `set_invoice_discount`, `set_invoice_tax`, `issue_invoice`, `delete_invoice_draft`) refuse in the same
// shapes. A member without the permission, or an invoice in another organization, comes back as
// insufficient_privilege — a stranger cannot tell which. A missing invoice is a not-found. A revision that no
// longer matches is a stale write: the browser is told to reload rather than overwrite someone else's change.
// A reused idempotency key carrying different details is a conflict the browser resolves by opening the
// invoice that already changed. The table's own checks — a voided or replaced bill, a bad rate, a due date
// before the invoice date, a draft that has been issued or still holds money — surface as a form error
// carrying the sentence the database already wrote.
export function updateInvoiceError(error: DatabaseError) {
	if (error.code === '42501') return notFound('That invoice could not be found.');
	if (error.code === 'P0404') return notFound(error.message ?? 'That invoice could not be found.');
	if (error.code === 'P0409')
		return json(
			{
				error: error.message ?? 'Someone else changed this invoice. Reload to see the latest.',
				// The same code carries two meanings: a create/issue/delete replay with different details is a
				// fresh start, everything else is a stale edit. The message the database wrote disambiguates it
				// for the reader; the reason keeps the edit path's reload-and-retry behaviour.
				reason: error.message?.includes('already started') ? 'already_started' : 'stale'
			},
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	if (error.code === '23514' || error.code === '23503')
		return validationError({ form: error.message ?? 'Those changes cannot be saved as entered.' });
	return databaseError();
}
