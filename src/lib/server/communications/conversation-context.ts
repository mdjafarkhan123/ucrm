import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { embeddedOne } from '$lib/server/api/embedded';
import { asMoneyMap } from '$lib/server/quotes/money';
import { CONTEXT_SECTION_LIMIT, type ContextSection } from '$lib/communications/context-sections';

// One tab of the inbox's customer context rail: the customer's latest records of one kind. Every reader
// asks for one row more than it shows, which is how a tab learns there is more without a second count query,
// and every one is scoped by organization and client so it rides that table's own client index.
//
// Money is withheld rather than zeroed. A member without the price permission gets `null`, never a number,
// and the gated money functions are not even asked for them -- the same rule the Quotes, Jobs and Invoices
// lists follow, so this rail can never show a figure those pages would hide.

type Scope = {
	supabase: SupabaseClient<Database>;
	organizationId: string;
	clientId: string;
	canSeePrice: boolean;
};

export type SectionRead = { ok: true; items: unknown[]; hasMore: boolean } | { ok: false };

const FETCH_LIMIT = CONTEXT_SECTION_LIMIT + 1;

function page(rows: unknown[]): SectionRead {
	return {
		ok: true,
		items: rows.slice(0, CONTEXT_SECTION_LIMIT),
		hasMore: rows.length > CONTEXT_SECTION_LIMIT
	};
}

async function readProperties({ supabase, organizationId, clientId }: Scope): Promise<SectionRead> {
	// `properties_client_active_idx (client_id, deleted_at, created_at)` gives this its scan and its order
	// for free -- ordering by created_at rather than is_primary/updated_at is what rides that index instead
	// of sorting after the fact.
	const { data, error } = await supabase
		.from('properties')
		.select('id, label, address_line1, city, state_region, postal_code')
		.eq('client_id', clientId)
		.eq('organization_id', organizationId)
		.is('deleted_at', null)
		.order('created_at', { ascending: false })
		.limit(FETCH_LIMIT);
	return error ? { ok: false } : page(data ?? []);
}

async function readRequests({ supabase, organizationId, clientId }: Scope): Promise<SectionRead> {
	const { data, error } = await supabase
		.from('requests')
		.select('id, title, status, created_at')
		.eq('client_id', clientId)
		.eq('organization_id', organizationId)
		.order('created_at', { ascending: false })
		.limit(FETCH_LIMIT);
	return error ? { ok: false } : page(data ?? []);
}

async function readQuotes({
	supabase,
	organizationId,
	clientId,
	canSeePrice
}: Scope): Promise<SectionRead> {
	// The total lives on the version a quote is currently working from: the draft while one is open, and the
	// published snapshot once the draft has been frozen away. Both pointers come back embedded, and the
	// totals are then read in one gated call for the whole tab.
	const { data, error } = await supabase
		.from('quotes')
		.select(
			`id, quote_number, title, status, currency_code, created_at,
			 draft:quote_versions!quotes_draft_version_organization_fk(id),
			 published:quote_versions!quotes_current_published_version_fk(id)`
		)
		.eq('client_id', clientId)
		.eq('organization_id', organizationId)
		.order('created_at', { ascending: false })
		.limit(FETCH_LIMIT);
	if (error) return { ok: false };

	const rows = (data ?? []).slice(0, CONTEXT_SECTION_LIMIT);
	const versionIdOf = (row: (typeof rows)[number]) =>
		(embeddedOne(row.draft) ?? embeddedOne(row.published))?.id ?? null;

	const versionIds = canSeePrice
		? rows.map(versionIdOf).filter((id): id is string => id !== null)
		: [];
	const { data: versionMoney, error: moneyError } = versionIds.length
		? await supabase.rpc('quote_version_money', { target_version_ids: versionIds })
		: { data: {}, error: null };
	if (moneyError) return { ok: false };
	const money = asMoneyMap(versionMoney);

	return {
		ok: true,
		hasMore: (data ?? []).length > CONTEXT_SECTION_LIMIT,
		items: rows.map((row) => {
			const versionId = versionIdOf(row);
			const total = versionId ? money[versionId]?.total_minor : undefined;
			return {
				id: row.id,
				quote_number: row.quote_number,
				title: row.title,
				status: row.status,
				currency_code: row.currency_code,
				created_at: row.created_at,
				total_minor: canSeePrice ? (typeof total === 'number' ? total : 0) : null
			};
		})
	};
}

async function readJobs({
	supabase,
	organizationId,
	clientId,
	canSeePrice
}: Scope): Promise<SectionRead> {
	// `job_list_rows` carries the status already worked out in the database (Upcoming, Today, Late, ...), so
	// nothing here re-derives one and this tab can never disagree with the Jobs list.
	const { data, error } = await supabase
		.from('job_list_rows')
		.select('id, job_number, title, derived_status, currency_code, created_at')
		.eq('organization_id', organizationId)
		.eq('client_id', clientId)
		.order('created_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(FETCH_LIMIT);
	if (error) return { ok: false };

	const rows = (data ?? []).slice(0, CONTEXT_SECTION_LIMIT);
	const ids = canSeePrice
		? rows.map((row) => row.id).filter((id): id is string => typeof id === 'string')
		: [];
	const { data: jobMoney, error: moneyError } = ids.length
		? await supabase.rpc('job_money', { target_job_ids: ids })
		: { data: {}, error: null };
	if (moneyError) return { ok: false };
	const money = asMoneyMap(jobMoney);

	return {
		ok: true,
		hasMore: (data ?? []).length > CONTEXT_SECTION_LIMIT,
		items: rows.map((row) => {
			const total = row.id ? money[row.id]?.total_minor : undefined;
			return {
				id: row.id,
				job_number: row.job_number,
				title: row.title,
				derived_status: row.derived_status,
				currency_code: row.currency_code,
				created_at: row.created_at,
				total_minor: canSeePrice ? (typeof total === 'number' ? total : 0) : null
			};
		})
	};
}

async function readInvoices({
	supabase,
	organizationId,
	clientId,
	canSeePrice
}: Scope): Promise<SectionRead> {
	// The same definer read the Invoices list uses: it carries the derived status (Awaiting payment, Past due,
	// Paid, ...) without ever selecting an amount, and `client_id_filter` walks `invoices_client_idx`.
	const { data, error } = await supabase.rpc('invoice_list_page', {
		target_organization_id: organizationId,
		client_id_filter: clientId,
		page_limit: FETCH_LIMIT
	});
	if (error) return { ok: false };

	const rows = (data ?? []).slice(0, CONTEXT_SECTION_LIMIT);
	const ids = canSeePrice ? rows.map((row) => row.id) : [];
	const { data: invoiceMoney, error: moneyError } = ids.length
		? await supabase.rpc('invoice_money', { target_invoice_ids: ids })
		: { data: {}, error: null };
	if (moneyError) return { ok: false };
	const money = asMoneyMap(invoiceMoney);

	return {
		ok: true,
		hasMore: (data ?? []).length > CONTEXT_SECTION_LIMIT,
		items: rows.map((row) => {
			const cell = money[row.id];
			return {
				id: row.id,
				invoice_number: row.invoice_number,
				subject: row.subject,
				derived_status: row.derived_status,
				currency_code: row.currency_code,
				due_date: row.due_date,
				created_at: row.created_at,
				total_minor: canSeePrice
					? typeof cell?.total_minor === 'number'
						? cell.total_minor
						: 0
					: null,
				remaining_minor: canSeePrice
					? typeof cell?.remaining_minor === 'number'
						? cell.remaining_minor
						: 0
					: null
			};
		})
	};
}

async function readPipeline({ supabase, organizationId, clientId }: Scope): Promise<SectionRead> {
	const { data, error } = await supabase
		.from('opportunities')
		.select('id, title, stage, outcome, created_at')
		.eq('client_id', clientId)
		.eq('organization_id', organizationId)
		// A Direct job was never a deal; it is already listed under Jobs.
		.is('job_id', null)
		.order('created_at', { ascending: false })
		.limit(FETCH_LIMIT);
	return error ? { ok: false } : page(data ?? []);
}

export function readContextSection(section: ContextSection, scope: Scope): Promise<SectionRead> {
	switch (section) {
		case 'properties':
			return readProperties(scope);
		case 'requests':
			return readRequests(scope);
		case 'quotes':
			return readQuotes(scope);
		case 'jobs':
			return readJobs(scope);
		case 'invoices':
			return readInvoices(scope);
		case 'pipeline':
			return readPipeline(scope);
	}
}
