import { describe, expect, it } from 'vitest';
import { invoiceLifecycleSchema } from './invoices.schema';

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
