import { describe, expect, it } from 'vitest';
import {
	runReview,
	type ExistingClient,
	type ImportColumnMapping,
	type ReviewInputs
} from './review';

const MAPPING: ImportColumnMapping = {
	'First name': { field: 'first_name' },
	'Last name': { field: 'last_name' },
	Company: { field: 'company_name' },
	Email: { field: 'email' },
	Phone: { field: 'phone' },
	Street: { field: 'property.address_line1' },
	City: { field: 'property.city' }
};

// Assemble runReview inputs, letting each test override only what it cares about.
function review(
	rows: Record<string, string>[],
	overrides: Partial<ReviewInputs> = {}
): ReturnType<typeof runReview> {
	return runReview({
		rows,
		mapping: MAPPING,
		matchAction: 'skip',
		emailToClientId: new Map(),
		phoneToClientId: new Map(),
		clientsById: new Map(),
		...overrides
	});
}

function existing(partial: Partial<ExistingClient> & { id: string }): ExistingClient {
	return {
		client_type: 'person',
		first_name: null,
		last_name: null,
		company_name: null,
		lead_source: null,
		has_email: false,
		has_phone: false,
		has_property: false,
		...partial
	};
}

describe('runReview — create', () => {
	it('creates a brand-new person as a full customer with their contact info and property', () => {
		const { rows, summary } = review([
			{
				'First name': 'Ada',
				'Last name': 'Lovelace',
				Email: 'ada@example.com',
				Phone: '(555) 111-2222',
				Street: '12 Byron Rd',
				City: 'Bath'
			}
		]);

		expect(summary.create).toBe(1);
		const row = rows[0];
		expect(row.planned_action).toBe('create');
		expect(row.resolved_payload?.client).toMatchObject({
			client_type: 'person',
			first_name: 'Ada',
			last_name: 'Lovelace',
			display_name: 'Ada Lovelace',
			lifecycle_status: 'customer'
		});
		expect(row.resolved_payload?.email).toBe('ada@example.com');
		expect(row.resolved_payload?.phone).toBe('(555) 111-2222');
		expect(row.resolved_payload?.property).toMatchObject({
			address_line1: '12 Byron Rd',
			city: 'Bath'
		});
		expect(row.flags).toEqual([]);
	});

	it('treats a company name with no personal name as a company', () => {
		const { rows } = review([{ Company: 'Bright Spark Ltd', Email: 'hi@brightspark.com' }]);
		expect(rows[0].planned_action).toBe('create');
		expect(rows[0].resolved_payload?.client).toMatchObject({
			client_type: 'company',
			company_name: 'Bright Spark Ltd',
			display_name: 'Bright Spark Ltd'
		});
	});

	it('imports a row with no email or phone, flagged', () => {
		const { rows } = review([{ 'First name': 'No', 'Last name': 'Contact' }]);
		expect(rows[0].planned_action).toBe('create');
		expect(rows[0].resolved_payload?.email).toBeNull();
		expect(rows[0].resolved_payload?.phone).toBeNull();
		expect(rows[0].flags).toContain('no_contact_method');
	});

	it('flags property cells with no street rather than inventing a property', () => {
		const { rows } = review([{ 'First name': 'Grace', 'Last name': 'Hopper', City: 'Arlington' }]);
		expect(rows[0].planned_action).toBe('create');
		expect(rows[0].resolved_payload?.property).toBeNull();
		expect(rows[0].flags).toContain('property_skipped_no_address');
	});
});

describe('runReview — errors', () => {
	it('marks a person missing a required name as an error, not a create', () => {
		const { rows, summary } = review([{ 'First name': 'Solo', Email: 'solo@example.com' }]);
		expect(summary.error).toBe(1);
		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].resolved_payload).toBeNull();
		expect(rows[0].error_message).toBeTruthy();
	});

	it('marks an invalid email as an error', () => {
		const { rows } = review([{ 'First name': 'Bad', 'Last name': 'Email', Email: 'not-an-email' }]);
		expect(rows[0].planned_action).toBe('error');
	});
});

describe('runReview — matching', () => {
	it('skips a row that matches an existing client when the action is skip', () => {
		const { rows, summary } = review(
			[{ 'First name': 'Ada', 'Last name': 'Lovelace', Email: 'ada@example.com' }],
			{ emailToClientId: new Map([['ada@example.com', 'client-a']]) }
		);
		expect(summary.skip).toBe(1);
		expect(rows[0].planned_action).toBe('skip');
		expect(rows[0].match_client_id).toBe('client-a');
		expect(rows[0].match_reason).toBe('email');
		expect(rows[0].resolved_payload).toBeNull();
	});

	it('holds a row whose email and phone point at two different clients', () => {
		const { rows, summary } = review(
			[
				{
					'First name': 'Split',
					'Last name': 'Match',
					Email: 'ada@example.com',
					Phone: '555-9999'
				}
			],
			{
				emailToClientId: new Map([['ada@example.com', 'client-a']]),
				phoneToClientId: new Map([['5559999', 'client-b']])
			}
		);
		expect(summary.hold).toBe(1);
		expect(rows[0].planned_action).toBe('hold');
		expect(rows[0].match_reason).toBe('email_phone_conflict');
	});
});

describe('runReview — in-file first wins', () => {
	it('gives a shared phone to the first row and flags the later one', () => {
		const { rows } = review([
			{ 'First name': 'First', 'Last name': 'Win', Phone: '555-000-1111' },
			{ 'First name': 'Second', 'Last name': 'Loss', Phone: '(555) 000 1111' }
		]);
		expect(rows[0].resolved_payload?.phone).toBe('555-000-1111');
		expect(rows[0].flags).not.toContain('phone_shared_in_file');
		expect(rows[1].resolved_payload?.phone).toBeNull();
		expect(rows[1].flags).toContain('phone_shared_in_file');
	});
});

describe('runReview — update', () => {
	const base = {
		matchAction: 'update' as const,
		phoneToClientId: new Map([['5551234', 'client-a']])
	};

	it('changes only the fields that differ and recomputes the display name', () => {
		const { rows, summary } = review(
			[{ 'First name': 'Ada', 'Last name': 'King', Phone: '555-1234' }],
			{
				...base,
				clientsById: new Map([
					['client-a', existing({ id: 'client-a', first_name: 'Ada', last_name: 'Lovelace' })]
				])
			}
		);
		expect(summary.update).toBe(1);
		expect(rows[0].planned_action).toBe('update');
		expect(rows[0].resolved_payload?.client).toEqual({
			last_name: 'King',
			display_name: 'Ada King'
		});
	});

	it('respects the "don\'t overwrite" toggle on a field that already has a value', () => {
		const mapping: ImportColumnMapping = {
			'Last name': { field: 'last_name', dont_overwrite: true },
			Phone: { field: 'phone' }
		};
		const { rows } = runReview({
			rows: [{ 'Last name': 'King', Phone: '555-1234' }],
			mapping,
			...base,
			emailToClientId: new Map(),
			clientsById: new Map([
				['client-a', existing({ id: 'client-a', first_name: 'Ada', last_name: 'Lovelace' })]
			])
		});
		// Last name is protected and unchanged, phone already matched — nothing left to write, so it becomes a skip.
		expect(rows[0].planned_action).toBe('skip');
		expect(rows[0].flags).toContain('already_up_to_date');
	});

	it('adds a new email to a phone-matched client that has none', () => {
		const { rows } = review(
			[
				{
					'First name': 'Ada',
					'Last name': 'Lovelace',
					Email: 'new@example.com',
					Phone: '555-1234'
				}
			],
			{
				...base,
				clientsById: new Map([
					[
						'client-a',
						existing({
							id: 'client-a',
							first_name: 'Ada',
							last_name: 'Lovelace',
							has_phone: true
						})
					]
				])
			}
		);
		expect(rows[0].planned_action).toBe('update');
		expect(rows[0].resolved_payload?.email).toBe('new@example.com');
	});
});
