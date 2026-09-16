import { z } from 'zod';

const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	workDate: z.iso.date(),
	unitId: z.string().uuid()
});

export type UninvoicedWorkCursor = z.infer<typeof cursorSchema>;

export function encodeUninvoicedWorkCursor(cursor: UninvoicedWorkCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readUninvoicedWorkCursor(
	raw: string | null | undefined
): UninvoicedWorkCursor | null {
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
