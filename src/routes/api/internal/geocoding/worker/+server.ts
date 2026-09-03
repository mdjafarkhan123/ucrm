import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { drainGeocodingQueue } from '$lib/server/geocoding/worker';
import { isGeocodingConfigured, resolveGeocoder } from '$lib/server/geocoding/provider';

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().GEOCODING_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

// One geocoding wake: drain the pending-property queue through the configured provider. Secret-gated like the
// other internal workers. No single-flight lease — the per-row `for update skip locked` claim is the
// exactly-once boundary, so overlapping wakes are safe.
//
// Until Schedule Part 7b wires managed Mapbox, no provider is configured and this returns 503 rather than
// running a stand-in against real properties (which would fabricate coordinates). The worker module itself is
// exercised in tests with the mock geocoder injected directly.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	if (!isGeocodingConfigured())
		return json(
			{ error: 'No geocoding provider is configured (wired in Schedule Part 7b).' },
			{ status: 503, headers: { 'cache-control': 'no-store' } }
		);

	const result = await drainGeocodingQueue({ geocoder: resolveGeocoder() });
	return json(result, { headers: { 'cache-control': 'no-store' } });
};
