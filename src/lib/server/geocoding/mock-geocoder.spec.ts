import { describe, expect, it } from 'vitest';
import { createMockGeocoder } from '$lib/server/geocoding/mock-geocoder';
import { geocodeQuery, type GeocodeAddress } from '$lib/server/geocoding/geocoder';

const AUSTIN: GeocodeAddress = {
	line1: '9 Oak Road',
	city: 'Austin',
	state_region: 'TX',
	postal_code: '78701'
};

describe('geocodeQuery', () => {
	it('joins the present parts, collapses whitespace and lowercases', () => {
		expect(geocodeQuery(AUSTIN)).toBe('9 oak road, austin, tx, 78701');
	});

	it('drops blank and null parts', () => {
		expect(
			geocodeQuery({ line1: '  9 Oak Road ', city: null, state_region: '  ', postal_code: '78701' })
		).toBe('9 oak road, 78701');
	});

	it('is empty when nothing can be geocoded', () => {
		expect(geocodeQuery({ line1: null, city: '', state_region: '  ', postal_code: null })).toBe('');
	});
});

describe('createMockGeocoder', () => {
	it('resolves an address to plausible, in-range coordinates', async () => {
		const result = await createMockGeocoder().geocode(AUSTIN);
		expect(result.status).toBe('found');
		if (result.status !== 'found') return;
		expect(result.latitude).toBeGreaterThanOrEqual(24);
		expect(result.latitude).toBeLessThanOrEqual(49);
		expect(result.longitude).toBeGreaterThanOrEqual(-125);
		expect(result.longitude).toBeLessThanOrEqual(-66);
	});

	it('rounds coordinates to numeric(9,6) precision', async () => {
		const result = await createMockGeocoder().geocode(AUSTIN);
		if (result.status !== 'found') throw new Error('expected found');
		expect(result.latitude).toBe(Math.round(result.latitude * 1_000_000) / 1_000_000);
		expect(result.longitude).toBe(Math.round(result.longitude * 1_000_000) / 1_000_000);
	});

	it('is deterministic: the same address always resolves the same way', async () => {
		const a = await createMockGeocoder().geocode(AUSTIN);
		const b = await createMockGeocoder().geocode(AUSTIN);
		expect(a).toEqual(b);
	});

	it('ignores how the address was typed, keying on the normalized query', async () => {
		const spaced: GeocodeAddress = {
			line1: '  9 OAK ROAD ',
			city: 'AUSTIN',
			state_region: 'tx',
			postal_code: ' 78701 '
		};
		expect(await createMockGeocoder().geocode(spaced)).toEqual(
			await createMockGeocoder().geocode(AUSTIN)
		);
	});

	it('gives different addresses different coordinates', async () => {
		const other = await createMockGeocoder().geocode({
			line1: '400 Pine Street',
			city: 'Denver',
			state_region: 'CO',
			postal_code: '80202'
		});
		const austin = await createMockGeocoder().geocode(AUSTIN);
		expect(other).not.toEqual(austin);
	});

	it('reports an address with nothing to geocode as not_found', async () => {
		const result = await createMockGeocoder().geocode({
			line1: null,
			city: null,
			state_region: null,
			postal_code: null
		});
		expect(result).toEqual({ status: 'not_found' });
	});

	it('lets a fixture pin an address to exact coordinates', async () => {
		const geocoder = createMockGeocoder({
			[geocodeQuery(AUSTIN)]: { status: 'found', latitude: 30.2672, longitude: -97.7431 }
		});
		expect(await geocoder.geocode(AUSTIN)).toEqual({
			status: 'found',
			latitude: 30.2672,
			longitude: -97.7431
		});
	});

	it('lets a fixture force a real-looking address to not_found', async () => {
		const nowhere: GeocodeAddress = {
			line1: '1 Nowhere Lane',
			city: 'Nowhere',
			state_region: 'ZZ',
			postal_code: '00000'
		};
		const geocoder = createMockGeocoder({ [geocodeQuery(nowhere)]: { status: 'not_found' } });
		expect(await geocoder.geocode(nowhere)).toEqual({ status: 'not_found' });
	});
});
