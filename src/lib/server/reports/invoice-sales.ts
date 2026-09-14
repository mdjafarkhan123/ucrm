import { z } from 'zod';

const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	saleDate: z.iso.date(),
	invoiceId: z.string().uuid()
});

export type InvoiceSalesCursor = z.infer<typeof cursorSchema>;

export function encodeInvoiceSalesCursor(cursor: InvoiceSalesCursor) {
	return `${cursor.direction}:${cursor.saleDate}|${cursor.invoiceId}`;
}

export function readInvoiceSalesCursor(raw: string | null | undefined): InvoiceSalesCursor | null {
	if (!raw) return null;
	const directionSeparator = raw.indexOf(':');
	const idSeparator = raw.lastIndexOf('|');
	if (directionSeparator < 1 || idSeparator <= directionSeparator + 1) return null;

	const parsed = cursorSchema.safeParse({
		direction: raw.slice(0, directionSeparator),
		saleDate: raw.slice(directionSeparator + 1, idSeparator),
		invoiceId: raw.slice(idSeparator + 1)
	});
	return parsed.success ? parsed.data : null;
}
