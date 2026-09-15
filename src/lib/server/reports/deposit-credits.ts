import { z } from 'zod';

const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	createdAt: z.iso.datetime({ offset: true }),
	eventId: z.string().uuid()
});

export type DepositCreditsCursor = z.infer<typeof cursorSchema>;

export function encodeDepositCreditsCursor(cursor: DepositCreditsCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readDepositCreditsCursor(
	raw: string | null | undefined
): DepositCreditsCursor | null {
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
