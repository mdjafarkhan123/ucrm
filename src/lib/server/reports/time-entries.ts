import { z } from 'zod';

// started_at is the ledger's date basis and the entry id is unique, so the pair is a complete marker.
const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	startedAt: z.iso.datetime({ offset: true }),
	entryId: z.string().uuid()
});

export type TimeEntriesCursor = z.infer<typeof cursorSchema>;

export function encodeTimeEntriesCursor(cursor: TimeEntriesCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readTimeEntriesCursor(raw: string | null | undefined): TimeEntriesCursor | null {
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
