import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, validationError } from '$lib/server/api/errors';
import {
	clientWriteSchema,
	deriveClientDisplayName,
	zodFieldErrors
} from '$lib/server/validation/foundation.schema';
import {
	duplicateResponse,
	findExactDuplicates,
	readWriteFailure
} from '$lib/server/clients/duplicates';

export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.create');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = clientWriteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;

	// Checked here so the office gets a useful message naming the existing client. The unique index
	// behind create_client is what actually settles two requests arriving at the same moment.
	const duplicates = await findExactDuplicates(event.locals.supabase, organizationId, parsed.data);
	if ('failed' in duplicates) return databaseError();
	if (duplicates.matches.length > 0) return duplicateResponse(duplicates.matches);

	// create_client keeps the client, contact methods, first property, note, tags, and preferences in
	// one transaction, so a partial failure leaves nothing behind.
	const { data, error } = await event.locals.supabase.rpc('create_client', {
		payload: {
			organization_id: organizationId,
			display_name: deriveClientDisplayName(parsed.data),
			...parsed.data
		}
	});

	if (error) {
		const failure = readWriteFailure(error);
		if (failure.kind === 'duplicate') {
			const raced = await findExactDuplicates(event.locals.supabase, organizationId, parsed.data);
			if ('failed' in raced) return databaseError();
			return duplicateResponse(raced.matches, failure.field);
		}
		return databaseError();
	}
	return json({ client: data }, { status: 201 });
};

const PAGE_SIZE_MAX = 50;
const PAGE_SIZE_DEFAULT = 25;

export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.view');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const supabase = event.locals.supabase;
	const params = event.url.searchParams;

	const search = params.get('search')?.trim() ?? '';
	const status = params.get('status');
	const tagId = params.get('tag_id');
	const page = Math.max(1, Number.parseInt(params.get('page') ?? '1', 10) || 1);
	const pageSize = Math.min(
		PAGE_SIZE_MAX,
		Math.max(
			1,
			Number.parseInt(params.get('page_size') ?? String(PAGE_SIZE_DEFAULT), 10) || PAGE_SIZE_DEFAULT
		)
	);

	// A tag filter narrows to a set of client ids before the main paged query, since Postgres can't express
	// "has this tag" as a plain column filter once tags live in their own assignment table.
	let tagFilteredClientIds: string[] | null = null;
	if (tagId) {
		const { data, error } = await supabase
			.from('tag_assignments')
			.select('entity_id')
			.eq('organization_id', organizationId)
			.eq('entity_type', 'client')
			.eq('tag_id', tagId);
		if (error) return databaseError();
		tagFilteredClientIds = (data ?? []).map((row) => row.entity_id);
		if (tagFilteredClientIds.length === 0) {
			return json({ clients: [], total_count: 0, page, page_size: pageSize });
		}
	}

	let query = supabase
		.from('clients')
		.select(
			'id, display_name, company_name, client_type, lifecycle_status, lead_source, archived_at, updated_at',
			{ count: 'exact' }
		)
		.eq('organization_id', organizationId)
		.is('deleted_at', null)
		.is('archived_at', null);

	if (search) {
		// PostgREST's or= filter string treats comma/parenthesis as syntax; quoting the value (and escaping
		// backslash/quote/ilike-wildcard characters inside it) keeps an arbitrary search term from being
		// parsed as extra filter clauses.
		const ilikeEscaped = search.replace(/[\\%_]/g, (match) => `\\${match}`);
		const quoted = `"%${ilikeEscaped.replace(/"/g, '\\"')}%"`;
		query = query.or(`display_name.ilike.${quoted},company_name.ilike.${quoted}`);
	}
	if (status === 'lead' || status === 'customer') query = query.eq('lifecycle_status', status);
	if (tagFilteredClientIds) query = query.in('id', tagFilteredClientIds);

	const from = (page - 1) * pageSize;
	const {
		data: clients,
		error,
		count
	} = await query.order('updated_at', { ascending: false }).range(from, from + pageSize - 1);
	if (error) return databaseError();

	const clientIds = (clients ?? []).map((client) => client.id);
	if (clientIds.length === 0) {
		return json({ clients: [], total_count: count ?? 0, page, page_size: pageSize });
	}

	const [
		{ data: properties, error: propertiesError },
		{ data: contactMethods, error: contactMethodsError },
		{ data: tagAssignments, error: tagAssignmentsError }
	] = await Promise.all([
		supabase
			.from('properties')
			.select('id, client_id, label, address_line1, city, state_region, postal_code, is_primary')
			.eq('organization_id', organizationId)
			.in('client_id', clientIds)
			.is('deleted_at', null),
		supabase
			.from('client_contact_methods')
			.select('client_id, kind, value')
			.eq('organization_id', organizationId)
			.in('client_id', clientIds)
			.eq('is_primary', true),
		supabase
			.from('tag_assignments')
			.select('entity_id, tag_id')
			.eq('organization_id', organizationId)
			.eq('entity_type', 'client')
			.in('entity_id', clientIds)
	]);
	if (propertiesError || contactMethodsError || tagAssignmentsError) return databaseError();

	const propertiesByClient = new Map<string, NonNullable<typeof properties>>();
	for (const property of properties ?? []) {
		const list = propertiesByClient.get(property.client_id) ?? [];
		list.push(property);
		propertiesByClient.set(property.client_id, list);
	}

	const contactByClient = new Map<string, { email: string | null; phone: string | null }>();
	for (const method of contactMethods ?? []) {
		const entry = contactByClient.get(method.client_id) ?? { email: null, phone: null };
		if (method.kind === 'email') entry.email = method.value;
		if (method.kind === 'phone') entry.phone = method.value;
		contactByClient.set(method.client_id, entry);
	}

	const tagIdsByClient = new Map<string, string[]>();
	for (const assignment of tagAssignments ?? []) {
		const list = tagIdsByClient.get(assignment.entity_id) ?? [];
		list.push(assignment.tag_id);
		tagIdsByClient.set(assignment.entity_id, list);
	}
	const allTagIds = [...new Set([...tagIdsByClient.values()].flat())];
	let tagsById = new Map<string, { id: string; name: string; color: string | null }>();
	if (allTagIds.length > 0) {
		const { data: tags, error: tagsError } = await supabase
			.from('tags')
			.select('id, name, color')
			.in('id', allTagIds);
		if (tagsError) return databaseError();
		tagsById = new Map((tags ?? []).map((tag) => [tag.id, tag]));
	}

	const result = (clients ?? []).map((client) => {
		const clientProperties = propertiesByClient.get(client.id) ?? [];
		const primaryProperty =
			clientProperties.find((property) => property.is_primary) ?? clientProperties[0] ?? null;
		const contact = contactByClient.get(client.id) ?? { email: null, phone: null };
		const tags = (tagIdsByClient.get(client.id) ?? [])
			.map((tagId) => tagsById.get(tagId))
			.filter((tag) => tag !== undefined);

		return {
			...client,
			primary_property: primaryProperty,
			additional_property_count: Math.max(0, clientProperties.length - (primaryProperty ? 1 : 0)),
			email: contact.email,
			phone: contact.phone,
			tags
		};
	});

	return json({ clients: result, total_count: count ?? 0, page, page_size: pageSize });
};
