<script lang="ts">
	import CalendarMonthGrid from '$lib/components/calendar/CalendarMonthGrid.svelte';
	import VisitCard from '$lib/components/schedule/VisitCard.svelte';
	import AssessmentCard from '$lib/components/schedule/AssessmentCard.svelte';
	import EventCard from '$lib/components/schedule/EventCard.svelte';
	import TaskCard from '$lib/components/schedule/TaskCard.svelte';
	import { bucketVisitsByDay, orderDayVisits } from '$lib/schedule/grouping';
	import { eachDayInWindow, type ScheduleWindow } from '$lib/schedule/filters';
	import { draftAnytime, type NewVisitDraft } from '$lib/schedule/drag';
	import type { AssessmentItem, EventItem, ScheduleItem } from '$lib/schedule/items';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';

	// The month, as six weeks of seven dates. The frame is the shared CalendarMonthGrid; this draws the
	// contractor's cards into it.

	let {
		window: activeWindow,
		anchorDate,
		items,
		today,
		employeesById,
		selectedItemId,
		canCreate = false,
		onselect,
		onselectassessment,
		onselectevent,
		oncreate
	}: {
		window: ScheduleWindow;
		/** The date the calendar is anchored to. It decides which month owns the grid, so the padding days
		 * either side can be dimmed without being hidden. */
		anchorDate: string;
		/** Already filtered by the page. Every one of these is drawn or counted -- visits and assessments. */
		items: ScheduleItem[];
		today: string;
		employeesById: Map<string, TeamMember>;
		selectedItemId: string | null;
		/** Whether this reader may start a Job from empty space. A month cell only becomes clickable with it. */
		canCreate?: boolean;
		onselect: (visit: ScheduleVisit, element: HTMLElement) => void;
		/** An assessment card was selected. The page opens its Request-owned preview. */
		onselectassessment: (assessment: AssessmentItem, element: HTMLElement) => void;
		/** An event card was selected. The page opens its Schedule-owned preview. */
		onselectevent: (event: EventItem, element: HTMLElement) => void;
		/** A click on empty cell space books a date-only visit for that date -- the same date-only visit the
		 *  Anytime lane creates. The page opens the create form; nothing is written until it is saved. */
		oncreate?: (draft: NewVisitDraft) => void;
	} = $props();

	const days = $derived(eachDayInWindow(activeWindow));
	const itemsByDay = $derived.by(() => {
		const byDay = bucketVisitsByDay(items);
		return new Map([...byDay].map(([day, dayItems]) => [day, orderDayVisits(dayItems)]));
	});
</script>

<CalendarMonthGrid
	{days}
	{anchorDate}
	{itemsByDay}
	{today}
	bookable={canCreate}
	oncellclick={canCreate ? (day) => oncreate?.(draftAnytime(day)) : undefined}
>
	{#snippet card(item, density, relay)}
		{#if item.kind === 'visit'}
			<VisitCard
				visit={item}
				{density}
				{today}
				{employeesById}
				selected={item.id === selectedItemId}
				onselect={relay(onselect)}
			/>
		{:else if item.kind === 'assessment'}
			<AssessmentCard
				assessment={item}
				{density}
				{today}
				{employeesById}
				selected={item.id === selectedItemId}
				onselect={relay(onselectassessment)}
			/>
		{:else if item.kind === 'task'}
			<TaskCard task={item} {density} {today} {employeesById} />
		{:else}
			<EventCard
				event={item}
				{density}
				selected={item.id === selectedItemId}
				onselect={relay(onselectevent)}
			/>
		{/if}
	{/snippet}
</CalendarMonthGrid>
