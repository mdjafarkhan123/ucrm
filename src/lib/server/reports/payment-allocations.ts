import { z } from 'zod';

const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	createdAt: z.iso.datetime({ offset: true }),
	allocationId: z.string().uuid()
});

export type PaymentAllocationsCursor = z.infer<typeof cursorSchema>;

export function encodePaymentAllocationsCursor(cursor: PaymentAllocationsCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readPaymentAllocationsCursor(
	raw: string | null | undefined
): PaymentAllocationsCursor | null {
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
