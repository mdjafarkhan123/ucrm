import { json } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

type Supabase = SupabaseClient<Database>;

export type DuplicateMatch = {
	id: string;
	display_name: string;
	matched_on: 'email' | 'phone';
};

export type SimilarMatch = {
	id: string;
	display_name: string;
	reason: 'name' | 'address';
	detail: string | null;
};

// The database stores these same normalized forms in a generated column, so the check the office sees
// and the rule the database enforces can never drift apart.
export function normalizeEmail(value: string | null | undefined) {
	const trimmed = (value ?? '').trim().toLowerCase();
	return trimmed === '' ? null : trimmed;
}

export function normalizePhone(value: string | null | undefined) {
	const digits = (value ?? '').replace(/[^0-9]/g, '');
	return digits === '' ? null : digits;
}

/**
 * Clients in this organization already using the same email or phone. An exact match blocks the save.
 * `excludeClientId` keeps a client from matching itself while it is being edited.
 */
export async function findExactDuplicates(
	supabase: Supabase,
	organizationId: string,
	input: { email?: string | null; phone?: string | null; excludeClientId?: string | null }
): Promise<{ matches: DuplicateMatch[] } | { failed: true }> {
	const email = normalizeEmail(input.email);
	const phone = normalizePhone(input.phone);
	if (!email && !phone) return { matches: [] };

	// One straight lookup per kind. Each matches the whole (organization_id, kind, normalized_value)
	// index, and the typed value never reaches a filter string it could break out of.
	const lookup = (kind: 'email' | 'phone', value: string) =>
		supabase
			.from('client_contact_methods')
			.select('client_id, kind')
			.eq('organization_id', organizationId)
			.eq('kind', kind)
			.eq('normalized_value', value);

	const [emailHits, phoneHits] = await Promise.all([
		email ? lookup('email', email) : null,
		phone ? lookup('phone', phone) : null
	]);
	if (emailHits?.error || phoneHits?.error) return { failed: true };

	const hits = [...(emailHits?.data ?? []), ...(phoneHits?.data ?? [])].filter(
		(method) => method.client_id !== input.excludeClientId
	);
	if (hits.length === 0) return { matches: [] };

	const { data: clients, error: clientsError } = await supabase
		.from('clients')
		.select('id, display_name')
		.eq('organization_id', organizationId)
		.in('id', [...new Set(hits.map((hit) => hit.client_id))]);
	if (clientsError) return { failed: true };

	const namesById = new Map((clients ?? []).map((client) => [client.id, client.display_name]));

	return {
		matches: hits
			.filter((hit) => namesById.has(hit.client_id))
			.map((hit) => ({
				id: hit.client_id,
				display_name: namesById.get(hit.client_id) as string,
				matched_on: hit.kind as 'email' | 'phone'
			}))
	};
}

const SIMILAR_LIMIT = 5;

/**
 * Clients that merely look alike. These warn and can be ignored; they never block a save and never
 * select or merge anything on the office's behalf.
 */
export async function findSimilarClients(
	supabase: Supabase,
	organizationId: string,
	input: { name?: string | null; address?: string | null; excludeClientId?: string | null }
): Promise<{ matches: SimilarMatch[] } | { failed: true }> {
	const name = (input.name ?? '').trim();
	const address = (input.address ?? '').trim();
	const matches: SimilarMatch[] = [];

	if (name.length >= 3) {
		const { data, error } = await supabase
			.from('clients')
			.select('id, display_name')
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.ilike('display_name', `%${escapeLike(name)}%`)
			.limit(SIMILAR_LIMIT);
		if (error) return { failed: true };
		for (const client of data ?? []) {
			if (client.id === input.excludeClientId) continue;
			matches.push({
				id: client.id,
				display_name: client.display_name,
				reason: 'name',
				detail: null
			});
		}
	}

	if (address.length >= 4) {
		const { data, error } = await supabase
			.from('properties')
			.select('client_id, address_line1, city')
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.ilike('address_line1', `%${escapeLike(address)}%`)
			.limit(SIMILAR_LIMIT);
		if (error) return { failed: true };

		const clientIds = [...new Set((data ?? []).map((property) => property.client_id))].filter(
			(clientId) => clientId !== input.excludeClientId
		);
		if (clientIds.length > 0) {
			const { data: clients, error: clientsError } = await supabase
				.from('clients')
				.select('id, display_name')
				.eq('organization_id', organizationId)
				.is('deleted_at', null)
				.in('id', clientIds);
			if (clientsError) return { failed: true };

			const addressByClient = new Map(
				(data ?? []).map((property) => [
					property.client_id,
					[property.address_line1, property.city].filter(Boolean).join(', ')
				])
			);
			for (const client of clients ?? []) {
				if (matches.some((match) => match.id === client.id)) continue;
				matches.push({
					id: client.id,
					display_name: client.display_name,
					reason: 'address',
					detail: addressByClient.get(client.id) ?? null
				});
			}
		}
	}

	return { matches };
}

// PostgREST treats %, _ and \ as pattern characters inside ilike.
function escapeLike(value: string) {
	return value.replace(/[\\%_]/g, (match) => `\\${match}`);
}

const FIELD_LABEL = { email: 'email address', phone: 'phone number' } as const;

/**
 * The one refusal an exact duplicate gets, whether it was caught before the write or by the database
 * during it. It names the client already using the value so the office can go straight there.
 */
export function duplicateResponse(matches: DuplicateMatch[], fallbackField?: 'email' | 'phone') {
	const fieldErrors: Record<string, string> = {};
	for (const match of matches) {
		fieldErrors[match.matched_on] =
			`${match.display_name} already uses this ${FIELD_LABEL[match.matched_on]}.`;
	}
	if (Object.keys(fieldErrors).length === 0 && fallbackField) {
		fieldErrors[fallbackField] = `Another client already uses this ${FIELD_LABEL[fallbackField]}.`;
	}

	return json(
		{
			error: 'This client is already in your list.',
			field_errors: fieldErrors,
			duplicates: matches
		},
		{ status: 409 }
	);
}

const ORGANIZATION_UNIQUE_INDEX = 'client_contact_methods_org_value_unique_idx';

/**
 * Reads a failed write from the database. The unique index is the final word on duplicates, so a save
 * that loses a race lands here and still tells the office exactly which field clashed.
 */
export function readWriteFailure(error: { code?: string; message?: string; details?: string }) {
	const text = `${error.message ?? ''} ${error.details ?? ''}`;

	if (error.code === '23505' && text.includes(ORGANIZATION_UNIQUE_INDEX)) {
		// Postgres reports the clashing values as "Key (organization_id, kind, normalized_value)=(…, phone, …)".
		const clashed = /=\([^,]+,\s*(email|phone)\s*,/.exec(text);
		const field: 'email' | 'phone' = clashed?.[1] === 'phone' ? 'phone' : 'email';
		return { kind: 'duplicate' as const, field };
	}
	if (error.code === 'P0002') return { kind: 'not_found' as const };
	if (error.code === '23514') return { kind: 'rule' as const, message: error.message ?? '' };
	return { kind: 'database' as const };
}
