import { describe, expect, it } from 'vitest';
import {
	draftDifferences,
	formatUsd,
	missingRequirements,
	slugify,
	type AllowanceReference,
	type CapabilityReference,
	type DraftForm
} from './packages';

const capabilities: CapabilityReference[] = [
	{
		key: 'core.jobs',
		label: 'Jobs',
		description: 'Jobs',
		kind: 'core',
		sellable: true,
		requires: []
	},
	{
		key: 'communications.inbox',
		label: 'Shared inbox',
		description: 'Inbox',
		kind: 'extra',
		sellable: false,
		requires: []
	},
	{
		key: 'website_chat',
		label: 'Website chat',
		description: 'Chat',
		kind: 'extra',
		sellable: false,
		requires: ['communications.inbox']
	}
];

const allowances: AllowanceReference[] = [
	{
		key: 'employee_seats',
		capability_key: 'core.jobs',
		label: 'Team seats',
		unit: 'seats',
		resets_monthly: false
	},
	{
		key: 'website_chat_widgets',
		capability_key: 'website_chat',
		label: 'Website chat widgets',
		unit: 'widgets',
		resets_monthly: false
	}
];

function draft(overrides: Partial<DraftForm> = {}): DraftForm {
	return {
		slug: 'growth',
		name: 'Growth',
		promise: '',
		highlights: [],
		included_services: [],
		exclusions: '',
		monthly_price_usd_cents: 24900,
		yearly_price_usd_cents: null,
		capabilities: ['core.jobs'],
		allowances: [
			{ key: 'employee_seats', state: 'numeric', value: 5 },
			{ key: 'website_chat_widgets', state: 'not_included', value: null }
		],
		...overrides
	};
}

describe('missingRequirements', () => {
	it('names the shared inbox when website chat is chosen without it', () => {
		const missing = missingRequirements(['core.jobs', 'website_chat'], capabilities);
		expect(missing).toHaveLength(1);
		expect(missing[0].capability.label).toBe('Website chat');
		expect(missing[0].missing.map((capability) => capability.label)).toEqual(['Shared inbox']);
	});

	it('is empty once the requirement is included', () => {
		expect(
			missingRequirements(['core.jobs', 'website_chat', 'communications.inbox'], capabilities)
		).toEqual([]);
	});
});

describe('draftDifferences', () => {
	it('lists only the fields that differ, in words', () => {
		const differences = draftDifferences(
			draft({ name: 'Growth Plus' }),
			draft({ monthly_price_usd_cents: 29900 }),
			capabilities,
			allowances
		);
		expect(differences).toEqual([
			{ field: 'name', label: 'Name', mine: 'Growth Plus', saved: 'Growth' },
			{ field: 'monthly', label: 'Monthly price', mine: '$249', saved: '$299' }
		]);
	});

	it('describes extras and the allowances that apply to them', () => {
		const withChat = draft({
			capabilities: ['core.jobs', 'website_chat', 'communications.inbox'],
			allowances: [
				{ key: 'employee_seats', state: 'unlimited', value: null },
				{ key: 'website_chat_widgets', state: 'numeric', value: 2 }
			]
		});
		const differences = draftDifferences(withChat, draft(), capabilities, allowances);
		expect(differences.find((difference) => difference.field === 'capabilities')).toMatchObject({
			mine: 'Shared inbox, Website chat',
			saved: 'None'
		});
		expect(differences.find((difference) => difference.field === 'allowances')).toMatchObject({
			mine: 'Team seats: unlimited, Website chat widgets: 2',
			saved: 'Team seats: 5'
		});
	});

	it('finds nothing when both tabs saved the same terms', () => {
		expect(draftDifferences(draft(), draft(), capabilities, allowances)).toEqual([]);
	});
});

describe('slugify and formatUsd', () => {
	it('turns a package name into a web address', () => {
		expect(slugify('  Growth Plus! Café ')).toBe('growth-plus-cafe');
	});

	it('shows whole dollars without cents and blanks for no price', () => {
		expect(formatUsd(24900)).toBe('$249');
		expect(formatUsd(24950)).toBe('$249.50');
		expect(formatUsd(null)).toBe('—');
	});
});
