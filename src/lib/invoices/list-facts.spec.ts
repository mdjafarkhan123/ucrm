import { describe, expect, it } from 'vitest';
import {
	averagePaidFact,
	invoiceRowNote,
	overdueReminderFact,
	readInvoiceListFacts
} from './list-facts';

describe('invoice facts strip', () => {
	it('reads the database answer', () => {
		expect(
			readInvoiceListFacts({
				paid_count: 6,
				average_days_to_paid: 10,
				overdue_reminders_on: true,
				overdue_reminder_days_after_due: 3
			})
		).toEqual({
			paid_count: 6,
			average_days_to_paid: 10,
			overdue_reminders_on: true,
			overdue_reminder_days_after_due: 3
		});
		expect(readInvoiceListFacts(null).overdue_reminders_on).toBe(false);
	});
	it('average days to get paid', () => {
		const facts = readInvoiceListFacts({ paid_count: 4, average_days_to_paid: 12 });
		expect(averagePaidFact(facts)).toEqual({
			value: '12 days',
			label: 'on average to get paid, past 30 days'
		});
		expect(averagePaidFact({ ...facts, average_days_to_paid: 1 }).value).toBe('1 day');
		expect(averagePaidFact(readInvoiceListFacts({ paid_count: 0 }))).toEqual({
			value: 'No invoices',
			label: 'paid in full in the past 30 days'
		});
	});
	it('overdue reminders', () => {
		const on = readInvoiceListFacts({ overdue_reminders_on: true, overdue_reminder_days_after_due: 1 });
		expect(overdueReminderFact(on)).toEqual({
			value: 'Overdue reminders on',
			label: '1 day after the due date'
		});
		expect(overdueReminderFact({ ...on, overdue_reminder_days_after_due: 5 }).label).toBe(
			'5 days after the due date'
		);
		expect(overdueReminderFact(readInvoiceListFacts({})).value).toBe('Overdue reminders off');
	});
});

describe('invoiceRowNote', () => {
	const waiting = {
		derived_status: 'awaiting_payment' as const,
		is_replaced: false,
		part_paid: false,
		view_count: 0
	};
	it('counts opens of a bill still owed', () => {
		expect(invoiceRowNote(waiting)).toEqual({ text: 'Not opened yet', unopened: true });
		expect(invoiceRowNote({ ...waiting, view_count: 1 })?.text).toBe('Viewed');
		expect(invoiceRowNote({ ...waiting, derived_status: 'past_due', view_count: 4 })?.text).toBe(
			'Viewed 4 times'
		);
	});
	it('part paid wins over opens', () => {
		expect(invoiceRowNote({ ...waiting, part_paid: true, view_count: 3 })?.text).toBe('Part paid');
	});
	it('says nothing for drafts, paid, replaced or never-emailed bills', () => {
		expect(invoiceRowNote({ ...waiting, derived_status: 'draft' })).toBeNull();
		expect(invoiceRowNote({ ...waiting, derived_status: 'paid' })).toBeNull();
		expect(invoiceRowNote({ ...waiting, is_replaced: true })).toBeNull();
		expect(invoiceRowNote({ ...waiting, view_count: null })).toBeNull();
	});
});
