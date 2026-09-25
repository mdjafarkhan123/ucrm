import { describe, expect, it } from 'vitest';
import {
	parseSesEvent,
	sesEventConfigurationSetName,
	sesEventKey,
	sesEventOccurredAt,
	sesEventTag
} from './ses-events';

const deliveryEvent = {
	eventType: 'Delivery',
	mail: { messageId: 'msg-1', timestamp: '2026-09-22T10:00:00.000Z' },
	delivery: { timestamp: '2026-09-22T10:00:05.000Z' }
};

describe('parseSesEvent', () => {
	it('accepts a well-formed SES event and keeps unknown fields', () => {
		const event = parseSesEvent({ ...deliveryEvent, extra: 'kept' });
		expect(event).not.toBeNull();
		expect(event?.eventType).toBe('Delivery');
		expect((event as { extra?: string })?.extra).toBe('kept');
	});

	it('rejects a payload missing mail.messageId', () => {
		expect(parseSesEvent({ eventType: 'Delivery', mail: {} })).toBeNull();
	});

	it('rejects a payload that is not an object', () => {
		expect(parseSesEvent('not an event')).toBeNull();
		expect(parseSesEvent(null)).toBeNull();
	});
});

describe('sesEventKey', () => {
	it('combines the message id and event type into one idempotency key', () => {
		expect(sesEventKey(deliveryEvent)).toBe('ses:msg-1:Delivery');
	});
});

describe('sesEventOccurredAt', () => {
	it('prefers the type-specific timestamp over mail.timestamp', () => {
		expect(sesEventOccurredAt(deliveryEvent)).toBe('2026-09-22T10:00:05.000Z');
	});

	it('falls back to mail.timestamp when the type-specific object is absent', () => {
		expect(
			sesEventOccurredAt({
				eventType: 'Send',
				mail: { messageId: 'msg-2', timestamp: '2026-09-22T09:00:00.000Z' }
			})
		).toBe('2026-09-22T09:00:00.000Z');
	});

	it('returns null when neither timestamp is present', () => {
		expect(sesEventOccurredAt({ eventType: 'Send', mail: { messageId: 'msg-3' } })).toBeNull();
	});
});

describe('sesEventConfigurationSetName', () => {
	it('reads the ses:configuration-set tag SES attaches to every event', () => {
		const event = parseSesEvent({
			eventType: 'Delivery',
			mail: {
				messageId: 'msg-4',
				tags: { 'ses:configuration-set': ['ucrm-operational-org-1'] }
			}
		});
		expect(sesEventConfigurationSetName(event!)).toBe('ucrm-operational-org-1');
	});

	it('returns null when the event carries no configuration-set tag', () => {
		expect(sesEventConfigurationSetName(deliveryEvent)).toBeNull();
	});
});

describe('sesEventTag', () => {
	it('reads the first value of a named EmailTag', () => {
		const event = parseSesEvent({
			eventType: 'Delivery',
			mail: { messageId: 'msg-5', tags: { 'ucrm-intent': ['intent-1'] } }
		});
		expect(sesEventTag(event!, 'ucrm-intent')).toBe('intent-1');
	});

	it('returns null when the named tag was never set', () => {
		expect(sesEventTag(deliveryEvent, 'ucrm-intent')).toBeNull();
	});
});
