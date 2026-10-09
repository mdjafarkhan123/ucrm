import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/env', () => ({ getServerEnv: () => ({ SESSION_SECRET: 'test-secret' }) }));

import { bookingToken, bookingTokenHash, verifiedTokenHash } from './booking-links';

const bookingId = '0f8b8c1e-3c1a-4c6e-9a51-2a8d6f1e7b10';

describe("a visitor's booking link", () => {
	it('is the same link every time for one booking', () => {
		expect(bookingToken(bookingId)).toBe(bookingToken(bookingId));
		expect(bookingToken(bookingId).startsWith(`${bookingId}.`)).toBe(true);
	});

	it('finds the booking by the hash the database keeps', () => {
		const token = bookingToken(bookingId);
		expect(verifiedTokenHash(token)).toBe(bookingTokenHash(token));
	});

	it('refuses an altered or guessed link', () => {
		const token = bookingToken(bookingId);
		const otherBooking = bookingId.replace(/0$/, '1');
		expect(verifiedTokenHash(`${otherBooking}.${token.split('.')[1]}`)).toBeNull();
		expect(verifiedTokenHash(`${bookingId}.${'A'.repeat(43)}`)).toBeNull();
		expect(verifiedTokenHash(bookingId)).toBeNull();
		expect(verifiedTokenHash('not-a-booking.abc')).toBeNull();
	});
});
