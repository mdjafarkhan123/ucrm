import { describe, expect, it } from 'vitest';
import {
	MAX_ROUTE_STOPS,
	routeDirections,
	singleStopDirections,
	type NavPlace
} from '$lib/schedule/directions';

function coords(lat: number, lng: number): NavPlace {
	return { lat, lng, address: '9 Oak Road, Austin, TX' };
}

function addressOnly(address: string | null): NavPlace {
	return { lat: null, lng: null, address };
}

describe('singleStopDirections', () => {
	it('routes to stored coordinates when a stop has them', () => {
		const link = singleStopDirections(coords(30.2672, -97.7431), 'google');
		expect(link).toEqual({
			ok: true,
			url: 'https://www.google.com/maps/dir/?api=1&destination=30.2672%2C-97.7431'
		});
	});

	it('falls back to the address text when there are no coordinates', () => {
		const link = singleStopDirections(addressOnly('4 Elm Street, Austin, TX'), 'google');
		expect(link).toEqual({
			ok: true,
			url: 'https://www.google.com/maps/dir/?api=1&destination=4%20Elm%20Street%2C%20Austin%2C%20TX'
		});
	});

	it('builds an Apple link when that provider is asked for', () => {
		const link = singleStopDirections(addressOnly('4 Elm Street'), 'apple');
		expect(link).toEqual({ ok: true, url: 'https://maps.apple.com/?daddr=4%20Elm%20Street' });
	});

	it('reports no destination when a stop has neither coordinates nor an address', () => {
		expect(singleStopDirections(addressOnly(null), 'google')).toEqual({
			ok: false,
			reason: 'no-destination'
		});
		expect(singleStopDirections(addressOnly('   '), 'google')).toEqual({
			ok: false,
			reason: 'no-destination'
		});
	});
});

describe('routeDirections', () => {
	it('puts the last stop as the destination and the rest as waypoints (Google)', () => {
		const link = routeDirections([addressOnly('A'), addressOnly('B'), addressOnly('C')], 'google');
		expect(link).toEqual({
			ok: true,
			url: 'https://www.google.com/maps/dir/?api=1&destination=C&waypoints=A%7CB'
		});
	});

	it('chains stops with +to: for Apple', () => {
		const link = routeDirections([addressOnly('A'), addressOnly('B'), addressOnly('C')], 'apple');
		expect(link).toEqual({ ok: true, url: 'https://maps.apple.com/?daddr=A+to:B+to:C' });
	});

	it('leaves out a stop with no usable location', () => {
		const link = routeDirections([addressOnly('A'), addressOnly(null), addressOnly('C')], 'google');
		expect(link).toEqual({
			ok: true,
			url: 'https://www.google.com/maps/dir/?api=1&destination=C&waypoints=A'
		});
	});

	it('degrades to a single-destination link when only one stop is usable', () => {
		const link = routeDirections([addressOnly(null), addressOnly('C')], 'google');
		expect(link).toEqual({
			ok: true,
			url: 'https://www.google.com/maps/dir/?api=1&destination=C'
		});
	});

	it('reports no destination when nothing on the route is usable', () => {
		expect(routeDirections([addressOnly(null), addressOnly('  ')], 'google')).toEqual({
			ok: false,
			reason: 'no-destination'
		});
		expect(routeDirections([], 'apple')).toEqual({ ok: false, reason: 'no-destination' });
	});

	it('explains the limit when a route has more stops than the provider link accepts', () => {
		const tooMany = Array.from({ length: MAX_ROUTE_STOPS.google + 1 }, (_, i) =>
			addressOnly(`stop-${i}`)
		);
		expect(routeDirections(tooMany, 'google')).toEqual({
			ok: false,
			reason: 'too-many-stops',
			limit: MAX_ROUTE_STOPS.google
		});
	});

	it('prefers coordinates over the address when both are present', () => {
		const link = routeDirections([coords(1, 2), addressOnly('B')], 'google');
		expect(link).toEqual({
			ok: true,
			url: 'https://www.google.com/maps/dir/?api=1&destination=B&waypoints=1%2C2'
		});
	});
});
