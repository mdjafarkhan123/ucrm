import { describe, expect, it } from 'vitest';
import { buildForwardGeocodeUrl, parseForwardGeocode } from '$lib/schedule/geocode-client';

describe('buildForwardGeocodeUrl', () => {
	it('encodes the address and asks for a single best hit', () => {
		const url = buildForwardGeocodeUrl('123 Main St, Springfield', 'pk.test');
		expect(url).toContain('https://api.mapbox.com/search/geocode/v6/forward?');
		expect(url).toContain('q=123+Main+St%2C+Springfield');
		expect(url).toContain('access_token=pk.test');
		expect(url).toContain('limit=1');
	});
});

describe('parseForwardGeocode', () => {
	it('reads longitude and latitude from the first feature', () => {
		const point = parseForwardGeocode({
			features: [{ geometry: { coordinates: [-71.0589, 42.3601] } }]
		});
		expect(point).toEqual({ lng: -71.0589, lat: 42.3601 });
	});

	it('returns null when nothing resolves', () => {
		expect(parseForwardGeocode({ features: [] })).toBeNull();
	});

	it('returns null for a malformed payload', () => {
		expect(parseForwardGeocode(null)).toBeNull();
		expect(parseForwardGeocode({})).toBeNull();
		expect(parseForwardGeocode({ features: [{ geometry: {} }] })).toBeNull();
		expect(
			parseForwardGeocode({ features: [{ geometry: { coordinates: ['a', 'b'] } }] })
		).toBeNull();
	});
});
