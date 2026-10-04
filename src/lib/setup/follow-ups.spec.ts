import { describe, expect, it } from 'vitest';
import { followUpSuggestions } from './follow-ups';

const have = (value: string) => ({ availability: 'have' as const, value, note: null });

describe('followUpSuggestions', () => {
	it('suggests nothing for a client who has not answered the follow-ups', () => {
		expect(followUpSuggestions({}, null)).toEqual({
			'business.legal_name_differs': null,
			'business.contact_is_approver': null,
			'business.availability': null,
			'business.hours_seasonal_changes': null
		});
	});

	it('suggests a different legal name only when it is not the public name', () => {
		const differs = (legal: string) =>
			followUpSuggestions(
				{ 'business.public_name': have('Raad LTD'), 'business.legal_name': have(legal) },
				null
			)['business.legal_name_differs'];
		expect(differs('Raad Trading Limited')).toBe('yes');
		expect(differs('raad ltd')).toBe('no');
	});

	it('reads a named approver as the main contact not approving', () => {
		expect(
			followUpSuggestions({ 'business.approver_name': have('Sam Lee') }, null)[
				'business.contact_is_approver'
			]
		).toBe('no');
	});

	it('ignores a follow-up the client deferred', () => {
		const deferred = { availability: 'need_help' as const, value: null, note: null };
		expect(
			followUpSuggestions({ 'business.legal_name': deferred }, null)['business.legal_name_differs']
		).toBeNull();
	});

	it('suggests how customers reach the business from its hours', () => {
		expect(
			followUpSuggestions({ 'business.hours': have('{}') }, null)['business.availability']
		).toBe('set_hours');
		expect(followUpSuggestions({}, 'weekly')['business.availability']).toBe('set_hours');
		expect(followUpSuggestions({}, 'appointment_only')['business.availability']).toBe(
			'appointment_only'
		);
	});

	it('reads written seasonal changes as the hours changing by season', () => {
		expect(
			followUpSuggestions({ 'business.hours_seasonal': have('Closed in January') }, null)[
				'business.hours_seasonal_changes'
			]
		).toBe('yes');
	});
});
