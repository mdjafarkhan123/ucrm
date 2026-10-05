import { describe, expect, it } from 'vitest';
import type { SetupFact } from '$lib/setup/catalogue';
import type { SetupHelpItem } from '$lib/setup/help';
import {
	addBusinessDays,
	previewSetupReadyRange,
	setupReadyBlockers,
	setupReadyBlockerText,
	todayIn
} from '$lib/setup/ready';

const sections = [
	{ key: 'business', title: 'Your business' },
	{ key: 'brand', title: 'Brand and photos' }
];
const accepted = { state: 'accepted' as const, decision: null };

function helpItem(required: boolean, answered: boolean): SetupHelpItem {
	return {
		section_key: 'business',
		section_title: 'Your business',
		fact_key: 'business.public_phone',
		label: 'Public phone',
		fact: { key: 'business.public_phone', required } as SetupFact,
		form: 'box',
		client_note: null,
		answer: answered
			? {
					value: '+44 20 7946 0958',
					note: null,
					lines: [],
					recorded_by_email: 'jafar@example.com',
					recorded_at: '2026-10-05T09:00:00Z'
				}
			: null
	};
}

const none = { paused: false, payment_reversed: false };

describe('setupReadyBlockers', () => {
	it('blocks before the first send', () => {
		expect(setupReadyBlockers({ account: none, sections: null, reviews: {}, help: [] })).toEqual([
			{ kind: 'not_sent' }
		]);
	});

	it('names each task that is not accepted, in task order, whatever else it is', () => {
		const blockers = setupReadyBlockers({
			account: none,
			sections,
			reviews: { business: { state: 'returned', decision: null } },
			help: []
		});
		expect(blockers).toEqual([
			{ kind: 'task', section_key: 'business', section_title: 'Your business', state: 'returned' },
			{ kind: 'task', section_key: 'brand', section_title: 'Brand and photos', state: 'to_review' }
		]);
		expect(blockers.map(setupReadyBlockerText)).toEqual([
			'Your business: sent back. Waiting for the client to change it.',
			'Brand and photos: not reviewed yet. Accept it or send it back.'
		]);
	});

	it('blocks on an open help request only when the question is required', () => {
		const reviews = { business: accepted, brand: accepted };
		const open = (required: boolean) =>
			setupReadyBlockers({ account: none, sections, reviews, help: [helpItem(required, false)] });
		expect(open(true)).toEqual([
			{
				kind: 'help',
				section_key: 'business',
				section_title: 'Your business',
				fact_key: 'business.public_phone',
				label: 'Public phone'
			}
		]);
		expect(open(false)).toEqual([]);
		expect(
			setupReadyBlockers({ account: none, sections, reviews, help: [helpItem(true, true)] })
		).toEqual([]);
	});

	it('blocks a paused account and a reversed payment even with everything accepted', () => {
		expect(
			setupReadyBlockers({
				account: { paused: true, payment_reversed: true },
				sections,
				reviews: { business: accepted, brand: accepted },
				help: []
			})
		).toEqual([{ kind: 'account_paused' }, { kind: 'payment_reversed' }]);
	});
});

describe('business days', () => {
	// The same cases the database's private.setup_add_business_days was checked with.
	it.each([
		['2026-10-05', '2026-10-14', '2026-10-19'], // Monday
		['2026-10-09', '2026-10-20', '2026-10-23'], // Friday
		['2026-10-10', '2026-10-20', '2026-10-23'], // Saturday
		['2026-10-11', '2026-10-20', '2026-10-23'] // Sunday
	])('from %s, the 7th is %s and the 10th %s', (start, from, to) => {
		expect(addBusinessDays(start, 7)).toBe(from);
		expect(addBusinessDays(start, 10)).toBe(to);
	});

	it('counts from the client’s own date, not the server’s', () => {
		// 23:30 in London on Sunday is already Monday in Sydney.
		const now = new Date('2026-10-11T22:30:00Z');
		expect(todayIn('Europe/London', now)).toBe('2026-10-11');
		expect(todayIn('Australia/Sydney', now)).toBe('2026-10-12');
		expect(previewSetupReadyRange('Australia/Sydney', now)).toEqual({
			start_date: '2026-10-12',
			target_from: '2026-10-21',
			target_to: '2026-10-26'
		});
	});

	it('counts an unknown time zone in UTC, as the database does', () => {
		expect(todayIn('Not/AZone', new Date('2026-10-11T22:30:00Z'))).toBe('2026-10-11');
	});
});
