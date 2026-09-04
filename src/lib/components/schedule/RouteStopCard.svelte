<script lang="ts">
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import type { RouteStop } from '$lib/schedule/route-order';
	import {
		stopAddressLabel,
		stopClientLabel,
		stopGeocodeState,
		stopNavPlace,
		stopTimeLabel,
		stopWorkLabel
	} from '$lib/schedule/stops';
	import { singleStopDirections } from '$lib/schedule/directions';
	import gripIcon from '@tabler/icons/outline/grip-vertical.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import directionIcon from '@tabler/icons/outline/directions.svg?raw';

	// One row in the Map's stop list: a place the crew has to be, drawn with its route number, when it is, whose
	// it is, where it is, and whether we can put it on the map yet. A fixed-time Visit and every Assessment are
	// anchors -- locked in chronological order, shown with a lock -- and only an Anytime Visit carries a drag
	// handle, because it is the only stop the dispatcher may reorder here.

	let {
		stop,
		position,
		anchor,
		selected = false,
		onselect,
		onpickup,
		onmovekey
	}: {
		stop: RouteStop;
		/** The stop's place in the route, 1-based, matching the numbered marker the map draws. */
		position: number;
		/** A fixed-time Visit or any Assessment: locked in clock order, not reorderable here. */
		anchor: boolean;
		selected?: boolean;
		/** The row was clicked: the workspace opens the same preview the calendar does, anchored to this row. */
		onselect: (stop: RouteStop, element: HTMLElement) => void;
		/** An Anytime stop's handle was pressed, to begin a pointer drag. Absent on an anchor. */
		onpickup?: (event: PointerEvent) => void;
		/** Keyboard reordering from the handle: -1 moves the stop one slot earlier, 1 one slot later. */
		onmovekey?: (direction: -1 | 1) => void;
	} = $props();

	const state = $derived(stopGeocodeState(stop));
	const client = $derived(stopClientLabel(stop));
	const work = $derived(stopWorkLabel(stop));
	const address = $derived(stopAddressLabel(stop));
	const time = $derived(stopTimeLabel(stop));

	// The words a stop wears when the map cannot place it. `located` needs none -- the pin says it. The other
	// three keep the stop in the list, each explaining why there is no pin, so nothing is ever silently dropped.
	const STATE_LABEL: Record<typeof state, string | null> = {
		located: null,
		pending: 'Locating…',
		failed: "Address didn't map",
		'no-address': 'No address'
	};
	const stateLabel = $derived(STATE_LABEL[state]);

	// The whole row in one sentence, for a screen reader.
	const summary = $derived(
		[`Stop ${position}`, time, client, work, stateLabel].filter(Boolean).join(', ')
	);

	// Per-stop Directions: a single destination always has one, whether from stored coordinates or the raw
	// address, so the menu offers Google and Apple and only disables a provider when there is nothing to route
	// to at all.
	const navPlace = $derived(stopNavPlace(stop));
	const googleLink = $derived(singleStopDirections(navPlace, 'google'));
	const appleLink = $derived(singleStopDirections(navPlace, 'apple'));

	const directionItems = $derived([
		{
			label: 'Google Maps',
			onSelect: () => googleLink.ok && window.open(googleLink.url, '_blank', 'noopener'),
			disabled: !googleLink.ok
		},
		{
			label: 'Apple Maps',
			onSelect: () => appleLink.ok && window.open(appleLink.url, '_blank', 'noopener'),
			disabled: !appleLink.ok
		}
	]);
	const canDirect = $derived(googleLink.ok || appleLink.ok);

	function handleKey(event: KeyboardEvent) {
		if (anchor || !onmovekey) return;
		if (event.key === 'ArrowUp') {
			event.preventDefault();
			onmovekey(-1);
		} else if (event.key === 'ArrowDown') {
			event.preventDefault();
			onmovekey(1);
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class="route-stop"
	class:route-stop--selected={selected}
	class:route-stop--anchor={anchor}
	class:route-stop--unplaced={state !== 'located'}
>
	{#if anchor}
		<span
			class="route-stop__handle route-stop__handle--locked"
			title="Fixed order"
			aria-hidden="true"
		>
			{@html lockIcon}
		</span>
	{:else}
		<button
			type="button"
			class="route-stop__handle"
			aria-label="Reorder {work}. Use the up and down arrow keys, or drag."
			onpointerdown={onpickup}
			onkeydown={handleKey}
		>
			{@html gripIcon}
		</button>
	{/if}

	<span class="route-stop__number" aria-hidden="true">{position}</span>

	<button
		type="button"
		class="route-stop__body"
		aria-label={summary}
		aria-pressed={selected}
		onclick={(event) => onselect(stop, event.currentTarget)}
	>
		<span class="route-stop__line">
			<span class="route-stop__time">{time}</span>
			<span class="route-stop__client">{client}</span>
		</span>
		<span class="route-stop__work">{work}</span>
		{#if address}
			<span class="route-stop__address">{address}</span>
		{/if}
		{#if stateLabel}
			<span class="route-stop__state route-stop__state--{state}">{stateLabel}</span>
		{/if}
	</button>

	{#if canDirect}
		<DropdownMenu
			items={directionItems}
			triggerLabel="Directions to {work}"
			triggerIcon={directionIcon}
		/>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.route-stop {
		display: grid;
		grid-template-columns: auto auto 1fr auto;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);

		&--selected {
			border-color: var(--color-interactive);
			background-color: var(--color-surface--active);
		}

		// A stop the map cannot pin yet is not an error -- it stays in the list, only quieter, with its state
		// spelled out below so the dispatcher knows why there is no marker for it.
		&--unplaced {
			background-color: var(--color-surface--background--subtle);
		}
	}

	.route-stop__handle {
		display: inline-grid;
		place-items: center;
		width: 24px;
		height: 24px;
		padding: 0;
		border: 0;
		border-radius: var(--radius-small);
		background: transparent;
		color: var(--color-icon--secondary);
		cursor: grab;
		touch-action: none;

		&:hover {
			background-color: var(--color-surface--hover);
			color: var(--color-icon);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&--locked {
			cursor: default;
			color: var(--color-icon--secondary);
			&:hover {
				background: transparent;
			}
		}

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	// The route number, drawn as the marker it matches on the map.
	.route-stop__number {
		display: inline-grid;
		place-items: center;
		width: 24px;
		height: 24px;
		border-radius: var(--radius-circle);
		background-color: var(--color-interactive);
		color: var(--color-surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
	}

	.route-stop--anchor .route-stop__number {
		// An anchor's number reads calmer than an Anytime stop's, because its order is not the dispatcher's to
		// change -- it is set by the clock.
		background-color: var(--color-inactive);
	}

	.route-stop__body {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
		padding: 0;
		border: 0;
		background: transparent;
		color: inherit;
		font-family: inherit;
		text-align: left;
		cursor: pointer;
	}

	.route-stop__body:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
		border-radius: var(--radius-small);
	}

	.route-stop__line {
		display: flex;
		align-items: baseline;
		gap: var(--space-small);
		min-width: 0;
	}

	.route-stop__time {
		flex-shrink: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}

	.route-stop__client {
		overflow: hidden;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.route-stop__work,
	.route-stop__address {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.route-stop__state {
		margin-top: var(--space-smallest);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;

		&--pending {
			color: var(--color-text--secondary);
		}
		&--failed {
			color: var(--color-warning--onSurface);
		}
		&--no-address {
			color: var(--color-text--secondary);
		}
	}
</style>
