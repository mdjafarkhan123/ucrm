import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { getServerEnv } from '$lib/server/env';

// Jafar business management E2: the visitor's secret link to change or cancel a booking (Calendly's and HubSpot's
// pattern: one link per booking, the same in every email). The link is the booking's id with a signature, as the
// owner session cookie is signed, so any later email -- a staff move, an approval -- can carry it again. The
// database stores only the link's SHA-256 and finds the booking by it.

function signature(bookingId: string) {
	return createHmac('sha256', getServerEnv().SESSION_SECRET)
		.update(`uplift-booking-link:${bookingId}`)
		.digest('base64url');
}

/** The secret part of a booking's link. */
export function bookingToken(bookingId: string) {
	return `${bookingId}.${signature(bookingId)}`;
}

/** What the database keeps to find a booking by its link. */
export function bookingTokenHash(token: string) {
	return createHash('sha256').update(token).digest('hex');
}

/** The hash when the token is one this server signed, otherwise null (a guessed or altered link). */
export function verifiedTokenHash(token: string) {
	const [bookingId, given] = token.split('.');
	if (!bookingId || !given || !/^[0-9a-f-]{36}$/.test(bookingId)) return null;
	const expected = Buffer.from(signature(bookingId));
	const provided = Buffer.from(given);
	if (expected.length !== provided.length || !timingSafeEqual(expected, provided)) return null;
	return bookingTokenHash(token);
}

export function bookingManageUrl(origin: string, bookingId: string) {
	return `${origin}/book/manage/${bookingToken(bookingId)}`;
}
