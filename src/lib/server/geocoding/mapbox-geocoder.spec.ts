import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createMapboxGeocoder } from '$lib/server/geocoding/mapbox-geocoder';
import { GeocodingProviderError, type GeocodeAddress } from '$lib/server/geocoding/geocoder';

const AUSTIN: GeocodeAddress = {
	line1: '9 Oak Road',
	city: 'Austin',
	state_region: 'TX',
	postal_code: '78701'
};

describe('createMapboxGeocoder', () => {
	beforeEach(() => vi.stubGlobal('fetch', vi.fn()));
	afterEach(() => vi.unstubAllGlobals());

	it('requests permanent geocoding with the secret token', async () => {
		vi.mocked(fetch).mockResolvedValue(
			new Response(
				JSON.stringify({ features: [{ geometry: { coordinates: [-97.7431, 30.2672] } }] }),
				{
					status: 200
				}
			)
		);

		await createMapboxGeocoder('sk.test').geocode(AUSTIN);

		const url = new URL(vi.mocked(fetch).mock.calls[0][0] as string);
		expect(url.origin + url.pathname).toBe('https://api.mapbox.com/search/geocode/v6/forward');
		expect(url.searchParams.get('permanent')).toBe('true');
		expect(url.searchParams.get('access_token')).toBe('sk.test');
		expect(url.searchParams.get('q')).toBe('9 oak road, austin, tx, 78701');
	});

	it('resolves a found address to rounded coordinates', async () => {
		vi.mocked(fetch).mockResolvedValue(
			new Response(
				JSON.stringify({ features: [{ geometry: { coordinates: [-97.74314159, 30.26721111] } }] }),
				{ status: 200 }
			)
		);

		await expect(createMapboxGeocoder('sk.test').geocode(AUSTIN)).resolves.toEqual({
			status: 'found',
			latitude: 30.267211,
			longitude: -97.743142
		});
	});

	it('reports an address with no features as not_found', async () => {
		vi.mocked(fetch).mockResolvedValue(
			new Response(JSON.stringify({ features: [] }), { status: 200 })
		);

		await expect(createMapboxGeocoder('sk.test').geocode(AUSTIN)).resolves.toEqual({
			status: 'not_found'
		});
	});

	it('reports an address with nothing to geocode as not_found without calling the provider', async () => {
		const blank: GeocodeAddress = {
			line1: null,
			city: null,
			state_region: null,
			postal_code: null
		};

		await expect(createMapboxGeocoder('sk.test').geocode(blank)).resolves.toEqual({
			status: 'not_found'
		});
		expect(fetch).not.toHaveBeenCalled();
	});

	it('throws a retryable provider error on a rate limit', async () => {
		vi.mocked(fetch).mockResolvedValue(new Response(null, { status: 429 }));

		const error = await createMapboxGeocoder('sk.test')
			.geocode(AUSTIN)
			.catch((error: unknown) => error);
		expect(error).toBeInstanceOf(GeocodingProviderError);
		expect((error as GeocodingProviderError).retryable).toBe(true);
		expect((error as GeocodingProviderError).code).toBe('mapbox_http_429');
	});

	it('throws a retryable provider error on a 5xx', async () => {
		vi.mocked(fetch).mockResolvedValue(new Response(null, { status: 503 }));

		const error = await createMapboxGeocoder('sk.test')
			.geocode(AUSTIN)
			.catch((error: unknown) => error);
		expect(error).toBeInstanceOf(GeocodingProviderError);
		expect((error as GeocodingProviderError).retryable).toBe(true);
	});

	it('throws a non-retryable provider error on an auth rejection', async () => {
		vi.mocked(fetch).mockResolvedValue(new Response(null, { status: 401 }));

		const error = await createMapboxGeocoder('sk.test')
			.geocode(AUSTIN)
			.catch((error: unknown) => error);
		expect(error).toBeInstanceOf(GeocodingProviderError);
		expect((error as GeocodingProviderError).retryable).toBe(false);
		expect((error as GeocodingProviderError).code).toBe('mapbox_http_401');
	});

	it('throws a retryable provider error when the network call itself fails', async () => {
		vi.mocked(fetch).mockRejectedValue(new Error('fetch failed'));

		const error = await createMapboxGeocoder('sk.test')
			.geocode(AUSTIN)
			.catch((error: unknown) => error);
		expect(error).toBeInstanceOf(GeocodingProviderError);
		expect((error as GeocodingProviderError).retryable).toBe(true);
		expect((error as GeocodingProviderError).code).toBe('mapbox_network_unknown');
	});
});
