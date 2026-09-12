<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import { fetchFormBookingSlots, formBookingSlotsKey } from '$lib/forms/api';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';

	// Real slots from the same engine 4B-2b built (public.get_form_available_slots) over the next two weeks —
	// approved recommendation 2026-09-13: this reflects the saved rules, refreshed after Save, rather than a
	// second "what-if" computation kept live on every keystroke.
	const PREVIEW_DAYS = 14;

	let { formId, hoursSet }: { formId: string; hoursSet: boolean } = $props();

	function isoDate(date: Date): string {
		return date.toISOString().slice(0, 10);
	}

	const rangeStart = isoDate(new Date());
	const rangeEnd = isoDate(new Date(Date.now() + (PREVIEW_DAYS - 1) * 86_400_000));

	const query = createQuery(() => ({
		queryKey: formBookingSlotsKey(formId, rangeStart, rangeEnd),
		queryFn: () => fetchFormBookingSlots(formId, rangeStart, rangeEnd),
		enabled: hoursSet,
		staleTime: 30_000
	}));

	function formatTime(time: string): string {
		const [hour, minute] = time.split(':').map(Number);
		return new Date(2000, 0, 1, hour, minute).toLocaleTimeString(undefined, {
			hour: 'numeric',
			minute: minute ? '2-digit' : undefined
		});
	}

	function formatDate(dateStr: string): string {
		return new Date(`${dateStr}T00:00:00`).toLocaleDateString(undefined, {
			weekday: 'short',
			month: 'short',
			day: 'numeric'
		});
	}

	// One row per day that actually has open time, earliest five days shown so the card stays a glance, not
	// a report — a person can already see the full picture on the real public form once it publishes (4C).
	const days = $derived.by(() => {
		const byDate = new Map<string, string[]>();
		for (const slot of query.data ?? []) {
			const times = byDate.get(slot.slot_date) ?? [];
			times.push(formatTime(slot.start_time));
			byDate.set(slot.slot_date, times);
		}
		return [...byDate.entries()].slice(0, 5);
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Card heading="Sample available times">
	{#if !hoursSet}
		<p class="booking-preview__hint">
			Set your business hours in Settings → Business profile to see sample times here.
		</p>
	{:else if query.isPending}
		<p class="booking-preview__hint">Loading…</p>
	{:else if query.isError}
		<p class="booking-preview__hint">Sample times could not be loaded.</p>
	{:else if days.length === 0}
		<p class="booking-preview__hint">
			No open times in the next {PREVIEW_DAYS} days with the current rules. Try shortening the minimum
			notice or lengthening business hours.
		</p>
	{:else}
		<ul class="booking-preview__days">
			{#each days as [date, times] (date)}
				<li class="booking-preview__day">
					<span class="booking-preview__date">{formatDate(date)}</span>
					<span class="booking-preview__times">{times.slice(0, 4).join(' · ')}</span>
				</li>
			{/each}
		</ul>
	{/if}
	<Button
		variant="secondary"
		size="small"
		onclick={() => query.refetch()}
		loading={query.isFetching}
		disabled={!hoursSet}
	>
		<span class="booking-preview__refresh-icon" aria-hidden="true">{@html refreshIcon}</span>
		Refresh preview
	</Button>
</Card>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.booking-preview {
		&__hint {
			margin: 0 0 var(--space-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__days {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0 0 var(--space-base);
			padding: 0;
			list-style: none;
		}
		&__day {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-small);
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}
		&__date {
			flex-shrink: 0;
			color: var(--color-heading);
			font-weight: 600;
		}
		&__times {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: right;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__refresh-icon {
			display: inline-grid;
			place-items: center;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
