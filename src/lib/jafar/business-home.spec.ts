import { describe, expect, it } from 'vitest';
import { agendaTag, groupAgenda, type HomeAgendaItem } from './business-home';

function item(id: string, due_on: string, extra: Partial<HomeAgendaItem> = {}): HomeAgendaItem {
	return {
		id,
		business_name: `Business ${id}`,
		country_code: 'GB',
		trade: 'Plumbing',
		next_action: `Step ${id}`,
		due_on,
		first_contact: false,
		deal_stage: null,
		call_id: null,
		...extra
	};
}

describe('groupAgenda', () => {
	it('puts overdue first, then today, then the coming week, keeping the order it was given', () => {
		const groups = groupAgenda(
			[
				item('a', '2026-10-01'),
				item('b', '2026-10-06'),
				item('c', '2026-10-07'),
				item('d', '2026-10-09')
			],
			'2026-10-07'
		);
		expect(groups.map((group) => [group.key, group.items.map((entry) => entry.id)])).toEqual([
			['overdue', ['a', 'b']],
			['today', ['c']],
			['upcoming', ['d']]
		]);
	});

	it('keeps all three groups even when one is empty', () => {
		expect(groupAgenda([], '2026-10-07').map((group) => group.items.length)).toEqual([0, 0, 0]);
	});
});

describe('agendaTag', () => {
	it('names a first contact before anything else', () => {
		expect(agendaTag({ first_contact: true, deal_stage: 'interested' }).label).toBe(
			'First contact'
		);
	});

	it('names the step from the open Deal', () => {
		expect(agendaTag({ first_contact: false, deal_stage: 'interested' }).label).toBe('Reply');
		expect(agendaTag({ first_contact: false, deal_stage: 'call_booked' }).label).toBe('Call');
		expect(agendaTag({ first_contact: false, deal_stage: 'pricing_shared' }).label).toBe('Pricing');
		expect(agendaTag({ first_contact: false, deal_stage: 'awaiting_decision' }).label).toBe(
			'Pricing'
		);
		expect(agendaTag({ first_contact: false, deal_stage: 'later' }).label).toBe('Later');
	});

	it('calls a Lead without a Deal a follow-up', () => {
		expect(agendaTag({ first_contact: false, deal_stage: null })).toEqual({
			label: 'Follow-up',
			tone: 'neutral'
		});
	});
});
