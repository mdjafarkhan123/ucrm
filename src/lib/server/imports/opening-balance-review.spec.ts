import { describe, expect, it } from 'vitest';
import {
	runOpeningBalanceReview,
	type OpeningBalanceColumnMapping,
	type OpeningBalanceReviewInputs
} from './opening-balance-review';

const MAPPING: OpeningBalanceColumnMapping = {
	Email: { field: 'client_email' },
	Type: { field: 'balance_type' },
	Amount: { field: 'amount' },
	'As Of': { field: 'as_of_date' },
	Note: { field: 'source_note' }
};

function review(
	rows: Record<string, string>[],
	overrides: Partial<OpeningBalanceReviewInputs> = {}
): ReturnType<typeof runOpeningBalanceReview> {
	return runOpeningBalanceReview({
		rows,
		mapping: MAPPING,
		emailToClientId: new Map(),
		activeFacts: [],
		currencyCode: 'USD',
		...overrides
	});
}

describe('runOpeningBalanceReview — create', () => {
	it('creates a fresh receivable fact for a matched client', () => {
		const { rows, summary } = review(
			[{ Email: 'ada@example.com', Type: 'receivable', Amount: '1250.00', 'As Of': '2026-01-01' }],
			{ emailToClientId: new Map([['ada@example.com', 'client-1']]) }
		);

		expect(summary).toEqual({ total: 1, create: 1, update: 0, skip: 0, hold: 0, error: 0 });
		expect(rows[0].planned_action).toBe('create');
		expect(rows[0].resolved_payload).toEqual({
			client_id: 'client-1',
			balance_type: 'receivable',
			amount_minor: 125000,
			currency_code: 'USD',
			as_of_date: '2026-01-01',
			source_note: null
		});
	});

	it('accepts a credit balance with a note, trimming and normalizing an uppercase type', () => {
		const { rows, summary } = review(
			[
				{
					Email: 'bob@example.com',
					Type: 'CREDIT',
					Amount: '$300',
					'As Of': '2026-01-01',
					Note: '  Prepaid deposit  '
				}
			],
			{ emailToClientId: new Map([['bob@example.com', 'client-2']]) }
		);

		expect(summary.create).toBe(1);
		expect(rows[0].resolved_payload).toMatchObject({
			balance_type: 'credit',
			amount_minor: 30000,
			source_note: 'Prepaid deposit'
		});
	});
});

describe('runOpeningBalanceReview — correction', () => {
	it('turns a second fact for a client who already has one of that type into a correction', () => {
		const { rows, summary } = review(
			[{ Email: 'ada@example.com', Type: 'receivable', Amount: '900.00', 'As Of': '2026-02-01' }],
			{
				emailToClientId: new Map([['ada@example.com', 'client-1']]),
				activeFacts: [
					{ client_id: 'client-1', balance_type: 'receivable', opening_balance_id: 'fact-1' }
				]
			}
		);

		expect(summary).toEqual({ total: 1, create: 0, update: 1, skip: 0, hold: 0, error: 0 });
		expect(rows[0].planned_action).toBe('update');
		expect(rows[0].match_client_id).toBe('fact-1');
		expect(rows[0].match_reason).toBe('existing_receivable');
		expect(rows[0].resolved_payload).toMatchObject({ predecessor_opening_balance_id: 'fact-1' });
	});

	it('does not confuse the client’s credit fact with their receivable fact', () => {
		const { rows } = review(
			[{ Email: 'ada@example.com', Type: 'credit', Amount: '50.00', 'As Of': '2026-02-01' }],
			{
				emailToClientId: new Map([['ada@example.com', 'client-1']]),
				activeFacts: [
					{ client_id: 'client-1', balance_type: 'receivable', opening_balance_id: 'fact-1' }
				]
			}
		);

		expect(rows[0].planned_action).toBe('create');
		expect(rows[0].resolved_payload).not.toHaveProperty('predecessor_opening_balance_id');
	});
});

describe('runOpeningBalanceReview — held, never guessed', () => {
	it('holds a second file row that targets the same client and balance type', () => {
		const { rows, summary } = review(
			[
				{ Email: 'ada@example.com', Type: 'receivable', Amount: '900.00', 'As Of': '2026-02-01' },
				{ Email: 'ada@example.com', Type: 'receivable', Amount: '950.00', 'As Of': '2026-02-02' }
			],
			{ emailToClientId: new Map([['ada@example.com', 'client-1']]) }
		);

		expect(summary).toEqual({ total: 2, create: 1, update: 0, skip: 0, hold: 1, error: 0 });
		expect(rows[0].planned_action).toBe('create');
		expect(rows[1].planned_action).toBe('hold');
		expect(rows[1].match_reason).toBe('duplicate_in_file');
	});
});

describe('runOpeningBalanceReview — errors', () => {
	it('errors when the email matches no client', () => {
		const { rows, summary } = review([
			{ Email: 'nobody@example.com', Type: 'receivable', Amount: '100.00', 'As Of': '2026-01-01' }
		]);

		expect(summary.error).toBe(1);
		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].error_message).toMatch(/no client/i);
	});

	it('errors on a balance type that is neither receivable nor credit', () => {
		const { rows } = review(
			[{ Email: 'ada@example.com', Type: 'owed', Amount: '100.00', 'As Of': '2026-01-01' }],
			{ emailToClientId: new Map([['ada@example.com', 'client-1']]) }
		);

		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].error_message).toMatch(/receivable.*credit/i);
	});

	it('errors on a zero or negative amount', () => {
		const { rows } = review(
			[{ Email: 'ada@example.com', Type: 'receivable', Amount: '0', 'As Of': '2026-01-01' }],
			{ emailToClientId: new Map([['ada@example.com', 'client-1']]) }
		);

		expect(rows[0].planned_action).toBe('error');
	});

	it('errors on an invalid as-of date', () => {
		const { rows } = review(
			[{ Email: 'ada@example.com', Type: 'receivable', Amount: '100.00', 'As Of': '13/40/2026' }],
			{ emailToClientId: new Map([['ada@example.com', 'client-1']]) }
		);

		expect(rows[0].planned_action).toBe('error');
	});
});
