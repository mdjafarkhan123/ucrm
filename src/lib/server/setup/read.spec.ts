import { describe, expect, it } from 'vitest';
import { SETUP_CATALOGUE_1 } from '$lib/setup/catalogue.fixture';
import { sectionFacts, type SetupAnswers, type SetupCatalogue } from '$lib/setup/catalogue';
import type { SetupClientReview } from '$lib/setup/review';
import { setupSummary, type SetupState } from './read';

// C3b: after a send, a section Uplift sent back is the client's next task until they change it; then sending the
// changes is. With nothing sent back, nothing is next.
const business = SETUP_CATALOGUE_1.sections[0];
const catalogue: SetupCatalogue = {
	...SETUP_CATALOGUE_1,
	sections: [business, { ...business, key: 'services', title: 'Services' }]
};

// Every question answered with "I need Uplift's help", which counts as an answer, and both tasks marked done.
const answers: SetupAnswers = Object.fromEntries(
	sectionFacts(business).map((fact) => [
		fact.key,
		{ availability: 'need_help', value: null, note: null }
	])
);
const sentState: SetupState = {
	welcomeSeen: true,
	answers,
	doneSections: new Set(['business', 'services']),
	sent: { number: 1, submitted_at: '2026-10-04T10:00:00Z', submitted_by_name: 'Sam' }
};

const review = (state: SetupClientReview['state'], changed = false): SetupClientReview => ({
	state,
	note: state === 'returned' ? 'Add your trading name.' : null,
	question_keys: [],
	reviewed_at: '2026-10-04T11:00:00Z',
	changed
});

describe('setupSummary after a send', () => {
	it('has nothing next while every section is with Uplift or accepted', () => {
		const summary = setupSummary(sentState, catalogue, {
			business: review('accepted'),
			services: review('with_uplift')
		});
		expect(summary.next).toBeNull();
		expect(summary.returned_count).toBe(0);
		expect(summary.sections.map((section) => section.review?.state)).toEqual([
			'accepted',
			'with_uplift'
		]);
	});

	it('makes a sent-back section the next task', () => {
		const summary = setupSummary(sentState, catalogue, {
			business: review('accepted'),
			services: review('returned')
		});
		expect(summary.next).toMatchObject({ key: 'services', returned: true });
		expect(summary.returned_count).toBe(1);
	});

	it('asks to send the changes once every sent-back section is changed', () => {
		const summary = setupSummary(sentState, catalogue, {
			business: review('returned', true),
			services: review('returned', true)
		});
		expect(summary.next).toMatchObject({ key: 'check-and-send', returned: false });
		expect(summary.returned_count).toBe(2);
	});

	it('still puts an unfinished task first', () => {
		const summary = setupSummary({ ...sentState, doneSections: new Set(['business']) }, catalogue, {
			business: review('returned')
		});
		expect(summary.next).toMatchObject({ key: 'services', returned: false });
	});
});
