import { z } from 'zod';

// outcome_at is set once per decision and the Opportunity id is unique, so the pair is a complete marker.
const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	outcomeAt: z.iso.datetime({ offset: true }),
	opportunityId: z.string().uuid()
});

export type SalesOutcomesCursor = z.infer<typeof cursorSchema>;

export function encodeSalesOutcomesCursor(cursor: SalesOutcomesCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readSalesOutcomesCursor(
	raw: string | null | undefined
): SalesOutcomesCursor | null {
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
