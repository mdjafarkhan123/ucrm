import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { organizationFormatting } from '$lib/server/requests/timezone';

// One recorded payment for its detail screen. `public.payment_detail` is the read model: it re-checks
// invoices.view and invoices.view_price itself and refuses outright without them, because a payment with its
// amount withheld is not worth a screen — unlike an invoice, whose document and status still mean something.
// A refund or reversal comes back as not found: this screen is the receipt's home, and Part 6b-2b is
// read-only. Editing and deleting a payment is ledger-correction work and is deliberately not here.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;

	const supabase = event.locals.supabase;
	const { data: detail, error } = await supabase.rpc('payment_detail', {
		target_organization_id: check.auth.organization.id,
		target_payment_event_id: event.params.id
	});
	if (error) {
		if (error.code === 'P0404') return notFound('That payment could not be found.');
		return databaseError();
	}
	if (!detail) return notFound('That payment could not be found.');

	const formatting = await organizationFormatting(supabase, check.auth.organization.id);

	return json(
		{
			...(detail as Record<string, unknown>),
			locale: formatting.ok ? formatting.formatting.locale : 'en-US',
			// Sending the receipt opens a customer conversation, so the screen offers it only to somebody who
			// holds both halves — the same pair the send route itself enforces.
			can_send_receipt:
				hasPermission(check.access, 'invoices.record_payment') &&
				hasPermission(check.access, 'conversations.send')
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
