import { describe, expect, it } from 'vitest';
import { moveDestinations, type MoveDestination } from './moves';
import { allowedDragTargets } from './transitions';
import { BOARD_STAGES, QUOTE_BOARD_STAGES, type AnyBoardStage, type CustomStage } from './stages';

const custom = (
	id: string,
	section: CustomStage['section'],
	after_stage: AnyBoardStage,
	requires_future_task = false
): CustomStage => ({
	id,
	section,
	name: `Stage ${id}`,
	after_stage,
	requires_future_task,
	inactivity_days: 3
});

const stages = [
	custom('r1', 'request', 'new_request'),
	custom('r2', 'request', 'assessment_completed', true),
	custom('q1', 'quote', 'quote_awaiting_response')
];

const find = (list: MoveDestination[], key: string) => list.find((item) => item.key === key)!;

describe('moveDestinations', () => {
	it('lists every stage on the board for every card, in board order', () => {
		const list = moveDestinations({ stage: 'new_request', custom_stage_id: null }, stages);

		expect(list.map((item) => item.key)).toEqual([
			'new_request',
			'custom-r1',
			'assessment_unscheduled',
			'assessment_scheduled',
			'assessment_completed',
			'custom-r2',
			'quote_draft',
			'quote_awaiting_response',
			'custom-q1',
			'quote_changes_requested'
		]);
	});

	it('offers exactly the real stages a drag allows, for every stage', () => {
		for (const from of [...BOARD_STAGES, ...QUOTE_BOARD_STAGES]) {
			const available = moveDestinations({ stage: from, custom_stage_id: null }, [])
				.filter((item) => item.state === 'available')
				.map((item) => item.key);

			expect(available, from).toEqual(allowedDragTargets(from));
		}
	});

	it('marks the stage the card is in, and gives every other refused stage a reason', () => {
		for (const from of [...BOARD_STAGES, ...QUOTE_BOARD_STAGES]) {
			const list = moveDestinations({ stage: from, custom_stage_id: null }, stages);

			expect(list.filter((item) => item.state === 'current').map((item) => item.key)).toEqual([
				from
			]);
			for (const item of list) {
				if (item.state === 'blocked') expect(item.reason.length, item.key).toBeGreaterThan(20);
			}
		}
	});

	it('takes a new request to Assessment scheduled, and explains why not Assessment completed', () => {
		const list = moveDestinations({ stage: 'new_request', custom_stage_id: null }, stages);

		expect(find(list, 'assessment_scheduled')).toMatchObject({
			state: 'available',
			target: { kind: 'stage', stage: 'assessment_scheduled' }
		});
		expect(find(list, 'assessment_completed')).toMatchObject({
			state: 'blocked',
			reason: expect.stringContaining('no assessment to complete yet')
		});
	});

	it('points a backward move at the record where it can really be done', () => {
		const booked = moveDestinations({ stage: 'assessment_scheduled', custom_stage_id: null }, []);
		expect(find(booked, 'assessment_unscheduled')).toMatchObject({
			state: 'blocked',
			nextStep: { label: 'Open request', record: 'request' }
		});
		expect(find(booked, 'quote_draft')).toMatchObject({
			state: 'blocked',
			reason: expect.stringContaining('Assessment completed first')
		});

		const sent = moveDestinations({ stage: 'quote_awaiting_response', custom_stage_id: null }, []);
		expect(find(sent, 'quote_draft')).toMatchObject({
			state: 'blocked',
			nextStep: { label: 'Open quote', record: 'quote' }
		});
		expect(find(sent, 'quote_changes_requested')).toMatchObject({
			state: 'blocked',
			reason: expect.stringContaining('Only the customer')
		});
		expect(find(sent, 'new_request')).toMatchObject({
			state: 'blocked',
			reason: expect.stringContaining('already become a quote')
		});
	});

	it('offers custom stages on the card’s own side only, and flags an on-hold one', () => {
		const list = moveDestinations(
			{ stage: 'assessment_unscheduled', custom_stage_id: null },
			stages
		);

		expect(find(list, 'custom-r1')).toMatchObject({
			state: 'available',
			target: { kind: 'custom', customStageId: 'r1' },
			onHold: false
		});
		expect(find(list, 'custom-r2')).toMatchObject({ state: 'available', onHold: true });
		expect(find(list, 'custom-q1')).toMatchObject({
			state: 'blocked',
			reason: expect.stringContaining('once it becomes a quote')
		});
	});

	it('lets a card in a custom stage go home, and still take real actions', () => {
		const list = moveDestinations({ stage: 'new_request', custom_stage_id: 'r1' }, stages);

		expect(find(list, 'custom-r1').state).toBe('current');
		expect(find(list, 'new_request')).toMatchObject({
			state: 'available',
			target: { kind: 'home' }
		});
		expect(find(list, 'assessment_unscheduled').state).toBe('available');
	});

	it('has nothing to offer a card that has left the board', () => {
		expect(moveDestinations({ stage: 'request_closed', custom_stage_id: null }, stages)).toEqual(
			[]
		);
	});
});
