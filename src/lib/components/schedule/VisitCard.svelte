<script lang="ts">
	import ScheduleItemCard from '$lib/components/schedule/ScheduleItemCard.svelte';
	import { cardState, visitDerivedStatus } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS } from '$lib/schedule/statuses';
	import {
		visitAssignmentLabel,
		visitClientLabel,
		visitPlaceLabel,
		visitStartLabel,
		visitTimeLabel,
		visitWorkLabel
	} from '$lib/schedule/labels';
	import type { CardDensity } from '$lib/schedule/layout';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';

	// One visit, drawn at whatever size the calendar could give it. The look -- colour for where the work
	// stands, the people, the place -- is the shared ScheduleItemCard; this card only says what a visit is
	// called, so the Week grid, the Day board and the Month cell describe a visit identically.

	let {
		visit,
		density,
		today,
		nowMinutes = null,
		employeesById,
		selected = false,
		showAssignment = true,
		sharedWith = [],
		badge = null,
		keyboardMovable = false,
		onselect,
		onpickup,
		onkeydown,
		onblur
	}: {
		visit: ScheduleVisit;
		density: CardDensity;
		today: string;
		/** Minutes past midnight in the contractor's timezone; a visit under way today wears "In progress". */
		nowMinutes?: number | null;
		employeesById: Map<string, TeamMember>;
		selected?: boolean;
		/** The card was pressed: the calendar decides whether that becomes a drag or stays a click. */
		onpickup?: (event: PointerEvent) => void;
		/** False where the surface itself already says who is going, as the Day board's employee row does.
		 * The card never repeats identity the row has already given. */
		showAssignment?: boolean;
		/** On a person's row, the names of the other people the visit is shared with. A wide card says
		 *  `Shared with Sofia Chen`; a narrow one, with no room for words, shows how many are on it. */
		sharedWith?: string[];
		/** The one-line Anytime form can carry a small number before the name. */
		badge?: number | null;
		/** Whether the arrow keys can reschedule this card from the keyboard. Only true for a permitted,
		 *  uncompleted visit -- the same gate a pointer drag uses. Adds the hint to the card's own label. */
		keyboardMovable?: boolean;
		/** The element is handed back so the page can anchor the preview to this exact card. */
		onselect: (visit: ScheduleVisit, element: HTMLElement) => void;
		/** Arrow keys nudge a pending reschedule; Enter or Space confirms it, Escape cancels it. */
		onkeydown?: (event: KeyboardEvent) => void;
		/** Focus left the card while a keyboard reschedule was pending, so the calendar can drop it rather
		 *  than leave a stranded preview behind. */
		onblur?: (event: FocusEvent) => void;
	} = $props();

	const state = $derived(cardState(visit, today, nowMinutes));
	const status = $derived(visitDerivedStatus(visit, today));
	const sharedLabel = $derived(
		sharedWith.length === 0
			? null
			: density === 'standard'
				? `Shared with ${sharedWith.join(', ')}`
				: String(sharedWith.length + 1)
	);
	const people = $derived(
		visit.assignee_ids.map((id) => employeesById.get(id)?.full_name ?? 'One employee')
	);

	// The whole card in words, for a screen reader and for the smallest form, where most of it is not drawn.
	const summary = $derived(
		[
			visitTimeLabel(visit),
			visitClientLabel(visit),
			visitWorkLabel(visit),
			visitAssignmentLabel(visit, employeesById),
			status ? VISIT_STATUS_LABELS[status] : null,
			state === 'in-progress' ? 'In progress' : null,
			keyboardMovable ? 'Arrow keys reschedule, Enter confirms, Escape cancels' : null
		]
			.filter(Boolean)
			.join(', ')
	);
</script>

<ScheduleItemCard
	{density}
	{state}
	time={visitTimeLabel(visit)}
	startTime={visitStartLabel(visit)}
	client={visitClientLabel(visit)}
	work={visitWorkLabel(visit)}
	place={visitPlaceLabel(visit)}
	{people}
	showPeople={showAssignment}
	{sharedLabel}
	{badge}
	inlineChip={!showAssignment}
	{selected}
	{summary}
	onclick={(event) => onselect(visit, event.currentTarget)}
	onpointerdown={onpickup}
	{onkeydown}
	{onblur}
/>
