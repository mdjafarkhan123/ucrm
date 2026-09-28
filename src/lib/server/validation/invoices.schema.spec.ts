import { describe, expect, it } from 'vitest';
import { invoiceLifecycleSchema, recordInvoicePaymentSchema } from './invoices.schema';

const retry = {
	idempotency_key: '123e4567-e89b-42d3-a456-426614174000',
	request_hash: 'v1:invoice-lifecycle'
};

describe('invoiceLifecycleSchema', () => {
	it('rejects the retired status-only Mark Received action', () => {
		const result = invoiceLifecycleSchema.safeParse({
			action: 'mark_received',
			reason: 'Paid outside the app',
			...retry
		});

		expect(result.success).toBe(false);
	});

	it('keeps reopen available to correct a historical closure', () => {
		const result = invoiceLifecycleSchema.safeParse({
			action: 'reopen',
			reason: 'Replace the old closure with a recorded payment',
			...retry
		});

		expect(result.success).toBe(true);
	});
});

describe('recordInvoicePaymentSchema allocations', () => {
	const payment = {
		client_id: '123e4567-e89b-42d3-a456-426614174001',
		amount_minor: 90000,
		method: 'bank_transfer',
		payment_date: '2026-09-28',
		...retry
	};
	const invoiceA = '123e4567-e89b-42d3-a456-426614174002';
	const invoiceB = '123e4567-e89b-42d3-a456-426614174003';

	it('keeps the single-bill shape when no list is sent', () => {
		const result = recordInvoicePaymentSchema.safeParse(payment);
		expect(result.success && result.data.allocations).toBeUndefined();
	});

	it('accepts one payment spread across bills, leaving the rest as credit', () => {
		const result = recordInvoicePaymentSchema.safeParse({
			...payment,
			allocations: [
				{ invoice_id: invoiceA, amount_minor: 50000 },
				{ invoice_id: invoiceB, amount_minor: 30000 }
			]
		});
		expect(result.success).toBe(true);
	});

	it('refuses bills that add up to more than was received', () => {
		const result = recordInvoicePaymentSchema.safeParse({
			...payment,
			allocations: [
				{ invoice_id: invoiceA, amount_minor: 60000 },
				{ invoice_id: invoiceB, amount_minor: 40000 }
			]
		});
		expect(result.success).toBe(false);
	});

	it('refuses the same bill twice', () => {
		const result = recordInvoicePaymentSchema.safeParse({
			...payment,
			allocations: [
				{ invoice_id: invoiceA, amount_minor: 100 },
				{ invoice_id: invoiceA, amount_minor: 100 }
			]
		});
		expect(result.success).toBe(false);
	});
});
