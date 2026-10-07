import { describe, expect, it } from 'vitest';
import { leadExclusion, missingInformation, previousContactLine } from './lead-review';

const method = { id: 'm1', kind: 'email' as const, value: 'info@a.co.uk', found_at: 'Site' };

describe('Who can be approved', () => {
	it('excludes a business that asked not to be contacted, before anything else', () => {
		expect(
			leadExclusion({
				do_not_contact: { at: '2026-10-07T10:00:00Z', reason: null },
				is_client: true,
				contact_methods: []
			})
		).toBe('do_not_contact');
	});

	it('excludes a client, then a business with no way to reach it', () => {
		expect(
			leadExclusion({ do_not_contact: null, is_client: true, contact_methods: [method] })
		).toBe('client');
		expect(leadExclusion({ do_not_contact: null, is_client: false, contact_methods: [] })).toBe(
			'no_contact_details'
		);
		expect(
			leadExclusion({ do_not_contact: null, is_client: false, contact_methods: [method] })
		).toBeNull();
	});

	it('lists what is missing without blocking approval', () => {
		expect(missingInformation({ contact_name: null, website: 'a.co.uk', fit_notes: null })).toEqual(
			['Why they may fit', 'Who to ask for']
		);
	});

	it('describes earlier contact in one line', () => {
		const none = { last_outbound_at: null, last_inbound_at: null };
		expect(previousContactLine({ outbound_count: 0, inbound_count: 0, ...none })).toBe(
			'No contact yet'
		);
		expect(previousContactLine({ outbound_count: 2, inbound_count: 1, ...none })).toBe(
			'Contacted 2 times · they got in touch once'
		);
		expect(previousContactLine({ outbound_count: 0, inbound_count: 1, ...none })).toBe(
			'They got in touch once'
		);
	});
});
