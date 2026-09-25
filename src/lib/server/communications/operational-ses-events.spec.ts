import { describe, expect, it } from 'vitest';
import type { SesEvent } from '$lib/server/marketing/ses-events';
import { operationalCallbackEventKind } from './operational-ses-events';

function event(overrides: Partial<SesEvent>): SesEvent {
	return { eventType: 'Delivery', mail: { messageId: 'msg-1' }, ...overrides };
}

describe('operationalCallbackEventKind', () => {
	it('maps Delivery to delivered', () => {
		expect(operationalCallbackEventKind(event({ eventType: 'Delivery' }))).toBe('delivered');
	});

	it('maps a permanent Bounce to hard_bounce', () => {
		expect(
			operationalCallbackEventKind(
				event({ eventType: 'Bounce', bounce: { bounceType: 'Permanent' } })
			)
		).toBe('hard_bounce');
	});

	it('maps any other Bounce to soft_bounce', () => {
		expect(
			operationalCallbackEventKind(
				event({ eventType: 'Bounce', bounce: { bounceType: 'Transient' } })
			)
		).toBe('soft_bounce');
		expect(operationalCallbackEventKind(event({ eventType: 'Bounce' }))).toBe('soft_bounce');
	});

	it('maps Complaint to complaint', () => {
		expect(operationalCallbackEventKind(event({ eventType: 'Complaint' }))).toBe('complaint');
	});

	it('maps DeliveryDelay to deferred', () => {
		expect(operationalCallbackEventKind(event({ eventType: 'DeliveryDelay' }))).toBe('deferred');
	});

	it('maps every other event type to other', () => {
		expect(operationalCallbackEventKind(event({ eventType: 'Send' }))).toBe('other');
		expect(operationalCallbackEventKind(event({ eventType: 'Open' }))).toBe('other');
	});
});
