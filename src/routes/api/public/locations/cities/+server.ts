import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { searchCities } from '$lib/server/locations/cities';

const querySchema = z.object({
	country: z.string().regex(/^[A-Z]{2}$/),
	q: z.string().max(80).default('')
});

export const GET: RequestHandler = ({ url }) => {
	const parsed = querySchema.safeParse({
		country: url.searchParams.get('country') ?? undefined,
		q: url.searchParams.get('q') ?? undefined
	});
	if (!parsed.success) return json({ error: 'Choose a country first.' }, { status: 400 });

	return json(
		{ cities: searchCities(parsed.data.country, parsed.data.q) },
		{ headers: { 'cache-control': 'public, max-age=86400' } }
	);
};
