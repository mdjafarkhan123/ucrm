import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

type PriceListRow = {
	country: string;
	offered: boolean;
	price: {
		segment: { rate: number; currency: string } | null;
		mms: { rate: number; currency: string } | null;
	} | null;
	number: { monthly: number | null; setup: number | null } | null;
};

const requestSchema = z.object({ country_code: z.string().regex(/^[A-Z]{2}$/) });

// Stage 10 Part 5c (`concept.pen` board `xGLYB`): the countries a business texts or asked for, and what texting any
// other country would cost, for "Text customers in another country". Uplift's own costs never leave the server;
// countries Uplift doesn't offer are only named so the list can leave them out.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const client = getOwnerSupabaseClient();
	const [destinations, prices] = await Promise.all([
		client
			.from('communication_sms_destinations')
			.select('country_code, status, is_home')
			.eq('organization_id', check.auth.organization.id),
		client.rpc('communication_sms_price_list')
	]);
	if (destinations.error || prices.error) {
		console.error('Could not load the texting countries.', destinations.error ?? prices.error);
		return databaseError();
	}

	const rows = ((prices.data as { countries?: PriceListRow[] } | null)?.countries ?? []).filter(
		(row) => row.offered
	);
	return json(
		{
			destinations: (destinations.data ?? []).map((row) => ({
				country: row.country_code,
				status: row.status,
				is_home: row.is_home
			})),
			not_offered: ((prices.data as { countries?: PriceListRow[] } | null)?.countries ?? [])
				.filter((row) => !row.offered)
				.map((row) => row.country),
			prices: rows.map((row) => ({
				country: row.country,
				currency: row.price?.segment?.currency ?? row.price?.mms?.currency ?? 'USD',
				segment: row.price?.segment?.rate ?? null,
				mms: row.price?.mms?.rate ?? null,
				number_monthly: row.number?.monthly ?? null
			}))
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Asks Uplift to switch texting on for one more country. Asking twice is harmless: the country keeps its place.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: NO_STORE_HEADERS });
	}
	const parsed = requestSchema.safeParse(body);
	if (!parsed.success) {
		return json({ error: 'Choose a country.' }, { status: 422, headers: NO_STORE_HEADERS });
	}

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'communication_sms_request_destination',
		{
			p_organization_id: check.auth.organization.id,
			p_country_code: parsed.data.country_code,
			p_actor: check.auth.user.id
		}
	);
	if (error) {
		if (error.code === 'P0001' || error.code === '23514') {
			return json({ error: error.message }, { status: 409, headers: NO_STORE_HEADERS });
		}
		console.error('Could not ask for a texting country.', error);
		return json(
			{ error: "We couldn't send your request. Check your connection and try again." },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
	return json(
		{ country: data.country_code, status: data.status, is_home: data.is_home },
		{ headers: NO_STORE_HEADERS }
	);
};
