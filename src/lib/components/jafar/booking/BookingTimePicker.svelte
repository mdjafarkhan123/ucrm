<script lang="ts">
	import { onMount } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import {
		CalendarDate,
		endOfMonth,
		parseDate,
		startOfMonth,
		toZoned,
		today
	} from '@internationalized/date';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import BookingMonth from '$lib/components/jafar/booking/BookingMonth.svelte';
	import { dateWords, dayKey, timeWords, zoneCity } from '$lib/jafar/booking';

	// Jafar business management E1/E2: the public month-then-time picker, Calendly's way -- a month with the open
	// days marked, that day's times, in the visitor's own zone (which they can change). The booking page and the
	// visitor's change page share it; each says where its open times come from.

	type Props = {
		/** Where open times come from; answers `?from=&to=` with a list of start instants. */
		slotsUrl: string;
		/** The cache key's start; the month's range is added to it. */
		queryKey: readonly unknown[];
		/** The open times the page arrived with, up to `to`. */
		firstWindow: { to: string; starts: string[] };
		horizonDays: number;
		/** The visitor's zone; the browser's until they change it. */
		zone?: string;
		locale?: string;
		/** The booking's current start, shown as such and not offered. */
		current?: string;
		onchoose: (start: string) => void;
	};

	let {
		slotsUrl,
		queryKey,
		firstWindow,
		horizonDays,
		zone = $bindable(''),
		locale,
		current,
		onchoose
	}: Props = $props();

	const queryClient = useQueryClient();

	let changingZone = $state(false);
	let month = $state<CalendarDate>();
	let picked = $state<CalendarDate>();
	let firstStarts = $state<string[]>([]);
	let firstTo = $state('');

	onMount(() => {
		zone ||= Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
		firstStarts = firstWindow.starts;
		firstTo = firstWindow.to;
		const first = current ?? firstStarts[0];
		month = first ? parseDate(dayKey(first, zone)) : today(zone);
		if (current) picked = parseDate(dayKey(current, zone));
	});

	function monthRange(shown: CalendarDate, inZone: string) {
		return {
			from: toZoned(startOfMonth(shown), inZone).toDate().toISOString(),
			to: toZoned(endOfMonth(shown).add({ days: 1 }), inZone)
				.toDate()
				.toISOString()
		};
	}

	async function fetchStarts(from: string, to: string): Promise<string[]> {
		const params = new URLSearchParams({ from, to });
		const response = await fetch(`${slotsUrl}?${params}`);
		const result = await response.json();
		if (!response.ok) throw new Error(result.error ?? 'We could not load the open times.');
		return result;
	}

	// Keyed by the month's first day, so a new date object for the same month starts no new work.
	const monthStart = $derived(month ? startOfMonth(month).toString() : '');
	const range = $derived(monthStart && zone ? monthRange(parseDate(monthStart), zone) : null);
	// A month that ends inside the window the page arrived with needs no request (times before now are never open).
	const covered = $derived(Boolean(range && firstTo && range.to <= firstTo));
	const monthQuery = createQuery(() => ({
		queryKey: [...queryKey, range?.from, range?.to],
		queryFn: () => fetchStarts(range!.from, range!.to),
		enabled: Boolean(range) && !covered,
		staleTime: 30_000
	}));

	const starts = $derived.by(() => {
		if (!range) return [];
		const inMonth = covered
			? firstStarts.filter((start) => start >= range.from && start < range.to)
			: (monthQuery.data ?? []);
		return inMonth.filter((start) => !current || Date.parse(start) !== Date.parse(current));
	});
	const loadingMonth = $derived(!covered && monthQuery.isPending);

	const byDay = $derived.by(() => {
		const days = new Map<string, string[]>();
		for (const start of starts) {
			const key = dayKey(start, zone);
			const list = days.get(key);
			if (list) list.push(start);
			else days.set(key, [start]);
		}
		return days;
	});
	const openDays = $derived(new Set(byDay.keys()));

	// The day shown: the one the visitor chose while it is still open in this month, else the month's first open day.
	const day = $derived.by(() => {
		if (picked && openDays.has(picked.toString())) return picked;
		const first = [...openDays].sort()[0];
		return first ? parseDate(first) : undefined;
	});
	const dayTimes = $derived(day ? (byDay.get(day.toString()) ?? []) : []);

	const minDay = $derived(zone ? today(zone) : undefined);
	const maxDay = $derived(zone ? today(zone).add({ days: horizonDays }) : undefined);

	/** After a time was taken: show that day again with every list fetched afresh. */
	export async function refresh(onDay?: string) {
		if (onDay) picked = parseDate(dayKey(onDay, zone));
		const now = new Date().toISOString();
		const [fresh] = await Promise.all([
			fetchStarts(now, firstTo).catch(() => null),
			queryClient.invalidateQueries({ queryKey })
		]);
		if (fresh) firstStarts = fresh;
	}
</script>

{#if !zone || !month || !minDay || !maxDay}
	<div class="time-picker time-picker--placeholder" aria-hidden="true">
		<div class="time-picker__skeleton time-picker__skeleton--month"></div>
		<div class="time-picker__skeleton time-picker__skeleton--times"></div>
	</div>
{:else}
	<div class="time-picker">
		<div class="time-picker__month">
			<BookingMonth
				bind:month
				bind:value={() => day, (next) => (picked = next)}
				{openDays}
				minValue={minDay}
				maxValue={maxDay}
				loading={loadingMonth}
			/>
			<div class="time-picker__zone">
				{#if changingZone}
					<span id="booking-zone-label" class="time-picker__zone-label">Time zone</span>
					<TimezonePicker
						id="booking-zone"
						labelledby="booking-zone-label"
						bind:value={zone}
						onchange={() => (changingZone = false)}
					/>
				{:else}
					<span class="time-picker__zone-icon" aria-hidden="true">{@html worldIcon}</span>
					<span>Times in {zoneCity(zone)} time</span>
					<button
						type="button"
						class="time-picker__link-button"
						onclick={() => (changingZone = true)}>Change</button
					>
				{/if}
			</div>
		</div>

		<div class="time-picker__times" aria-live="polite">
			{#if loadingMonth}
				<p class="time-picker__hint">Finding open times…</p>
			{:else if monthQuery.isError && !covered}
				<p class="time-picker__hint">
					We could not load the open times.
					<button
						type="button"
						class="time-picker__link-button"
						onclick={() => monthQuery.refetch()}>Try again</button
					>
				</p>
			{:else if !day}
				<p class="time-picker__hint">
					No open times this month. Try the next month with the arrow above.
				</p>
			{:else}
				<h3 class="time-picker__day-title">{dateWords(dayTimes[0], zone, locale)}</h3>
				<!-- A new day starts its own list, scrolled to its first time. -->
				{#key day?.toString()}
					<ul class="time-picker__list">
						{#each dayTimes as start (start)}
							<li>
								<button type="button" class="time-picker__time" onclick={() => onchoose(start)}>
									{timeWords(start, zone, locale)}
								</button>
							</li>
						{/each}
					</ul>
				{/key}
			{/if}
		</div>
	</div>
{/if}

<style lang="scss">
	.time-picker {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 220px;
		gap: var(--space-larger);
		min-height: 420px;

		@media (max-width: 640px) {
			grid-template-columns: 1fr;
			gap: var(--space-large);
		}
	}

	.time-picker__skeleton {
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle, var(--color-surface--background));
		animation: time-picker-pulse 1.4s ease-in-out infinite;
	}

	.time-picker__skeleton--month {
		height: 380px;
	}

	.time-picker__skeleton--times {
		height: 380px;

		@media (max-width: 640px) {
			height: 160px;
		}
	}

	@keyframes time-picker-pulse {
		50% {
			opacity: 0.5;
		}
	}

	.time-picker__month {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.time-picker__zone {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		:global(.timezone-picker),
		:global(> div) {
			flex: 1 1 240px;
		}
	}

	.time-picker__zone-label {
		flex-basis: 100%;
		font-weight: 600;
		color: var(--color-text);
	}

	.time-picker__zone-icon {
		display: inline-flex;

		:global(svg) {
			width: 1rem;
			height: 1rem;
		}
	}

	.time-picker__link-button {
		padding: 0;
		border: 0;
		background: none;
		color: var(--color-interactive);
		font: inherit;
		font-weight: 600;
		text-decoration: underline;
		text-underline-offset: 2px;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive--hover);
		}

		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}

	.time-picker__times {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
	}

	.time-picker__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.time-picker__day-title {
		margin: 0;
		min-height: 2.5rem;
		display: flex;
		align-items: center;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	.time-picker__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		max-height: 420px;
		margin: 0;
		padding: 0 var(--space-smaller) 0 0;
		overflow-y: auto;
		list-style: none;

		@media (max-width: 640px) {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			max-height: none;
			overflow: visible;
		}
	}

	.time-picker__time {
		width: 100%;
		min-height: 3rem;
		border: var(--border-thick) solid var(--color-interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		color: var(--color-interactive);
		font: inherit;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		cursor: pointer;
		transition:
			background-color 120ms ease,
			color 120ms ease;

		&:hover {
			background: var(--color-interactive);
			color: var(--color-surface);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
</style>
