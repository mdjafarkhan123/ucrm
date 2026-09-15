import { z } from 'zod';

const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	sortName: z.string().max(300),
	clientId: z.string().uuid()
});

export type ClientAgingCursor = z.infer<typeof cursorSchema>;

export function encodeClientAgingCursor(cursor: ClientAgingCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readClientAgingCursor(raw: string | null | undefined): ClientAgingCursor | null {
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
