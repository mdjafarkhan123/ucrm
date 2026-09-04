import { afterEach, describe, expect, it, vi } from 'vitest';
import { getServerEnv } from '$lib/server/env';
import { isGeocodingConfigured, resolveGeocoder } from '$lib/server/geocoding/provider';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));

describe('geocoding provider', () => {
	afterEach(() => vi.restoreAllMocks());

	it('is unconfigured without a token', () => {
		vi.mocked(getServerEnv).mockReturnValue({ MAPBOX_ACCESS_TOKEN: undefined } as never);
		expect(isGeocodingConfigured()).toBe(false);
		expect(() => resolveGeocoder()).toThrow(/No geocoding provider is configured/);
	});

	it('is configured once a token is set, resolving a real geocoder', () => {
		vi.mocked(getServerEnv).mockReturnValue({ MAPBOX_ACCESS_TOKEN: 'sk.test' } as never);
		expect(isGeocodingConfigured()).toBe(true);
		expect(resolveGeocoder()).toHaveProperty('geocode');
	});
});
