export type ClientSortKey = 'updated_at' | 'name' | 'status';

export type ClientListFilters = {
	search: string;
	status: 'lead' | 'customer' | '';
	tagId: string;
	sort: ClientSortKey;
	dir: 'asc' | 'desc';
};

export type ClientListItem = {
	id: string;
	display_name: string;
	company_name: string | null;
	client_type: string;
	lifecycle_status: string;
	lead_source: string | null;
	archived_at: string | null;
	updated_at: string;
	primary_property: {
		id: string;
		label: string;
		address_line1: string;
		city: string;
		state_region: string | null;
		postal_code: string | null;
	} | null;
	additional_property_count: number;
	email: string | null;
	phone: string | null;
	tags: { id: string; name: string; color: string | null }[];
};

export type ClientListPage = {
	clients: ClientListItem[];
	// Null means this was the last page. The list is keyset paginated, so there is no page number to
	// jump to — the cursor is the only way to ask for what comes next.
	next_cursor: string | null;
};

export type ClientPreferences = {
	contact_policy: 'allow' | 'no_marketing' | 'do_not_disturb';
	quote_follow_ups: boolean;
	invoice_reminders: boolean;
	appointment_reminders: boolean;
	job_follow_ups: boolean;
	review_requests: boolean;
	marketing: boolean;
};

export type ClientPropertyInput = {
	label?: string;
	address_line1: string;
	address_line2?: string;
	city: string;
	state_region?: string;
	postal_code?: string;
	country?: string;
	access_notes?: string;
	is_billing_address?: boolean;
};

export type ClientWriteValues = {
	client_type: 'person' | 'company';
	lifecycle_status: 'lead' | 'customer';
	first_name?: string;
	last_name?: string;
	company_name?: string;
	email?: string;
	phone?: string;
	lead_source?: string;
	initial_note?: string;
	property?: ClientPropertyInput;
	preferences: ClientPreferences;
	tag_ids: string[];
};

/**
 * The client fields a detail-page block can stage. Blocks edit into a draft of this shape and one save
 * writes them together, so lead source, tags, and properties are deliberately not part of it.
 */
export type ClientIdentityDraft = {
	client_type: 'person' | 'company';
	lifecycle_status: 'lead' | 'customer';
	first_name: string;
	last_name: string;
	company_name: string;
	email: string;
	phone: string;
	preferences: ClientPreferences;
};

export type ClientProperty = ClientPropertyInput & {
	id: string;
	is_primary: boolean;
	is_billing_address: boolean;
};

export type ClientDetail = ClientWriteValues & {
	id: string;
	display_name: string;
	created_at: string;
	converted_to_customer_at: string | null;
	archived_at: string | null;
	primary_property: ClientProperty | null;
	/** Every property this client has, primary first. The form uses primary_property; the detail page uses this. */
	properties: ClientProperty[];
	property_count: number;
	preferences:
		(ClientPreferences & { sms_opt_out_at: string | null; sms_opt_in_at: string | null }) | null;
};

export type DuplicateCandidates = {
	exact: { id: string; display_name: string; matched_on: 'email' | 'phone' }[];
	similar: {
		id: string;
		display_name: string;
		reason: 'name' | 'address';
		detail: string | null;
	}[];
};

// A save that fails for a reason the form can show: bad fields, or a client already using that email
// or phone. Anything else throws a plain Error with a message worth showing.
export class ClientWriteError extends Error {
	fieldErrors: Record<string, string>;
	duplicates: DuplicateCandidates['exact'];

	constructor(
		message: string,
		fieldErrors: Record<string, string>,
		duplicates: DuplicateCandidates['exact']
	) {
		super(message);
		this.name = 'ClientWriteError';
		this.fieldErrors = fieldErrors;
		this.duplicates = duplicates;
	}
}

export const clientsListKey = (filters: ClientListFilters) => ['clients', 'list', filters] as const;

export const clientDetailKey = (clientId: string) => ['clients', 'detail', clientId] as const;

export async function fetchClient(clientId: string): Promise<ClientDetail> {
	const response = await fetch(`/api/clients/${clientId}`);
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'That client could not be loaded.');
	}
	const result = await response.json();
	return result.client;
}

export async function fetchDuplicateCandidates(input: {
	email?: string;
	phone?: string;
	name?: string;
	address?: string;
	excludeClientId?: string;
}): Promise<DuplicateCandidates> {
	const params = new URLSearchParams();
	if (input.email) params.set('email', input.email);
	if (input.phone) params.set('phone', input.phone);
	if (input.name) params.set('name', input.name);
	if (input.address) params.set('address', input.address);
	if (input.excludeClientId) params.set('exclude_id', input.excludeClientId);

	const response = await fetch(`/api/clients/duplicates?${params.toString()}`);
	if (!response.ok) return { exact: [], similar: [] };
	return response.json();
}

export async function saveClient(values: ClientWriteValues, clientId?: string) {
	const response = await fetch(clientId ? `/api/clients/${clientId}` : '/api/clients', {
		method: clientId ? 'PATCH' : 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(values)
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'That client could not be saved.',
			result.field_errors ?? {},
			result.duplicates ?? []
		);
	}
	return result.client as { id: string; display_name: string };
}

export async function updateProperty(propertyId: string, values: ClientPropertyInput) {
	const response = await fetch(`/api/properties/${propertyId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(values)
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'That address could not be saved.',
			result.field_errors ?? {},
			[]
		);
	}
	return result.property as ClientProperty;
}

export async function createProperty(clientId: string, values: ClientPropertyInput) {
	const response = await fetch('/api/properties', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...values, client_id: clientId })
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'That property could not be added.',
			result.field_errors ?? {},
			[]
		);
	}
	return result.property as ClientProperty;
}

export async function deleteProperty(propertyId: string) {
	const response = await fetch(`/api/properties/${propertyId}`, { method: 'DELETE' });
	if (response.ok) return;

	const result = await response.json().catch(() => ({}));
	throw new ClientWriteError(
		result.error ?? 'That property could not be removed.',
		result.field_errors ?? {},
		[]
	);
}

export async function fetchClients(
	filters: ClientListFilters,
	cursor?: string
): Promise<ClientListPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	if (filters.status) params.set('status', filters.status);
	if (filters.tagId) params.set('tag_id', filters.tagId);
	if (filters.sort !== 'updated_at') params.set('sort', filters.sort);
	if (filters.dir !== 'desc') params.set('dir', filters.dir);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/clients?${params.toString()}`);
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'Clients could not be loaded.');
	}
	return response.json();
}
