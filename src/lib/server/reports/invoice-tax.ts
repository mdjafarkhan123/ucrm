import { z } from 'zod';

const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	taxDate: z.iso.date(),
	invoiceId: z.string().uuid()
});

export type InvoiceTaxCursor = z.infer<typeof cursorSchema>;

export function encodeInvoiceTaxCursor(cursor: InvoiceTaxCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readInvoiceTaxCursor(raw: string | null | undefined): InvoiceTaxCursor | null {
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
