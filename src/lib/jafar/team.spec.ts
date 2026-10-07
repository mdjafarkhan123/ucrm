import { describe, expect, it } from 'vitest';
import { describeTeamHistoryEntry, type TeamAccessHistoryEntry } from './team';

function entry(partial: Partial<TeamAccessHistoryEntry>): TeamAccessHistoryEntry {
	return {
		id: 'e1',
		event_type: 'team_access_changed',
		actor_email: 'owner@example.com',
		created_at: '2026-10-07T10:00:00Z',
		before_state: null,
		after_state: null,
		...partial
	};
}

describe('teammate history wording', () => {
	it('says what an access change did, area by area', () => {
		const lines = describeTeamHistoryEntry(
			entry({
				before_state: { role: 'sales', area_adjustments: {}, action_grants: [] },
				after_state: {
					role: 'sales',
					area_adjustments: { applications: 'work', leads: 'none' },
					action_grants: ['payments']
				}
			})
		);
		expect(lines).toEqual([
			'Leads & Deals: can change → off',
			'Applications: view only → can change',
			'Turned on: Confirm and undo payments'
		]);
	});

	it('names a role change and what it changed', () => {
		const lines = describeTeamHistoryEntry(
			entry({
				before_state: { role: 'sales', area_adjustments: {}, action_grants: [] },
				after_state: { role: 'support', area_adjustments: {}, action_grants: [] }
			})
		);
		expect(lines[0]).toBe('Role: Sales → Support');
		expect(lines).toContain('Support inbox: off → can change');
	});

	it('words the D1 events', () => {
		expect(
			describeTeamHistoryEntry(
				entry({ event_type: 'team_member_invited', after_state: { role: 'delivery' } })
			)
		).toEqual(['Invited as Delivery']);
		expect(describeTeamHistoryEntry(entry({ event_type: 'team_member_removed' }))).toEqual([
			'Removed from the team and signed out'
		]);
	});

	it('copes with a damaged record', () => {
		expect(describeTeamHistoryEntry(entry({ before_state: 'x', after_state: null }))).toEqual([
			'Access changed'
		]);
	});
});
