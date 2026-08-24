import { describe, expect, it } from 'vitest';
import { bearerMatches, eventKey, intentIdFromTags, parseBrevoWebhookEvent } from './brevo-webhook';

describe('Brevo transactional webhook helpers', () => {
	it('accepts only the exact configured bearer token', () => {
		expect(bearerMatches('Bearer callback-token', 'callback-token')).toBe(true);
		expect(bearerMatches('Bearer wrong-token', 'callback-token')).toBe(false);
		expect(bearerMatches('Basic callback-token', 'callback-token')).toBe(false);
		expect(bearerMatches(null, 'callback-token')).toBe(false);
		expect(bearerMatches('Bearer callback-token', undefined)).toBe(false);
	});

	it('keeps the provider identity stable for duplicate detection', () => {
		const event = parseBrevoWebhookEvent({
			event: 'delivered',
			id: 101,
			['message-id']: 'provider-message-42',
			ts_event: 1_700_000_000
		});

		expect(event).not.toBeNull();
		expect(eventKey(event!)).toBe('delivered:101:provider-message-42:1700000000');
	});

	it('accepts only a usable provider event and extracts UCRM intent tags', () => {
		expect(parseBrevoWebhookEvent({ event: '' })).toBeNull();
		expect(parseBrevoWebhookEvent({ event: 'delivered', id: {} })).toBeNull();
		expect(intentIdFromTags(['provider:transactional', 'ucrm:email:intent-42'])).toBe('intent-42');
		expect(intentIdFromTags(['provider:transactional'])).toBeNull();
	});
});
