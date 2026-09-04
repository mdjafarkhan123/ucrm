import { describe, expect, it } from 'vitest';
import {
	stopAddressLabel,
	stopClientLabel,
	stopGeocodeState,
	stopNavPlace,
	stopPropertyId,
	stopTimeLabel,
	stopWorkLabel
} from '$lib/schedule/stops';
import type { AssessmentItem, VisitItem } from '$lib/schedule/items';

const TODAY = '2026-09-04';

function visit(overrides: Partial<VisitItem> & { id: string }): VisitItem {
	return {
		kind: 'visit',
		job_id: 'job-1',
		visit_date: TODAY,
		start_time: '09:00:00',
		end_time: '10:30:00',
		all_day: false,
		title: null,
		completed_at: null,
		revision: 1,
		position: 0,
		assignee_ids: [],
		job_number: 7,
		job_title: 'Gutter clean',
		client_id: 'client-1',
		client_name: 'Dana Reed',
		client_company_name: null,
		property_id: 'property-1',
		property_label: null,
		property_address_line1: '4 Elm Street',
		property_city: 'Austin',
		property_state_region: 'TX',
		property_postal_code: '78701',
		property_latitude: null,
		property_longitude: null,
		property_geocode_status: 'pending',
		...overrides
	};
}

function assessment(overrides: Partial<AssessmentItem> & { id: string }): AssessmentItem {
	return {
		kind: 'assessment',
		request_id: 'request-1',
		visit_date: TODAY,
		start_time: null,
		end_time: null,
		all_day: true,
		completed_at: null,
		assignee_ids: [],
		request_title: 'Roof look',
		request_status: 'assessment_scheduled',
		client_id: 'client-2',
		client_name: null,
		client_company_name: 'Cole Roofing',
		property_id: 'property-2',
		property_label: null,
		property_address_line1: '9 Oak Road',
		property_city: 'Austin',
		property_state_region: 'TX',
		property_postal_code: '78702',
		property_latitude: null,
		property_longitude: null,
		property_geocode_status: 'pending',
		...overrides
	};
}

describe('stopGeocodeState', () => {
	it('is located when coordinates are stored, whatever the status column says', () => {
		const stop = visit({ id: 'a', property_latitude: 30.26, property_longitude: -97.74 });
		expect(stopGeocodeState(stop)).toBe('located');
	});

	it('is failed when the geocoder ran and the address does not resolve', () => {
		const stop = visit({ id: 'a', property_geocode_status: 'failed' });
		expect(stopGeocodeState(stop)).toBe('failed');
	});

	it('is pending when the address is queued but not geocoded yet', () => {
		const stop = visit({ id: 'a', property_geocode_status: 'pending' });
		expect(stopGeocodeState(stop)).toBe('pending');
	});

	it('is no-address when the property has no address at all', () => {
		const stop = visit({
			id: 'a',
			property_label: null,
			property_address_line1: null,
			property_city: null,
			property_state_region: null,
			property_postal_code: null
		});
		expect(stopGeocodeState(stop)).toBe('no-address');
	});

	it('a failed row with stored coordinates still reads located', () => {
		const stop = visit({
			id: 'a',
			property_geocode_status: 'failed',
			property_latitude: 30.26,
			property_longitude: -97.74
		});
		expect(stopGeocodeState(stop)).toBe('located');
	});
});

describe('stopNavPlace', () => {
	it('carries stored coordinates and the one-line address', () => {
		const stop = visit({ id: 'a', property_latitude: 30.26, property_longitude: -97.74 });
		expect(stopNavPlace(stop)).toEqual({
			lat: 30.26,
			lng: -97.74,
			address: '4 Elm Street Austin, TX 78701'
		});
	});

	it('leaves coordinates null when the property is not geocoded, keeping the address for the maps app', () => {
		const place = stopNavPlace(visit({ id: 'a' }));
		expect(place.lat).toBeNull();
		expect(place.lng).toBeNull();
		expect(place.address).toBe('4 Elm Street Austin, TX 78701');
	});
});

describe('stop labels', () => {
	it('names a visit stop by its client and its work', () => {
		const stop = visit({ id: 'a', title: 'Back fence' });
		expect(stopClientLabel(stop)).toBe('Dana Reed');
		expect(stopWorkLabel(stop)).toBe('Back fence');
	});

	it('falls back to the job title, then the job number, for a visit with no visit title', () => {
		expect(stopWorkLabel(visit({ id: 'a' }))).toBe('Gutter clean');
		expect(stopWorkLabel(visit({ id: 'a', job_title: null }))).toBe('Job #7');
	});

	it('names an assessment stop by its company and its request title', () => {
		const stop = assessment({ id: 'a' });
		expect(stopClientLabel(stop)).toBe('Cole Roofing');
		expect(stopWorkLabel(stop)).toBe('Roof look');
	});

	it('says the client is hidden when the reader may not see it', () => {
		const stop = visit({ id: 'a', client_name: null, client_company_name: null });
		expect(stopClientLabel(stop)).toBe('Client hidden');
	});

	it('reads a fixed-time stop as a range and an anytime stop as Anytime', () => {
		expect(stopTimeLabel(visit({ id: 'a' }))).toBe('9am – 10:30am');
		expect(stopTimeLabel(visit({ id: 'a', start_time: '09:00:00', end_time: null }))).toBe('9am');
		expect(stopTimeLabel(assessment({ id: 'a' }))).toBe('Anytime');
	});

	it('reports the property id so two stops at one address can stack', () => {
		expect(stopPropertyId(visit({ id: 'a' }))).toBe('property-1');
		expect(stopPropertyId(assessment({ id: 'a' }))).toBe('property-2');
	});
});

describe('stopAddressLabel', () => {
	it('joins label, street, city/region and postal into one line', () => {
		const stop = visit({ id: 'a', property_label: 'Main house' });
		expect(stopAddressLabel(stop)).toBe('Main house · 4 Elm Street Austin, TX 78701');
	});

	it('is null when there is no address to show', () => {
		const stop = visit({
			id: 'a',
			property_label: null,
			property_address_line1: null,
			property_city: null,
			property_state_region: null,
			property_postal_code: null
		});
		expect(stopAddressLabel(stop)).toBeNull();
	});
});
