import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound
} from '$lib/server/api/errors';
import { quoteWriteError } from '$lib/server/quotes/errors';

const NOT_FOUND = 'That quote could not be found.';

const QUOTE_SELECT = `id, quote_number, title, status, currency_code, client_id, property_id, request_id,
	 draft_version_id, current_published_version_id, archived_at, archive_reason, previous_status, created_at, updated_at,
	 sent_at, decision, decided_at, decision_method, decision_note,
	 client:clients!quotes_client_organization_fk(id, display_name, company_name),
	 property:properties!quotes_property_organization_fk(id, label, address_line1, address_line2, city, state_region, postal_code, country)`;

const VERSION_SELECT = `id, version_number, status, revision, contract_disclaimer, currency_code,
	 client_display_name, organization_name, service_address_line1, service_address_line2, service_city,
	 service_state_region, service_postal_code, service_country, created_at, introduction, client_message,
	 show_quantities, show_unit_prices, show_line_totals, show_totals, discount_name, discount_type,
	 discount_value, tax_source, tax_name, tax_rate_basis_points, tax_rate_id, published_at, deposit_type`;

// Money the reader may not see is never selected. The version's own totals are customer money, so they
// follow `quotes.view_price`; cost, profit, margin, and the itemized calculation are the business's own
// numbers and follow `quotes.view_cost`, which is a separate permission.
const VERSION_PRICE_COLUMNS =
	'subtotal_minor, discount_minor, tax_minor, total_minor, deposit_required_minor';
const VERSION_COST_COLUMNS = 'cost_minor, profit_minor, margin_basis_points, calculation';

const LINE_SELECT = `id, position, source_catalog_item_id, category, is_labor, name, description,
	 unit_label, quantity, is_taxable, image_attachment_id, line_kind, selection_kind,
	 is_recommended`;

const VERSION_ATTACHMENT_SELECT = 'id, attachment_id, position, customer_visible, display_name';

// Both carry money — a schedule installment's `value` and a receipt's `amount_minor` — so both stay behind
// `quotes.view_price`, the same as the version's own price columns above.
const SCHEDULE_ITEM_SELECT = 'id, position, description, value_type, value, is_deposit';
const DEPOSIT_EVENT_SELECT = `id, quote_version_id, event_type, amount_minor, method, reference, note,
	 reversed_event_id, created_at`;

const PRICE_COLUMNS = 'unit_price_minor, line_total_minor';
const COST_COLUMNS = 'unit_cost_minor, line_cost_total_minor';

// Money a person may not see is never selected in the first place. Dropping it after the fact would still
// have carried it over the wire, and a payload that never held it cannot leak it.
function columns(base: string, ...extra: Array<string | null>) {
	return [base, ...extra.filter(Boolean)].join(', ');
}

// A quote and the version a person is allowed to see, with everything the proposal is made of: its
// choice-aware lines and the files staged for the customer's copy.
//
// Staff work on the draft, so the draft is what comes back whenever there is one. Freezing a quote clears
// its draft pointer and moves it to the published snapshot, so a quote with nothing in progress reads its
// published version instead — otherwise a published quote would draw itself empty. The page is told which
// published version stands behind it, so it can name the version without pretending there is history that
// does not exist yet.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const canSeePrice = hasPermission(check.access, 'quotes.view_price');
	const canSeeCost = hasPermission(check.access, 'quotes.view_cost');
	const canEdit = hasPermission(check.access, 'quotes.edit');
	// The header only offers what this person could actually carry out. Sending and answering are separate
	// permissions from editing, so the page is told about each one rather than guessing from can_edit.
	const canSend = hasPermission(check.access, 'quotes.send');
	const canSendEmail = canSend && hasPermission(check.access, 'conversations.send');
	const canRecordDecision = hasPermission(check.access, 'quotes.record_decision');
	const canRecordDeposit = hasPermission(check.access, 'quotes.record_deposit');
	// Gates the Tax dialog's "save as a reusable rate" checkbox only — pricing a quote is not managing
	// Settings → Taxes, so this stays separate from `canEdit`.
	const canManageTaxes = hasPermission(check.access, 'settings.taxes.manage');

	const { data: quote, error } = await supabase
		.from('quotes')
		.select(QUOTE_SELECT)
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.maybeSingle();
	if (error) return databaseError();
	if (!quote) return notFound(NOT_FOUND);

	const publishedVersionId = quote.current_published_version_id;
	const versionId = quote.draft_version_id ?? publishedVersionId;
	const versionIds = [...new Set([versionId, publishedVersionId])].filter((id): id is string =>
		Boolean(id)
	);
	const [
		{ data: versions, error: versionError },
		{ data: lines, error: linesError },
		{ data: versionAttachments, error: versionAttachmentsError },
		{ data: contactMethods, error: contactMethodsError },
		{ data: signature },
		{ data: scheduleItems, error: scheduleItemsError },
		{ data: depositEvents, error: depositEventsError },
		{ data: readyForJob }
	] = await Promise.all([
		versionIds.length
			? supabase
					.from('quote_versions')
					.select(
						columns(
							VERSION_SELECT,
							canSeePrice ? VERSION_PRICE_COLUMNS : null,
							canSeeCost ? VERSION_COST_COLUMNS : null
						)
					)
					.eq('organization_id', organizationId)
					.in('id', versionIds)
			: Promise.resolve({ data: [], error: null }),
		versionId
			? supabase
					.from('quote_version_lines')
					.select(
						columns(
							LINE_SELECT,
							canSeePrice ? PRICE_COLUMNS : null,
							canSeeCost ? COST_COLUMNS : null
						)
					)
					.eq('organization_id', organizationId)
					.eq('quote_id', quote.id)
					.eq('quote_version_id', versionId)
					.order('position', { ascending: true })
					.order('id', { ascending: true })
			: Promise.resolve({ data: [], error: null }),
		versionId
			? supabase
					.from('quote_version_attachments')
					.select(VERSION_ATTACHMENT_SELECT)
					.eq('organization_id', organizationId)
					.eq('quote_id', quote.id)
					.eq('quote_version_id', versionId)
					.order('position', { ascending: true })
					.order('id', { ascending: true })
			: Promise.resolve({ data: [], error: null }),
		quote.client_id
			? supabase
					.from('client_contact_methods')
					.select('kind, value, is_primary')
					.eq('organization_id', organizationId)
					.eq('client_id', quote.client_id)
					.eq('is_primary', true)
			: Promise.resolve({ data: [], error: null }),
		// Only an approval is ever signed, and only the answer that currently counts is shown - a
		// revision ends the decision, so the signature goes quiet with it without anything being
		// deleted. The read goes through the command so the private object key stays in the database
		// and the page is told only whether there is a picture to ask for.
		quote.decision === 'approved'
			? supabase.rpc('quote_current_signature', { target_quote_id: quote.id })
			: Promise.resolve({ data: null }),
		// Both carry money, so neither is fetched at all for a reader without `quotes.view_price` — the
		// column never rides over the wire to be dropped on the client.
		versionId && canSeePrice
			? supabase
					.from('quote_version_schedule_items')
					.select(SCHEDULE_ITEM_SELECT)
					.eq('organization_id', organizationId)
					.eq('quote_id', quote.id)
					.eq('quote_version_id', versionId)
					.order('position', { ascending: true })
			: Promise.resolve({ data: [], error: null }),
		// A deposit receipt only ever binds to the version that was actually sent, never the draft still
		// being priced.
		quote.current_published_version_id && canSeePrice
			? supabase
					.from('quote_deposit_events')
					.select(DEPOSIT_EVENT_SELECT)
					.eq('organization_id', organizationId)
					.eq('quote_id', quote.id)
					.eq('quote_version_id', quote.current_published_version_id)
					.order('created_at', { ascending: true })
					.order('id', { ascending: true })
			: Promise.resolve({ data: [], error: null }),
		// A status fact, not money -- computed authoritatively in the database so a viewer without
		// `quotes.view_price` (the deposit rows above are withheld from) still gets the right answer.
		supabase.rpc('quote_ready_for_job', { target_quote_id: quote.id })
	]);
	if (
		versionError ||
		linesError ||
		versionAttachmentsError ||
		contactMethodsError ||
		scheduleItemsError ||
		depositEventsError
	)
		return databaseError();

	// The version columns are chosen at request time, so PostgREST cannot type the rows. Only the two
	// identity columns are read here; everything else is passed straight through.
	const versionRows = (versions ?? []) as unknown as Array<{ id: string; version_number: number }>;
	const version = versionRows.find((row) => row.id === versionId) ?? null;
	const publishedVersion = versionRows.find((row) => row.id === publishedVersionId) ?? null;

	const primaryContact = (kind: 'email' | 'phone') =>
		(contactMethods ?? []).find((method) => method.kind === kind)?.value ?? null;

	return json(
		{
			quote: {
				...quote,
				client: quote.client
					? {
							...quote.client,
							email: primaryContact('email'),
							phone: primaryContact('phone')
						}
					: null
			},
			version,
			published_version_number: publishedVersion?.version_number ?? null,
			lines: lines ?? [],
			version_attachments: versionAttachments ?? [],
			signature: signature ?? null,
			deposit_schedule_items: scheduleItems ?? [],
			deposit_events: depositEvents ?? [],
			ready_for_job: readyForJob ?? false,
			can_see_price: canSeePrice,
			can_see_cost: canSeeCost,
			can_edit: canEdit,
			can_send: canSend,
			can_send_email: canSendEmail,
			can_record_decision: canRecordDecision,
			can_record_deposit: canRecordDeposit,
			can_manage_taxes: canManageTaxes
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Removing a draft nobody has ever seen. Anything that has ever been sent, approved, declined, or made
// from a request is refused by the command itself - this route only forwards that refusal.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('delete_quote', {
		target_quote_id: event.params.id
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
