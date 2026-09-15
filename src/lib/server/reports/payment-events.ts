import { z } from 'zod';

const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	eventDate: z.iso.date(),
	eventId: z.string().uuid()
});

export type PaymentEventsCursor = z.infer<typeof cursorSchema>;

export function encodePaymentEventsCursor(cursor: PaymentEventsCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readPaymentEventsCursor(
	raw: string | null | undefined
): PaymentEventsCursor | null {
	if (!raw) return null;
	try {
		const parsed = cursorSchema.safeParse(
			JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'))
		);
		return parsed.success ? parsed.data : null;
	} catch {
		return null;
	}
}
