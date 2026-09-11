import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { embeddedOne } from '$lib/server/api/embedded';

const GROUP_LIMIT = 5;

export type CoreSearchPermissions = {
	clients: boolean;
	requests: boolean;
	quotes: boolean;
	jobs: boolean;
	invoices: boolean;
};

export type CoreSearchResult = {
	id: string;
	type: 'client' | 'request' | 'quote' | 'job' | 'invoice' | 'conversation';
	title: string;
	subtitle: string | null;
	href: string;
};

export type CoreSearchGroups = {
	clients?: CoreSearchResult[];
	requests?: CoreSearchResult[];
	quotes?: CoreSearchResult[];
	jobs?: CoreSearchResult[];
	invoices?: CoreSearchResult[];
	conversations?: CoreSearchResult[];
};

function likeTerm(term: string) {
	return `%${term.replace(/[\\%_]/g, (character) => `\\${character}`)}%`;
}

function orTerm(term: string) {
	return `"${likeTerm(term).replace(/"/g, '\\"')}"`;
}

function clientName(value: unknown) {
	const client = embeddedOne(value) as {
		display_name: string | null;
		company_name: string | null;
	} | null;
	return client?.display_name ?? client?.company_name ?? null;
}

async function searchClients(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	term: string
) {
	const quoted = orTerm(term);
	const [names, contacts] = await Promise.all([
		supabase
			.from('clients')
			.select('id, display_name, company_name, updated_at')
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.is('archived_at', null)
			.or(`display_name.ilike.${quoted},company_name.ilike.${quoted}`)
			.order('updated_at', { ascending: false })
			.limit(GROUP_LIMIT),
		supabase
			.from('client_contact_methods')
			.select('client_id')
			.eq('organization_id', organizationId)
			.ilike('value', likeTerm(term))
			.limit(GROUP_LIMIT)
	]);
	if (names.error) throw names.error;
	if (contacts.error) throw contacts.error;

	const namedRows = names.data ?? [];
	const namedIds = new Set(namedRows.map((row) => row.id));
	const contactIds = [
		...new Set((contacts.data ?? []).map((row) => row.client_id).filter((id) => !namedIds.has(id)))
	].slice(0, Math.max(0, GROUP_LIMIT - namedRows.length));
	let contactRows: typeof namedRows = [];
	if (contactIds.length > 0) {
		const result = await supabase
			.from('clients')
			.select('id, display_name, company_name, updated_at')
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.is('archived_at', null)
			.in('id', contactIds)
			.order('updated_at', { ascending: false })
			.limit(GROUP_LIMIT);
		if (result.error) throw result.error;
		contactRows = result.data ?? [];
	}

	return [...namedRows, ...contactRows].slice(0, GROUP_LIMIT).map((row) => ({
		id: row.id,
		type: 'client' as const,
		title: row.display_name,
		subtitle: row.company_name && row.company_name !== row.display_name ? row.company_name : null,
		href: `/clients/${row.id}`
	}));
}

async function searchRequests(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	term: string
) {
	const quoted = orTerm(term);
	const { data, error } = await supabase
		.from('requests')
		.select(
			'id, title, service_type, client:clients!requests_client_organization_fk(display_name, company_name)'
		)
		.eq('organization_id', organizationId)
		.neq('status', 'archived')
		.or(`title.ilike.${quoted},service_type.ilike.${quoted}`)
		.order('updated_at', { ascending: false })
		.limit(GROUP_LIMIT);
	if (error) throw error;

	return (data ?? []).map((row) => ({
		id: row.id,
		type: 'request' as const,
		title: row.title,
		subtitle: clientName(row.client) ?? row.service_type,
		href: `/requests/${row.id}`
	}));
}

async function searchQuotes(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	term: string
) {
	const quoted = orTerm(term);
	const number = Number.parseInt(term, 10);
	const filter = Number.isSafeInteger(number)
		? `title.ilike.${quoted},quote_number.eq.${number}`
		: `title.ilike.${quoted}`;
	const { data, error } = await supabase
		.from('quotes')
		.select(
			'id, quote_number, title, client:clients!quotes_client_organization_fk(display_name, company_name)'
		)
		.eq('organization_id', organizationId)
		.neq('status', 'archived')
		.or(filter)
		.order('updated_at', { ascending: false })
		.limit(GROUP_LIMIT);
	if (error) throw error;

	return (data ?? []).map((row) => ({
		id: row.id,
		type: 'quote' as const,
		title: `Quote #${row.quote_number} · ${row.title}`,
		subtitle: clientName(row.client),
		href: `/quotes/${row.id}`
	}));
}

async function searchJobs(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	term: string
) {
	const quoted = orTerm(term);
	const number = Number.parseInt(term, 10);
	const filter = Number.isSafeInteger(number)
		? `title.ilike.${quoted},job_number.eq.${number}`
		: `title.ilike.${quoted}`;
	const { data, error } = await supabase
		.from('job_list_rows')
		.select('id, job_number, title, client_display_name, client_company_name')
		.eq('organization_id', organizationId)
		.eq('status', 'active')
		.or(filter)
		.order('created_at', { ascending: false })
		.limit(GROUP_LIMIT);
	if (error) throw error;

	return (data ?? []).map((row) => ({
		id: row.id,
		type: 'job' as const,
		title: `Job #${row.job_number} · ${row.title}`,
		subtitle: row.client_display_name ?? row.client_company_name,
		href: `/jobs/${row.id}`
	}));
}

async function searchInvoices(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	term: string
) {
	const quoted = orTerm(term);
	const number = Number.parseInt(term, 10);
	const filter = Number.isSafeInteger(number)
		? `subject.ilike.${quoted},invoice_number.eq.${number}`
		: `subject.ilike.${quoted}`;
	const { data, error } = await supabase
		.from('invoices')
		.select(
			'id, invoice_number, subject, client:clients!invoices_client_organization_fk(display_name, company_name)'
		)
		.eq('organization_id', organizationId)
		.is('replaced_by_invoice_id', null)
		.or(filter)
		.order('updated_at', { ascending: false })
		.limit(GROUP_LIMIT);
	if (error) throw error;

	return (data ?? []).map((row) => ({
		id: row.id,
		type: 'invoice' as const,
		title: `Invoice #${row.invoice_number} · ${row.subject}`,
		subtitle: clientName(row.client),
		href: `/invoices/${row.id}`
	}));
}

export async function searchCoreRecords(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	term: string,
	permissions: CoreSearchPermissions
): Promise<CoreSearchGroups> {
	const searches = [
		permissions.clients
			? searchClients(supabase, organizationId, term).then(
					(results) => ['clients', results] as const
				)
			: null,
		permissions.requests
			? searchRequests(supabase, organizationId, term).then(
					(results) => ['requests', results] as const
				)
			: null,
		permissions.quotes
			? searchQuotes(supabase, organizationId, term).then((results) => ['quotes', results] as const)
			: null,
		permissions.jobs
			? searchJobs(supabase, organizationId, term).then((results) => ['jobs', results] as const)
			: null,
		permissions.invoices
			? searchInvoices(supabase, organizationId, term).then(
					(results) => ['invoices', results] as const
				)
			: null
	].filter((search) => search !== null);

	return Object.fromEntries(await Promise.all(searches));
}
