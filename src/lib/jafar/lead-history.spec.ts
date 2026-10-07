import { describe, expect, it } from 'vitest';
import { detailChangeLine } from './lead-history';

describe('How a change to a Lead’s details reads in its history', () => {
	it('names a corrected contact detail, from and to', () => {
		expect(
			detailChangeLine({
				field: 'contact_method',
				action: 'changed',
				kind: 'email',
				value: 'info@smithplumbing.co.uk',
				from: 'info@smithplumbng.co.uk',
				to: 'info@smithplumbing.co.uk'
			})
		).toBe('Email changed from info@smithplumbng.co.uk to info@smithplumbing.co.uk');
	});

	it('reads added, removed, and moved-source details in everyday words', () => {
		expect(
			detailChangeLine({
				field: 'contact_method',
				action: 'added',
				kind: 'whatsapp',
				value: '+44 7700 900999'
			})
		).toBe('Added WhatsApp number +44 7700 900999');
		expect(
			detailChangeLine({
				field: 'contact_method',
				action: 'removed',
				kind: 'phone',
				value: '+44 7700 900123'
			})
		).toBe('Removed phone number +44 7700 900123');
		expect(
			detailChangeLine({
				field: 'contact_method',
				action: 'changed',
				kind: 'email',
				value: 'a@b.co',
				found_at_changed: true
			})
		).toBe('Updated where the email a@b.co was found');
	});

	it('shows a country and a source by name, and an added or cleared field plainly', () => {
		expect(detailChangeLine({ field: 'country_code', from: 'IE', to: 'GB' })).toBe(
			'Country changed from Ireland to United Kingdom'
		);
		expect(detailChangeLine({ field: 'source', from: 'google_maps', to: 'referral' })).toMatch(
			/^How you found them changed from .+ to .+$/
		);
		expect(detailChangeLine({ field: 'website', from: null, to: 'smith.co.uk' })).toBe(
			'Website added: smith.co.uk'
		);
		expect(detailChangeLine({ field: 'contact_name', from: 'Sam', to: null })).toBe(
			'Contact person removed (was Sam)'
		);
	});

	it('never copies the fit notes into the history', () => {
		expect(detailChangeLine({ field: 'fit_notes' })).toBe('Updated why they may fit');
	});
});
