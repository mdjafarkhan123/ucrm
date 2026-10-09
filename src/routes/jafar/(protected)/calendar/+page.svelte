<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { MediaQuery } from 'svelte/reactivity';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import phoneIcon from '@tabler/icons/outline/phone-plus.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Popover from '$lib/components/ui/Popover.svelte';
	import { anchorAtPoint, type PopoverAnchor } from '$lib/components/ui/popover-anchor';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import CalendarBar from '$lib/components/calendar/CalendarBar.svelte';
	import CalendarWeekGrid, {
		type WeekGridGhost
	} from '$lib/components/calendar/CalendarWeekGrid.svelte';
	import CalendarMonthGrid from '$lib/components/calendar/CalendarMonthGrid.svelte';
	import SalesCalendarCard from '$lib/components/jafar/calendar/SalesCalendarCard.svelte';
	import SalesCalendarList from '$lib/components/jafar/calendar/SalesCalendarList.svelte';
	import CallDialog from '$lib/components/jafar/calendar/CallDialog.svelte';
	import CallOutcomeDialog from '$lib/components/jafar/calendar/CallOutcomeDialog.svelte';
	import BusyDialog from '$lib/components/jafar/calendar/BusyDialog.svelte';
	import {
		eachDayInWindow,
		reanchorScheduleDate,
		scheduleWindow,
		shiftScheduleDate
	} from '$lib/schedule/filters';
	import { SCHEDULE_VIEWS, type ScheduleView } from '$lib/schedule/statuses';
	import { cardDensity, layoutTimedVisits, type TimedBlock } from '$lib/schedule/layout';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { snapMinutes } from '$lib/schedule/drag';
	import { startPointerDrag } from '$lib/schedule/pointer-drag';
	import {
		browserTimeZone,
		calendarPreferencesKey,
		calendarWindowKey,
		fetchCalendarPreferences,
		fetchCalendarWindow,
		minutesWords,
		orderCalendarDay,
		placeCalendarItems,
		zonedPlace,
		type CalendarEntry,
		type CalendarItem
	} from '$lib/jafar/calendar';

	// Jafar business management C2: the Business Management calendar (plan § 6) -- sales calls, Busy blocks and
	// dated next actions, never contractor jobs. Day and Week draw the shared time grid, Month the shared month,
	// and a phone gets one readable list of the window instead of columns too narrow to tap. The date and view
	// live in the URL, as on the contractor Schedule, so Back, refresh and a shared link all keep them.

	const queryClient = useQueryClient();
	const phone = new MediaQuery('max-width: 639px');

	const VIEWS = [
		{ value: 'day' as const, label: 'Day' },
		{ value: 'week' as const, label: 'Week' },
		{ value: 'month' as const, label: 'Month' }
	];

	// Jafar's own time zone once saved; until then the browser's, which is saved with his first booking.
	const preferencesQuery = createQuery(() => ({
		queryKey: calendarPreferencesKey,
		queryFn: fetchCalendarPreferences,
		staleTime: 5 * 60_000
	}));
	const zone = $derived(preferencesQuery.data?.time_zone ?? browserTimeZone());
	const defaults = $derived(
		preferencesQuery.data?.reminder_defaults ?? { call: [], follow_up_day: [], follow_up_timed: [] }
	);

	// The clock moves the now line and turns ended calls into "Outcome?" without a reload.
	let clock = $state(new Date());
	$effect(() => {
		const tick = setInterval(() => (clock = new Date()), 60_000);
		return () => clearInterval(tick);
	});
	const now = $derived(zonedPlace(clock.toISOString(), zone));
	const today = $derived(now.day);

	const view = $derived.by((): ScheduleView => {
		const param = page.url.searchParams.get('view');
		return SCHEDULE_VIEWS.includes(param as ScheduleView) ? (param as ScheduleView) : 'week';
	});
	const date = $derived.by(() => {
		const param = page.url.searchParams.get('date');
		return param && /^\d{4}-\d{2}-\d{2}$/.test(param) && !Number.isNaN(Date.parse(param))
			? param
			: today;
	});
	const activeWindow = $derived(scheduleWindow(date, view));
	const days = $derived(eachDayInWindow(activeWindow));

	// The window waits for the time zone, so it is read once in the right one rather than twice.
	const windowQuery = createQuery(() => ({
		queryKey: calendarWindowKey(activeWindow.from, activeWindow.to, zone),
		queryFn: () => fetchCalendarWindow(activeWindow.from, activeWindow.to, zone),
		enabled: !preferencesQuery.isPending,
		staleTime: 30_000,
		placeholderData: (previous) => previous
	}));

	// The window either side is read once this one has arrived, so stepping feels instant.
	$effect(() => {
		if (!windowQuery.isSuccess || windowQuery.isPlaceholderData) return;
		for (const direction of [-1, 1] as const) {
			const next = scheduleWindow(shiftScheduleDate(date, view, direction), view);
			void queryClient.prefetchQuery({
				queryKey: calendarWindowKey(next.from, next.to, zone),
				queryFn: () => fetchCalendarWindow(next.from, next.to, zone),
				staleTime: 30_000
			});
		}
	});

	const placed = $derived(
		windowQuery.data ? placeCalendarItems(windowQuery.data, zone) : new Map()
	);

	function navigate(next: { view: ScheduleView; date: string }) {
		const query = new URLSearchParams();
		if (next.view !== 'week') query.set('view', next.view);
		if (next.date !== today) query.set('date', next.date);
		const route: string = resolve('/jafar/(protected)/calendar');
		const search = query.toString();
		void goto(search ? `${route}?${search}` : route, { keepFocus: true, noScroll: true });
	}

	const rangeLabel = $derived.by(() => {
		if (view === 'month') return formatCalendarDay(date, { month: 'long', year: 'numeric' });
		if (view === 'day')
			return formatCalendarDay(activeWindow.from, {
				weekday: 'long',
				month: 'long',
				day: 'numeric',
				year: 'numeric'
			});
		const sameYear = activeWindow.from.slice(0, 4) === activeWindow.to.slice(0, 4);
		const start = formatCalendarDay(activeWindow.from, {
			month: 'short',
			day: 'numeric',
			...(sameYear ? {} : { year: 'numeric' })
		});
		const end = formatCalendarDay(activeWindow.to, {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
		return `${start} – ${end}`;
	});

	// --- Day and Week ----------------------------------------------------------------------------------

	const hourHeight = $derived(view === 'day' ? 64 : 48);
	const columns = $derived(
		(view === 'day' ? [activeWindow.from] : days).map((day) => {
			const found = placed.get(day);
			return {
				day,
				anytime: found?.anytime ?? [],
				blocks: layoutTimedVisits<CalendarItem>(found?.timed ?? []),
				count: (found?.anytime.length ?? 0) + (found?.timed.length ?? 0),
				working: []
			};
		})
	);
	// Opens just before the first thing on screen, or at 8am on an empty window.
	const openingMinute = $derived.by(() => {
		const starts = columns.flatMap((column) => column.blocks.map((block) => block.start));
		return Math.max(0, (starts.length ? Math.min(...starts, 8 * 60) : 8 * 60) - 30);
	});

	/** The real times of a call or Busy block, even where the grid cut it at midnight. */
	function entryTime(entry: CalendarEntry, short: boolean) {
		const start = minutesWords(zonedPlace(entry.starts_at, zone).minutes);
		return short ? start : `${start} – ${minutesWords(zonedPlace(entry.ends_at, zone).minutes)}`;
	}

	function itemTime(item: CalendarItem, short = false) {
		if (item.kind !== 'follow_up') return entryTime(item.entry, short);
		return item.followUp.due_at ? minutesWords(zonedPlace(item.followUp.due_at, zone).minutes) : '';
	}

	function passed(item: CalendarItem) {
		return item.kind === 'call' && Date.parse(item.entry.ends_at) <= clock.getTime();
	}

	function blockDensity(block: TimedBlock<CalendarItem>) {
		return cardDensity(((block.end - block.start) / 60) * hourHeight, block.columns);
	}

	// Pressing empty time and dragging draws the new item's length; a plain click gives it 30 minutes. Either
	// way, a small menu then asks whether it is a call or Busy time.
	let columnEls = $state<(HTMLElement | undefined)[]>([]);
	let drawing = $state<{ day: string; start: number; end: number } | null>(null);
	let slot = $state<{ day: string; start: number; end: number; anchor: PopoverAnchor } | null>(
		null
	);

	const ghosts = $derived<WeekGridGhost[]>(
		drawing && drawing.end !== drawing.start
			? [
					{
						day: drawing.day,
						start: Math.min(drawing.start, drawing.end),
						end: Math.max(drawing.start, drawing.end),
						label: `${minutesWords(Math.min(drawing.start, drawing.end))} – ${minutesWords(Math.max(drawing.start, drawing.end))}`,
						tone: 'create'
					}
				]
			: []
	);

	function minutesAt(event: PointerEvent, index: number) {
		const box = columnEls[index]?.getBoundingClientRect();
		return box ? snapMinutes((event.clientY - box.top) / (hourHeight / 60)) : 0;
	}

	function beginSlot(event: PointerEvent, index: number) {
		if ((event.target as HTMLElement).closest('.calendar-week__block')) return;
		const day = columns[index].day;
		const start = Math.min(minutesAt(event, index), 24 * 60 - 30);
		startPointerDrag(event, {
			onStart: () => (drawing = { day, start, end: start }),
			onMove: (moved) => drawing && (drawing = { ...drawing, end: minutesAt(moved, index) }),
			onDrop: (dropped) => {
				const end = minutesAt(dropped, index);
				drawing = null;
				const from = Math.min(start, end);
				const to = Math.max(start, end);
				openSlot(day, from, to - from < 15 ? from + 30 : to, dropped);
			},
			onCancel: () => {
				const wasDrawing = drawing !== null;
				drawing = null;
				if (!wasDrawing) openSlot(day, start, start + 30, event);
			}
		});
	}

	function openSlot(day: string, start: number, end: number, event: PointerEvent) {
		slot = { day, start, end, anchor: anchorAtPoint(event.clientX, event.clientY) };
	}

	// --- Dialogs ---------------------------------------------------------------------------------------

	type Open =
		| {
				kind: 'call';
				entryId: string | null;
				seed: { day: string; start: number; end: number } | null;
		  }
		| {
				kind: 'busy';
				entry: CalendarEntry | null;
				seed: { day: string; start: number; end: number } | null;
		  }
		| { kind: 'outcome'; entryId: string; cancelling: boolean };
	let open = $state<Open | null>(null);

	function choose(kind: 'call' | 'busy') {
		const seed = slot ? { day: slot.day, start: slot.start, end: slot.end } : null;
		slot = null;
		open = kind === 'call' ? { kind, entryId: null, seed } : { kind, entry: null, seed };
	}

	function select(item: CalendarItem) {
		if (item.kind === 'follow_up') {
			void goto(resolve('/jafar/(protected)/leads/[id]', { id: item.followUp.id }));
			return;
		}
		if (item.kind === 'busy') {
			open = { kind: 'busy', entry: item.entry, seed: null };
			return;
		}
		open = { kind: 'call', entryId: item.entry.id, seed: null };
	}

	function askOutcome(entryId: string) {
		const entry = windowQuery.data?.entries.find((candidate) => candidate.id === entryId);
		const ended = entry ? Date.parse(entry.ends_at) <= Date.now() : true;
		open = { kind: 'outcome', entryId, cancelling: !ended };
	}

	// A month cell books a call that day at 10am.
	function bookOnDay(day: string) {
		open = { kind: 'call', entryId: null, seed: { day, start: 10 * 60, end: 10 * 60 + 30 } };
	}

	const monthItems = $derived(new Map(days.map((day) => [day, orderCalendarDay(placed.get(day))])));
	const listDays = $derived(
		(view === 'day' ? [activeWindow.from] : days)
			.filter((day) => view !== 'month' || day.slice(0, 7) === date.slice(0, 7))
			.map((day) => ({ day, items: orderCalendarDay(placed.get(day)) }))
	);
</script>

<svelte:head><title>Calendar · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="sales-calendar">
	<header class="sales-calendar__header">
		<div>
			<p class="sales-calendar__eyebrow">Business management</p>
			<h1>Calendar</h1>
			<p class="sales-calendar__description">
				Your sales calls, follow-ups and busy time. Times are shown in {zone.replace(/_/g, ' ')}.
			</p>
		</div>
		<div class="sales-calendar__actions">
			<Button
				variant="secondary"
				onclick={() => (open = { kind: 'busy', entry: null, seed: null })}
			>
				<span class="sales-calendar__icon" aria-hidden="true">{@html lockIcon}</span>Add busy time
			</Button>
			<Button onclick={() => (open = { kind: 'call', entryId: null, seed: null })}>
				<span class="sales-calendar__icon" aria-hidden="true">{@html phoneIcon}</span>Book a call
			</Button>
		</div>
	</header>

	<CalendarBar
		{view}
		views={VIEWS}
		{rangeLabel}
		onstep={(direction) => navigate({ view, date: shiftScheduleDate(date, view, direction) })}
		ontoday={() => navigate({ view, date: today })}
		onview={(next) => navigate({ view: next, date: reanchorScheduleDate(date, view, next) })}
	/>

	{#if windowQuery.isError && !windowQuery.data}
		<ErrorState
			title="The calendar could not load"
			description="Your dates are still here. Try again."
			retry={() => void windowQuery.refetch()}
		/>
	{:else if !windowQuery.data}
		<LoadingSkeleton variant="card" rows={4} label="Loading the calendar" />
	{:else}
		{#if windowQuery.data.truncated}
			<p class="sales-calendar__notice" role="status">
				This {view} holds more than the calendar can draw at once. Switch to Week or Day to see everything.
			</p>
		{/if}

		{#if phone.current}
			<SalesCalendarList
				days={listDays}
				{today}
				{itemTime}
				{passed}
				onselect={select}
				onbook={bookOnDay}
			/>
		{:else if view === 'month'}
			<CalendarMonthGrid
				{days}
				anchorDate={date}
				itemsByDay={monthItems}
				{today}
				bookable
				oncellclick={bookOnDay}
			>
				{#snippet card(item, density, relay)}
					<SalesCalendarCard
						{item}
						density={density === 'micro' ? 'micro' : 'compact'}
						time={itemTime(item, true)}
						passed={passed(item)}
						onselect={relay((chosen: CalendarItem) => select(chosen))}
					/>
				{/snippet}
			</CalendarMonthGrid>
		{:else}
			<CalendarWeekGrid
				{columns}
				{today}
				nowMinutes={columns.some((column) => column.day === today) ? now.minutes : null}
				{hourHeight}
				{openingMinute}
				{ghosts}
				anytimeLabel="Due"
				bookable
				bind:columnEls
				oncolumnpointerdown={beginSlot}
			>
				{#snippet anytimeItem(item)}
					<SalesCalendarCard {item} density="micro" time="" onselect={select} />
				{/snippet}
				{#snippet block(placedBlock)}
					{@const density = blockDensity(placedBlock)}
					<SalesCalendarCard
						item={placedBlock.item}
						{density}
						time={itemTime(placedBlock.item, density === 'micro')}
						passed={passed(placedBlock.item)}
						onselect={select}
					/>
				{/snippet}
			</CalendarWeekGrid>
		{/if}
	{/if}
</main>

<Popover
	open={slot !== null}
	anchor={slot?.anchor ?? null}
	title="Add"
	onClose={() => (slot = null)}
>
	{#if slot}
		<p class="sales-calendar__slot">
			{formatCalendarDay(slot.day, { weekday: 'short', month: 'short', day: 'numeric' })},
			{minutesWords(slot.start)} – {minutesWords(slot.end)}
		</p>
		<div class="sales-calendar__slot-actions">
			<Button size="small" onclick={() => choose('call')}>
				<span class="sales-calendar__icon" aria-hidden="true">{@html phoneIcon}</span>Sales call
			</Button>
			<Button size="small" variant="secondary" onclick={() => choose('busy')}>
				<span class="sales-calendar__icon" aria-hidden="true">{@html lockIcon}</span>Busy
			</Button>
		</div>
	{/if}
</Popover>

{#if open?.kind === 'call'}
	<CallDialog
		entryId={open.entryId}
		seed={open.seed}
		{zone}
		{defaults}
		onClose={() => (open = null)}
		onOutcome={askOutcome}
	/>
{:else if open?.kind === 'busy'}
	<BusyDialog entry={open.entry} seed={open.seed} {zone} onClose={() => (open = null)} />
{:else if open?.kind === 'outcome'}
	<CallOutcomeDialog
		entryId={open.entryId}
		{zone}
		cancelling={open.cancelling}
		onClose={() => (open = null)}
	/>
{/if}

<style lang="scss">
	.sales-calendar {
		min-width: 0;
		display: grid;
		gap: var(--space-base);
	}

	.sales-calendar h1,
	.sales-calendar p {
		margin: 0;
	}

	.sales-calendar h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.sales-calendar__header {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.sales-calendar__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.sales-calendar__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.sales-calendar__actions,
	.sales-calendar__slot-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.sales-calendar__icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.sales-calendar__notice {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		background-color: var(--color-warning--surface);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}

	.sales-calendar__slot {
		margin-bottom: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	@media (max-width: 639px) {
		.sales-calendar__actions {
			width: 100%;

			:global(> *) {
				flex: 1;
			}
		}
	}
</style>
