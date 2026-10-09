import { describe, expect, it } from 'vitest';
import { customerNoticeToast } from './customer-notices';

describe('customerNoticeToast', () => {
	it('tells the user which email the save queued', () => {
		expect(customerNoticeToast('booked')).toBe('The customer will get a booking confirmation.');
		expect(customerNoticeToast('rescheduled')).toBe('The customer will get the new time by email.');
	});

	it('says nothing when no email was queued', () => {
		expect(customerNoticeToast(null)).toBeNull();
		expect(customerNoticeToast(undefined)).toBeNull();
	});
});
