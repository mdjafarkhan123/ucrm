import { describe, expect, it } from 'vitest';
import {
	destinationStatus,
	margin,
	shortSid,
	textPrice,
	type BusinessDestination
} from './texting-setup';
import { destinationActorName, finishedBy } from '$lib/server/communications/sms-destination-ops';

const country = (overrides: Partial<BusinessDestination>): BusinessDestination => ({
	id: 'd1',
	country: 'GB',
	status: 'setting_up',
	is_home: false,
	requested_at: '2026-10-22T10:00:00Z',
	ready_at: null,
	off_at: null,
	off_reason: null,
	price: { segment: null, mms: null },
	history: [],
	...overrides
});

const priced = { segment: { rate: 0.09, cost: 0.0524, currency: 'USD' }, mms: null };

describe('text prices', () => {
	it('keeps the digits a price was set with, at least two', () => {
		expect(textPrice(0.09)).toBe('$0.09');
		expect(textPrice(0.1)).toBe('$0.10');
		expect(textPrice(0.0079)).toBe('$0.0079');
	});

	it('works out what Uplift keeps after Twilio’s cost', () => {
		expect(margin(0.09, 0.0524)).toBe('42%');
	});

	it('cuts a Twilio account id down for reading', () => {
		expect(shortSid(`AC${'0'.repeat(28)}4f2e`)).toBe('AC…4f2e');
	});
});

describe('a business’s country status', () => {
	it('is Ready only with the Twilio permission and a price', () => {
		expect(destinationStatus(country({ status: 'ready', price: priced })).label).toBe('Ready');
		expect(destinationStatus(country({ status: 'ready' })).label).toBe('Setting up');
		expect(destinationStatus(country({ price: priced })).label).toBe('Setting up');
		expect(destinationStatus(country({ status: 'off', price: priced })).label).toBe('Off');
	});
});

describe('who did it', () => {
	const session = { email: 'sam@uplift.example', sessionId: 's', access: null, memberId: null };

	it('names a teammate, else Jafar for the owner', () => {
		expect(destinationActorName({ ...session, role: 'platform_operations', name: 'Sam' })).toBe(
			'Sam'
		);
		expect(destinationActorName({ ...session, role: null, name: null })).toBe('Jafar');
		expect(destinationActorName({ ...session, role: 'support', name: ' ' })).toBe(
			'sam@uplift.example'
		);
	});

	it('finds the newest switch-on or close, not the request', () => {
		expect(
			finishedBy([
				{ kind: 'switched_on', at: '2026-10-23T09:00:00Z', who: 'Sam' },
				{ kind: 'requested', at: '2026-10-22T09:00:00Z', who: null }
			])
		).toEqual({ kind: 'switched_on', at: '2026-10-23T09:00:00Z', who: 'Sam' });
		expect(finishedBy([{ kind: 'requested', at: '2026-10-22T09:00:00Z', who: null }])).toBeNull();
	});
});
