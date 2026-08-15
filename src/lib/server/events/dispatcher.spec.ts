import { beforeEach, describe, expect, it, vi } from 'vitest';
import { enqueueEmailDelivery, dispatchOutboxDelivery } from './dispatcher';
import { sendTransactionalEmail } from '$lib/server/email/brevo';
import { recordOperationOutcome } from './outbox';

vi.mock('$lib/server/email/brevo', () => ({ sendTransactionalEmail: vi.fn() }));
vi.mock('./outbox', () => ({ recordOperationOutcome: vi.fn() }));

const mockedSend = vi.mocked(sendTransactionalEmail);
const mockedRecordOutcome = vi.mocked(recordOperationOutcome);

type DeliveryRow = {
	id: string;
	idempotency_key: string;
	recipient_email: string;
	attempt_count: number;
	target_kind: string;
	target_id: string | null;
	correlation_id: string | null;
	payload: { subject: string; html_content: string; text_content: string };
	status: string;
	sent_at?: string | null;
	last_error?: string | null;
};

function deliveryRow(overrides: Partial<DeliveryRow> = {}): DeliveryRow {
	return {
		id: 'delivery-1',
		idempotency_key: 'application:app-42:receipt',
		recipient_email: 'jordan@ridgeway.example',
		attempt_count: 0,
		target_kind: 'onboarding_application',
		target_id: 'app-42',
		correlation_id: null,
		payload: {
			subject: 'Thanks for applying, Growth at $49/mo',
			html_content: '<p>Version one wording.</p>',
			text_content: 'Version one wording.'
		},
		status: 'queued',
		...overrides
	};
}

function clientWith(initialRows: DeliveryRow[] = []) {
	const rows = new Map(initialRows.map((row) => [row.id, { ...row }]));
	const inserted: Record<string, unknown>[] = [];
	let nextId = rows.size + 1;

	const findBy = (column: string, value: unknown) =>
		[...rows.values()].find(
			(row) => (row as unknown as Record<string, unknown>)[column] === value
		) ?? null;

	const client = {
		from(table: string) {
			if (table !== 'platform_outbox_deliveries') throw new Error(`unexpected table ${table}`);
			return {
				select: () => ({
					eq: (column: string, value: unknown) => ({
						maybeSingle: async () => ({ data: findBy(column, value), error: null })
					})
				}),
				insert: (values: Record<string, unknown>) => {
					inserted.push(values);
					return {
						select: () => ({
							single: async () => {
								const id = `delivery-${nextId++}`;
								rows.set(id, { ...deliveryRow(), ...values, id } as DeliveryRow);
								return { data: { id }, error: null };
							}
						})
					};
				},
				update: (values: Record<string, unknown>) => ({
					eq: async (_column: string, value: string) => {
						const row = rows.get(value);
						if (row) Object.assign(row, values);
						return { error: null };
					}
				})
			};
		},
		__rows: rows,
		__inserted: inserted
	};

	return client;
}

const enqueueParams = {
	templateKey: 'application_receipt',
	target: { targetKind: 'onboarding_application' as const, targetId: 'app-42' },
	idempotencyKey: 'application:app-42:receipt',
	recipientEmail: 'jordan@ridgeway.example',
	subject: 'Thanks for applying, Growth at $49/mo',
	htmlContent: '<p>Version one wording.</p>',
	textContent: 'Version one wording.'
};

describe('durable email outbox', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedSend.mockResolvedValue(undefined as never);
	});

	it('stores the rendered email before attempting to send it', async () => {
		const client = clientWith();

		await enqueueEmailDelivery(client as never, enqueueParams);

		expect(client.__inserted[0]).toMatchObject({
			template_key: 'application_receipt',
			idempotency_key: 'application:app-42:receipt',
			recipient_email: 'jordan@ridgeway.example',
			payload: {
				subject: 'Thanks for applying, Growth at $49/mo',
				html_content: '<p>Version one wording.</p>'
			}
		});
		expect(mockedSend).toHaveBeenCalledTimes(1);
	});

	it('reuses the existing row instead of sending the same email twice', async () => {
		const client = clientWith([deliveryRow({ id: 'delivery-9', status: 'sent' })]);

		const deliveryId = await enqueueEmailDelivery(client as never, enqueueParams);

		expect(deliveryId).toBe('delivery-9');
		expect(client.__inserted).toHaveLength(0);
		expect(mockedSend).not.toHaveBeenCalled();
	});

	it('marks the row sent and records a successful operation when the provider accepts it', async () => {
		const client = clientWith([deliveryRow()]);

		await dispatchOutboxDelivery(client as never, 'delivery-1');

		const row = client.__rows.get('delivery-1');
		expect(row?.status).toBe('sent');
		expect(row?.sent_at).toBeTruthy();
		expect(row?.last_error).toBeNull();
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				operationType: 'outbox_email_delivery',
				idempotencyKey: 'delivery-1',
				success: true
			})
		);
	});

	it('keeps the email during a provider outage and files a retryable operation', async () => {
		const client = clientWith([deliveryRow()]);
		mockedSend.mockRejectedValue(new Error('Brevo returned 503'));

		await expect(dispatchOutboxDelivery(client as never, 'delivery-1')).rejects.toThrow(
			'Brevo returned 503'
		);

		const row = client.__rows.get('delivery-1');
		expect(row?.status).toBe('failed');
		expect(row?.attempt_count).toBe(1);
		expect(row?.last_error).toBe('Brevo returned 503');
		expect(row?.payload.html_content).toBe('<p>Version one wording.</p>');
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				operationType: 'outbox_email_delivery',
				idempotencyKey: 'delivery-1',
				success: false,
				target: { targetKind: 'onboarding_application', targetId: 'app-42' }
			})
		);
	});

	it('attributes a failed retry to the owner who triggered it', async () => {
		const client = clientWith([deliveryRow()]);
		mockedSend.mockRejectedValue(new Error('Brevo returned 503'));

		await expect(
			dispatchOutboxDelivery(client as never, 'delivery-1', 'owner@example.com')
		).rejects.toThrow();

		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ actorEmail: 'owner@example.com', success: false })
		);
	});

	it('leaves the original automated send unattributed to any human actor', async () => {
		const client = clientWith([deliveryRow()]);
		mockedSend.mockRejectedValue(new Error('Brevo returned 503'));

		await expect(dispatchOutboxDelivery(client as never, 'delivery-1')).rejects.toThrow();

		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ actorEmail: undefined })
		);
	});

	it('counts every failed attempt so a repeatedly failing send is visible in Operations', async () => {
		const client = clientWith([deliveryRow({ status: 'failed', attempt_count: 2 })]);
		mockedSend.mockRejectedValue(new Error('Brevo returned 503'));

		await expect(dispatchOutboxDelivery(client as never, 'delivery-1')).rejects.toThrow();

		expect(client.__rows.get('delivery-1')?.attempt_count).toBe(3);
	});

	it('re-sends the exact wording stored on the row, not a freshly rendered template', async () => {
		const client = clientWith([deliveryRow({ status: 'failed', attempt_count: 1 })]);

		await dispatchOutboxDelivery(client as never, 'delivery-1');

		expect(mockedSend).toHaveBeenCalledWith({
			to: { email: 'jordan@ridgeway.example' },
			subject: 'Thanks for applying, Growth at $49/mo',
			htmlContent: '<p>Version one wording.</p>',
			textContent: 'Version one wording.'
		});
	});

	it('does nothing when the row was already sent, so a retry cannot double-send', async () => {
		const client = clientWith([deliveryRow({ status: 'sent' })]);

		await dispatchOutboxDelivery(client as never, 'delivery-1');

		expect(mockedSend).not.toHaveBeenCalled();
		expect(mockedRecordOutcome).not.toHaveBeenCalled();
	});

	it('trims a very long provider error before storing it', async () => {
		const client = clientWith([deliveryRow()]);
		mockedSend.mockRejectedValue(new Error('x'.repeat(900)));

		await expect(dispatchOutboxDelivery(client as never, 'delivery-1')).rejects.toThrow();

		expect(client.__rows.get('delivery-1')?.last_error).toHaveLength(500);
	});

	it('refuses to dispatch a delivery that does not exist', async () => {
		const client = clientWith();

		await expect(dispatchOutboxDelivery(client as never, 'missing')).rejects.toThrow(
			'does not exist'
		);
		expect(mockedSend).not.toHaveBeenCalled();
	});
});
