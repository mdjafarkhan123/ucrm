import {
	ALL_STAGE_LABELS,
	BOARD_SECTIONS,
	SECTION_STAGES,
	stageSection,
	type AnyBoardStage,
	type BoardSection,
	type CustomStage,
	type OpportunityStage
} from './stages';
import { dragActionFor } from './transitions';

// Where a card can be asked to go without dragging. The Move button on a card and a drop on a column
// both end in one of these, so the two can never disagree about what a move does.
export type MoveTarget =
	// A real stage, reached by performing that stage's own action.
	| { kind: 'stage'; stage: AnyBoardStage }
	// A custom follow-up stage. Nothing about the Request or Quote changes.
	| { kind: 'custom'; customStageId: string }
	// Out of a custom stage, back to the real stage the card never stopped being in.
	| { kind: 'home' };

// The record a blocked move sends the person to, when that is where the genuine next step lives.
export type MoveNextStep = { label: string; record: 'request' | 'quote' };

// One row of a card's Move menu. Every stage on the board is listed for every card: the one it is in,
// the ones it can go to, and the ones it cannot — each of those with the exact reason, never a silent gap.
export type MoveDestination = {
	key: string;
	label: string;
	section: BoardSection;
	// An on-hold stage: the board asks for a Task with a future date on the way in.
	onHold: boolean;
} & (
	| { state: 'current' }
	| { state: 'available'; target: MoveTarget }
	| { state: 'blocked'; reason: string; nextStep?: MoveNextStep }
);

type MovableCard = { stage: OpportunityStage; custom_stage_id: string | null };

const OPEN_REQUEST: MoveNextStep = { label: 'Open request', record: 'request' };
const OPEN_QUOTE: MoveNextStep = { label: 'Open quote', record: 'quote' };

// Why a real stage cannot be reached from another, and what to do instead. Only asked about pairs the
// transition table refuses; the wording names the real fact in the way, the way a person would say it.
function blockedStage(
	from: AnyBoardStage,
	to: AnyBoardStage
): { reason: string; nextStep?: MoveNextStep } {
	if (stageSection(from) === 'quote') {
		if (stageSection(to) === 'request') {
			return {
				reason: 'This request has already become a quote, and that cannot be reversed.'
			};
		}
		if (to === 'quote_changes_requested') {
			return {
				reason:
					from === 'quote_draft'
						? 'Only the customer can ask for changes, after the quote has been sent to them.'
						: 'Only the customer can ask for changes. The card moves here by itself when they do.'
			};
		}
		if (to === 'quote_draft') {
			return {
				reason:
					from === 'quote_awaiting_response'
						? 'This quote has already been sent. To change it, open the quote and start a new version.'
						: 'To make the changes the customer asked for, open the quote and start a new version.',
				nextStep: OPEN_QUOTE
			};
		}
		// Changes requested -> Awaiting response.
		return {
			reason:
				'Send the updated quote from the quote itself. The card moves back to Awaiting response once it has gone out.',
			nextStep: OPEN_QUOTE
		};
	}

	if (to === 'quote_changes_requested') {
		return {
			reason: 'Only the customer can ask for changes, after a quote has been sent to them.'
		};
	}
	if (to === 'quote_awaiting_response') {
		return {
			reason: 'There is no quote to send yet. Move this card to Draft first to create the quote.'
		};
	}
	if (to === 'quote_draft') {
		// Only a booked, unfinished assessment stops a request becoming a quote.
		return {
			reason:
				'The assessment is booked but not finished. Move this card to Assessment completed first, then to Draft.'
		};
	}
	if (to === 'assessment_completed') {
		return {
			reason:
				'There is no assessment to complete yet. Move this card to Assessment unscheduled or Assessment scheduled first.'
		};
	}
	if (to === 'new_request') {
		return {
			reason:
				'This request already has an assessment. To bring it back to New requests, remove the assessment on the request.',
			nextStep: OPEN_REQUEST
		};
	}
	if (from === 'assessment_completed') {
		return {
			reason:
				'The assessment is already marked complete. To reopen it, untick Complete on the request.',
			nextStep: OPEN_REQUEST
		};
	}
	// Assessment scheduled -> Assessment unscheduled.
	return {
		reason: 'The assessment is already booked. To unschedule it, clear its date on the request.',
		nextStep: OPEN_REQUEST
	};
}

function blockedSection(cardSection: BoardSection): string {
	return cardSection === 'request'
		? 'This is still a request, so it can only go into a Requests stage. It can go here once it becomes a quote.'
		: 'This is a quote, so it can only go into a Quotes stage.';
}

// Every destination for one card, in the board's own left-to-right order: each section's real stages,
// each followed by the custom stages saved after it. Empty for a card that has left the board.
export function moveDestinations(
	card: MovableCard,
	customStages: readonly CustomStage[]
): MoveDestination[] {
	const cardSection = stageSection(card.stage);
	if (cardSection === null) return [];
	const from = card.stage as AnyBoardStage;
	const destinations: MoveDestination[] = [];

	for (const section of BOARD_SECTIONS) {
		for (const stage of SECTION_STAGES[section]) {
			const base = { key: stage, label: ALL_STAGE_LABELS[stage], section, onHold: false };
			if (stage === from) {
				destinations.push(
					card.custom_stage_id === null
						? { ...base, state: 'current' }
						: { ...base, state: 'available', target: { kind: 'home' } }
				);
			} else if (dragActionFor(from, stage)) {
				destinations.push({ ...base, state: 'available', target: { kind: 'stage', stage } });
			} else {
				destinations.push({ ...base, state: 'blocked', ...blockedStage(from, stage) });
			}

			for (const custom of customStages) {
				if (custom.section !== section || custom.after_stage !== stage) continue;
				const customBase = {
					key: `custom-${custom.id}`,
					label: custom.name,
					section,
					onHold: custom.requires_future_task
				};
				if (custom.id === card.custom_stage_id) {
					destinations.push({ ...customBase, state: 'current' });
				} else if (section === cardSection) {
					destinations.push({
						...customBase,
						state: 'available',
						target: { kind: 'custom', customStageId: custom.id }
					});
				} else {
					destinations.push({
						...customBase,
						state: 'blocked',
						reason: blockedSection(cardSection)
					});
				}
			}
		}
	}

	return destinations;
}
