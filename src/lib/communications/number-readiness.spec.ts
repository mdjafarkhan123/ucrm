import { describe, expect, it } from 'vitest';
import {
	numberCard,
	readinessSummary,
	summaryCount,
	summaryLine,
	type ReadinessNumber,
	type ReadinessRegistration
} from './number-readiness';

const now = new Date('2026-10-22T12:00:00Z');

function number(overrides: Partial<ReadinessNumber> = {}): ReadinessNumber {
	return {
		sender_id: 'sender-1',
		order_id: 'order-1',
		phone_number: '+12065550187',
		display_name: 'Seattle office',
		country_code: 'US',
		sender_type: 'long_code',
		number_type: 'local',
		lifecycle_state: 'pending_setup',
		capabilities: { sms: true, mms: true, voice: true },
		is_default_sender: false,
		created_at: '2026-10-18T10:00:00Z',
		order: {
			state: 'completed',
			purchased_at: '2026-10-18T10:00:00Z',
			created_at: '2026-10-18T10:00:00Z',
			needs_paperwork: false
		},
		paperwork: null,
		toll_free_check: null,
		...overrides
	};
}

const registration = (
	status: ReadinessRegistration['status'],
	extra: Partial<ReadinessRegistration> = {}
): ReadinessRegistration => ({
	status,
	required_fixes: null,
	submitted_at: '2026-10-20T10:00:00Z',
	updated_at: '2026-10-20T10:00:00Z',
	...extra
});

const states = (card: ReturnType<typeof numberCard>) =>
	card.steps.map((step) => `${step.key}:${step.state}`);

describe('numberCard', () => {
	it('asks for business details on a US local number with no registration yet', () => {
		const card = numberCard(number(), null, now);
		expect(states(card)).toEqual([
			'bought:done',
			'paperwork:done',
			'approval:your_turn',
			'texting:not_yet'
		]);
		expect(card.status).toBe('business_details_needed');
		expect(card.action?.kind).toBe('add_business_details');
		expect(card.can_be_default).toBe(false);
	});

	it('shows the US registration under review with when it was sent', () => {
		const card = numberCard(number(), registration('under_review'), now);
		expect(card.steps[2]).toMatchObject({ state: 'waiting', hint: 'Sent Oct 20' });
		expect(card.status).toBe('under_review');
		expect(card.action?.kind).toBe('see_business_details');
	});

	it('turns a refused registration into an action with a fix', () => {
		const card = numberCard(
			number(),
			registration('action_needed', { required_fixes: 'Add STOP wording' }),
			now
		);
		expect(card.steps[2]).toMatchObject({ state: 'failed', hint: 'Turned down' });
		expect(card.status).toBe('action_needed');
		expect(card.action?.kind).toBe('fix_business_details');
	});

	it('is switching on once the registration is approved but the number is not live yet', () => {
		const card = numberCard(number(), registration('approved'), now);
		expect(card.steps[2].state).toBe('done');
		expect(card.status).toBe('getting_ready');
		expect(card.can_text).toBe(false);
	});

	it('is ready to text once the number is live, and only then can be the default', () => {
		const card = numberCard(number({ lifecycle_state: 'ready' }), registration('approved'), now);
		expect(states(card)).toEqual([
			'bought:done',
			'paperwork:done',
			'approval:done',
			'texting:done'
		]);
		expect(card.status).toBe('ready_to_text');
		expect(card.line).toContain('United States');
		expect(card.can_be_default).toBe(true);
	});

	it('needs no approval for a Canadian local number texting Canada', () => {
		const card = numberCard(
			number({ country_code: 'CA', phone_number: '+16045550142', lifecycle_state: 'ready' }),
			null,
			now
		);
		expect(card.steps[2]).toMatchObject({ state: 'done', hint: 'Not needed' });
		expect(card.steps[3].hint).toBe('Canada');
		expect(card.status).toBe('ready_to_text');
	});

	it('marks a toll-free number as needing its own check without borrowing the US form', () => {
		const card = numberCard(
			number({ sender_type: 'toll_free', number_type: 'toll_free', display_name: 'Toll-free' }),
			registration('approved'),
			now
		);
		expect(card.detail).toBe('+1 206-555-0187 · US and Canada · Toll-free');
		expect(card.steps[2].state).toBe('your_turn');
		expect(card.status).toBe('business_details_needed');
		expect(card.action).toMatchObject({ kind: 'toll_free_check', label: 'Add business details' });
	});

	it('follows a toll-free number through its own check: sent, turned down, approved', () => {
		const tollFree = (check: Partial<NonNullable<ReadinessNumber['toll_free_check']>>) =>
			number({
				sender_type: 'toll_free',
				number_type: 'toll_free',
				toll_free_check: {
					id: 'check-1',
					status: 'under_review',
					failure_reason: null,
					submitted_at: '2026-10-21T10:00:00Z',
					decided_at: null,
					edit_expires_at: null,
					...check
				}
			});

		const sent = numberCard(tollFree({}), null, now);
		expect(sent.steps[2]).toMatchObject({ state: 'waiting', hint: 'Sent Oct 21' });
		expect(sent.status).toBe('under_review');
		expect(sent.line).toContain('toll-free');

		const turnedDown = numberCard(
			tollFree({
				status: 'needs_fix',
				failure_reason: 'Business email must use an official domain.',
				edit_expires_at: '2026-10-28T10:00:00Z'
			}),
			// A US registration's own state never decides a toll-free number.
			registration('approved'),
			now
		);
		expect(turnedDown.steps[2]).toMatchObject({ state: 'failed', hint: 'Turned down' });
		expect(turnedDown.status).toBe('action_needed');
		expect(turnedDown.title).toBe('Carriers turned down your toll-free check');
		expect(turnedDown.line).toBe(
			'Business email must use an official domain. Send the fix by Oct 28.'
		);

		const approved = numberCard(tollFree({ status: 'approved' }), null, now);
		expect(approved.steps[2].state).toBe('done');
		expect(approved.status).toBe('getting_ready');

		const live = numberCard(
			{ ...tollFree({ status: 'approved' }), lifecycle_state: 'ready' },
			null,
			now
		);
		expect(live.status).toBe('ready_to_text');
		expect(live.line).toBe('Customers in US and Canada get your texts from this number.');
	});

	it('shows a number still being bought as connecting, with no sender yet', () => {
		const card = numberCard(
			number({
				sender_id: null,
				display_name: null,
				lifecycle_state: null,
				order: {
					state: 'purchasing',
					purchased_at: null,
					created_at: '2026-10-22T11:59:00Z',
					needs_paperwork: false
				}
			}),
			null,
			now
		);
		expect(states(card)).toEqual([
			'bought:connecting',
			'paperwork:not_yet',
			'approval:not_yet',
			'texting:not_yet'
		]);
		expect(card.status).toBe('getting_ready');
		expect(card.key).toBe('order:order-1');
		expect(card.name).toBe('+1 206-555-0187');
		expect(card.detail).toBe('United States · Local');
	});

	it('asks for a paperwork update while a number keeps texting', () => {
		const card = numberCard(
			number({
				country_code: 'GB',
				phone_number: '+447700900412',
				number_type: 'mobile',
				display_name: 'London',
				lifecycle_state: 'ready',
				order: {
					state: 'completed',
					purchased_at: '2026-09-30T10:00:00Z',
					created_at: '2026-09-30T10:00:00Z',
					needs_paperwork: true
				},
				paperwork: {
					id: 'pw-1',
					status: 'needs_fix',
					failure_reason: 'The UK now asks for your company number.',
					valid_until: '2026-11-21T00:00:00Z',
					submitted_at: null,
					decided_at: null
				}
			}),
			null,
			now
		);
		expect(card.steps[1]).toMatchObject({ state: 'failed', hint: 'Needs update' });
		expect(card.steps[3].state).toBe('done');
		expect(card.can_text).toBe(true);
		expect(card.status).toBe('action_needed');
		expect(card.title).toBe('United Kingdom paperwork needs an update');
		expect(card.line).toContain('Add it by Nov 21 so this number keeps texting.');
		expect(card.action).toEqual({
			kind: 'update_paperwork',
			label: 'Update paperwork',
			paperwork_id: 'pw-1'
		});
	});

	it('says texting is paused when the paperwork date passed', () => {
		const card = numberCard(
			number({
				country_code: 'GB',
				phone_number: '+447700900412',
				lifecycle_state: 'suspended',
				order: {
					state: 'completed',
					purchased_at: '2026-09-30T10:00:00Z',
					created_at: '2026-09-30T10:00:00Z',
					needs_paperwork: true
				},
				paperwork: {
					id: 'pw-1',
					status: 'approved',
					failure_reason: null,
					valid_until: '2026-10-01T00:00:00Z',
					submitted_at: null,
					decided_at: '2026-09-29T00:00:00Z'
				}
			}),
			null,
			now
		);
		expect(card.steps[1]).toMatchObject({ state: 'failed', hint: 'Date passed' });
		expect(card.steps[3]).toMatchObject({ state: 'failed', hint: 'Paused' });
		expect(card.status).toBe('texting_paused');
		expect(card.title).toBe('Texting paused: United Kingdom paperwork date passed');
		expect(card.action?.kind).toBe('update_paperwork');
	});
});

describe('readinessSummary', () => {
	const london = number({
		sender_id: 'gb',
		country_code: 'GB',
		display_name: 'London',
		lifecycle_state: 'ready',
		order: {
			state: 'completed',
			purchased_at: null,
			created_at: '2026-09-30T10:00:00Z',
			needs_paperwork: true
		},
		paperwork: {
			id: 'pw',
			status: 'needs_fix',
			failure_reason: 'Company number missing.',
			valid_until: null,
			submitted_at: null,
			decided_at: null
		}
	});
	const tollFree = number({
		sender_id: 'tf',
		display_name: 'Toll-free',
		sender_type: 'toll_free',
		number_type: 'toll_free'
	});
	const seattle = number({ sender_id: 'us' });
	const main = number({
		sender_id: 'ca',
		country_code: 'CA',
		display_name: 'Main line',
		lifecycle_state: 'ready'
	});

	it('counts what can text and names what needs the business', () => {
		const numbers = [london, tollFree, seattle, main];
		const cards = numbers.map((n) => numberCard(n, registration('under_review'), now));
		const summary = readinessSummary(numbers, cards);
		expect(summaryCount(summary)).toBe('2 of 4');
		expect(summaryLine(summary)).toBe(
			'Two more are on their way. London and Toll-free each need one thing from you.'
		);
		expect(summary.counts).toEqual({
			action_needed: 1,
			business_details_needed: 1,
			under_review: 1,
			ready_to_text: 1
		});
		expect(summary.countries).toEqual([
			{ code: 'CA', name: 'Canada', ready: true },
			{ code: 'GB', name: 'United Kingdom', ready: true },
			{ code: 'US', name: 'United States', ready: false }
		]);
	});

	it('says nothing needs the business when every number texts', () => {
		const numbers = [main, number({ sender_id: 'us', lifecycle_state: 'ready' })];
		const cards = numbers.map((n) => numberCard(n, registration('approved'), now));
		const summary = readinessSummary(numbers, cards);
		expect(summaryCount(summary)).toBe('All 2');
		expect(summaryLine(summary)).toBe(
			'Nothing needs you. Customers in all two countries get your texts.'
		);
	});

	it('greets a first number on its way', () => {
		const numbers = [seattle];
		const cards = numbers.map((n) => numberCard(n, registration('under_review'), now));
		const summary = readinessSummary(numbers, cards);
		expect(summaryCount(summary)).toBe('0 of 1');
		expect(summaryLine(summary)).toBe(
			'Your first number is on its way. Carriers are checking your US texting registration, usually 3 to 7 working days. The answer shows here.'
		);
	});
});

describe('renewal strip (Part 7)', () => {
	const ready = (renewal: ReadinessNumber['renewal']) =>
		number({ lifecycle_state: 'ready', country_code: 'CA', renewal });
	const paid = {
		state: 'paid' as const,
		renews_at: '2026-11-02T00:00:00Z',
		price_minor: 115,
		currency: 'USD',
		unpaid_since: null,
		grace_ends_at: null,
		released_at: null
	};

	it('shows the next renewal and that the balance covers it', () => {
		const card = numberCard(ready(paid), null, now, { available_minor: 460, currency: 'USD' });
		expect(card.renewal).toMatchObject({
			tone: 'paid',
			eyebrow: 'RENEWS',
			headline: 'Nov 2 · $1.15',
			add_money: false,
			meter: { kind: 'balance', left: 'Balance $4.60 covers it', fraction: 1 }
		});
		expect(card.status).toBe('ready_to_text');
	});

	it('warns 3 days ahead when the balance is short, and stays calm before that', () => {
		const soon = numberCard(ready(paid), null, new Date('2026-10-30T09:00:00Z'), {
			available_minor: 40,
			currency: 'USD'
		});
		expect(soon.renewal).toMatchObject({
			tone: 'short',
			eyebrow: 'RENEWS IN 3 DAYS',
			add_money: true,
			meter: { left: '$0.40 of $1.15', right: 'short by $0.75' }
		});
		const early = numberCard(ready(paid), null, now, { available_minor: 40, currency: 'USD' });
		expect(early.renewal?.tone).toBe('paid');
		expect(early.renewal?.eyebrow).toBe('RENEWS');
	});

	it('counts down the 14-day grace and pauses sending after a failed renewal', () => {
		const card = numberCard(
			ready({
				...paid,
				state: 'unpaid',
				unpaid_since: '2026-11-02T00:00:00Z',
				grace_ends_at: '2026-11-16T00:00:00Z'
			}),
			null,
			new Date('2026-11-07T00:00:00Z'),
			{ available_minor: 40, currency: 'USD' }
		);
		expect(card.renewal).toMatchObject({
			tone: 'unpaid',
			eyebrow: 'UNPAID SINCE NOV 2',
			headline: 'Add $0.75',
			meter: { kind: 'days', left: '9 of 14 days left', right: 'released Nov 16', days_left: 9 }
		});
		expect(card.steps[3]).toMatchObject({ state: 'paused', hint: 'Paused' });
		expect(card.status).toBe('sending_paused');
		expect(card.can_text).toBe(false);
	});

	it('ends a released number and leaves it out of the summary', () => {
		const released = number({
			lifecycle_state: 'released',
			is_default_sender: true,
			renewal: { ...paid, state: 'released', released_at: '2026-11-16T00:00:00Z' }
		});
		const card = numberCard(released, null, now);
		expect(card.renewal).toMatchObject({
			tone: 'released',
			headline: 'Nov 16 · it no longer renews',
			note: 'Your conversations are kept.',
			meter: null
		});
		expect(card.steps[3]).toMatchObject({ state: 'ended', hint: 'Ended' });
		expect(card).toMatchObject({ status: 'released', released: true, is_default: false });
		expect(card.action?.kind).toBe('add_number');
		const other = number({ sender_id: 'sender-2', lifecycle_state: 'ready', country_code: 'CA' });
		const summary = readinessSummary([released, other], [card, numberCard(other, null, now)]);
		expect(summary.total).toBe(1);
	});

	it('has no strip while a number is still connecting', () => {
		expect(numberCard(number({ renewal: undefined }), null, now).renewal).toBeNull();
	});
});
