import { describe, expect, it } from 'vitest';
import {
	canSendPreviewNotes,
	previewChoices,
	starterPreviewCards,
	unansweredCards,
	type PreviewVersion
} from './preview';

const preview: PreviewVersion = {
	version: 1,
	released_at: '2026-10-20T10:00:00Z',
	correction_round: true,
	notes_sent_at: null,
	notes_sent_by_name: null,
	cards: [
		{ id: 'a', title: 'Website', summary: 'Five pages', link: null, screenshots: [] },
		{ id: 'b', title: 'Google profile', summary: 'Hours and services', link: null, screenshots: [] }
	],
	notes: []
};

const note = (card_id: string, choice: PreviewVersion['notes'][number]['choice']) => ({
	card_id,
	choice,
	note: choice === 'looks_right' ? null : 'Change the phone number',
	screenshots: [],
	updated_at: '2026-10-20T11:00:00Z',
	kind: null
});

describe('previewChoices', () => {
	it('offers a change while the correction round is open, and only mistakes or new requests after it', () => {
		expect(previewChoices(true)).toEqual(['looks_right', 'needs_change']);
		expect(previewChoices(false)).toEqual(['looks_right', 'uplift_mistake', 'new_request']);
	});
});

describe('canSendPreviewNotes', () => {
	it('needs at least one card asking for something, and only once', () => {
		expect(canSendPreviewNotes(preview)).toBe(false);
		expect(canSendPreviewNotes({ ...preview, notes: [note('a', 'looks_right')] })).toBe(false);
		const asking = { ...preview, notes: [note('a', 'needs_change')] };
		expect(canSendPreviewNotes(asking)).toBe(true);
		expect(canSendPreviewNotes({ ...asking, notes_sent_at: '2026-10-21T09:00:00Z' })).toBe(false);
	});
});

describe('unansweredCards', () => {
	it('lists the cards without a choice', () => {
		expect(
			unansweredCards({ ...preview, notes: [note('a', 'looks_right')] }).map((c) => c.id)
		).toEqual(['b']);
	});
});

describe('starterPreviewCards', () => {
	it('starts with everyone’s cards and those of the package’s services', () => {
		expect(starterPreviewCards([])).toEqual([
			'Your business details',
			'Services and service area',
			'CRM settings and imports'
		]);
		expect(starterPreviewCards(['website', 'google_profile'])).toContain(
			'Forms and where new leads go'
		);
		expect(starterPreviewCards(['website', 'google_profile'])).toContain('Google profile');
		expect(starterPreviewCards(['website'])).not.toContain('Calls and texts');
	});
});
