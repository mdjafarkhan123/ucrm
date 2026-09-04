<script lang="ts">
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import RouteStopCard from '$lib/components/schedule/RouteStopCard.svelte';
	import type { RouteStop } from '$lib/schedule/route-order';
	import {
		applySavedOrder,
		defaultRouteOrder,
		isAnchor,
		moveAnytimeStop,
		serializeRouteOrder
	} from '$lib/schedule/route-order';
	import { stopGeocodeState, stopNavPlace } from '$lib/schedule/stops';
	import { routeDirections } from '$lib/schedule/directions';
	import { startPointerDrag } from '$lib/schedule/pointer-drag';
	import mapIcon from '@tabler/icons/outline/map-2.svg?raw';
	import directionIcon from '@tabler/icons/outline/directions.svg?raw';
	import saveIcon from '@tabler/icons/outline/device-floppy.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	// The contextual Map workspace: one selected employee's stops for the chosen day, laid out as an ordered
	// list beside the map pane. Provider-independent -- it draws no live tiles yet (that arrives with real
	// Mapbox), so the map pane is an honest shell that says where the route stands. The ordered list is fully
	// usable on its own: reorder the Anytime stops, and open Directions for one stop or the whole route.

	let {
		stops,
		employeeName,
		savedOrder = null,
		saving = false,
		selectedItemId = null,
		onselect,
		onsave,
		onclose
	}: {
		stops: RouteStop[];
		employeeName: string;
		/** The order saved for this employee and day, or null while it is still being loaded. */
		savedOrder?: string[] | null;
		/** True while a save is in flight, so the button reads "Saving…" and cannot be pressed again. */
		saving?: boolean;
		selectedItemId?: string | null;
		onselect: (stop: RouteStop, element: HTMLElement) => void;
		onsave: (order: string[]) => void;
		onclose: () => void;
	} = $props();

	// The dispatcher's manual arrangement this session, as a list of stop ids. Null means "no drag yet", so the
	// list falls back to whatever is saved, and to the default order when nothing is saved. A drag sets this and
	// takes over; a save persists it and the parent feeds the result back in through `savedOrder`.
	let manualOrder = $state<string[] | null>(null);

	// The order that actually drives the list: this session's drag if there is one, otherwise the saved order,
	// otherwise the default. So a saved route rehydrates on open, and a drag overrides it.
	const effectiveOrder = $derived(manualOrder ?? savedOrder);

	// The order the list draws in. The chosen order is merged against the stops actually in hand -- ids that
	// have gone are dropped, stops added since are slotted in at their default -- and the anchors are always
	// re-settled into clock order, so a refetch never scrambles the route.
	const ordered = $derived(
		effectiveOrder ? applySavedOrder(stops, effectiveOrder) : defaultRouteOrder(stops)
	);

	// The ids the list currently reads in, and the ids last saved, compared to know whether there is anything
	// worth saving. Save is offered only after a real drag (manualOrder set) that leaves the order different
	// from what is stored, and never while the saved order is still loading or a save is already running.
	const currentOrder = $derived(serializeRouteOrder(ordered));
	const dirty = $derived(
		manualOrder !== null &&
			savedOrder !== null &&
			(currentOrder.length !== savedOrder.length ||
				currentOrder.some((id, index) => id !== savedOrder![index]))
	);
	const canSave = $derived(dirty && !saving);

	function save() {
		if (!canSave) return;
		onsave(currentOrder);
	}

	// The stop being dragged, so its row reads lifted while it travels.
	let draggingId = $state<string | null>(null);

	let listEl = $state<HTMLOListElement | null>(null);

	// Where the pointer sits, as an index into the current order: the row whose vertical midpoint the pointer is
	// above. Used to slot the dragged stop live as it moves.
	function indexUnderPointer(clientY: number): number {
		if (!listEl) return ordered.length;
		const rows = Array.from(listEl.querySelectorAll<HTMLElement>('li[data-stop-id]'));
		for (let index = 0; index < rows.length; index++) {
			const box = rows[index].getBoundingClientRect();
			if (clientY < box.top + box.height / 2) return index;
		}
		return rows.length;
	}

	function pickUp(event: PointerEvent, stopId: string) {
		startPointerDrag(event, {
			onStart: () => {
				draggingId = stopId;
			},
			onMove: (moved) => {
				const target = indexUnderPointer(moved.clientY);
				const next = moveAnytimeStop(ordered, stopId, target);
				manualOrder = serializeRouteOrder(next);
			},
			onDrop: () => {
				draggingId = null;
			},
			onCancel: () => {
				draggingId = null;
			}
		});
	}

	// Keyboard reordering: move the focused Anytime stop one slot earlier or later, past whatever anchor sits
	// beside it, and let the anchor order re-settle itself.
	function moveByKey(stopId: string, direction: -1 | 1) {
		const from = ordered.findIndex((stop) => stop.id === stopId);
		if (from === -1) return;
		const next = moveAnytimeStop(ordered, stopId, from + direction);
		manualOrder = serializeRouteOrder(next);
	}

	// Whole-route Directions in the current order. A provider that cannot take this many waypoints is offered
	// but disabled, with the limit spelled out, exactly as the contract requires -- every single stop still has
	// its own Directions regardless.
	const navPlaces = $derived(ordered.map(stopNavPlace));
	const googleRoute = $derived(routeDirections(navPlaces, 'google'));
	const appleRoute = $derived(routeDirections(navPlaces, 'apple'));

	function routeItemLabel(
		base: string,
		link: ReturnType<typeof routeDirections>
	): { label: string; disabled: boolean; onSelect: () => void } {
		if (link.ok) {
			return {
				label: base,
				disabled: false,
				onSelect: () => window.open(link.url, '_blank', 'noopener')
			};
		}
		const why =
			link.reason === 'too-many-stops'
				? ` — too many stops (max ${link.limit})`
				: ' — no mappable stops';
		return { label: `${base}${why}`, disabled: true, onSelect: () => {} };
	}

	const routeItems = $derived([
		routeItemLabel('Google Maps', googleRoute),
		routeItemLabel('Apple Maps', appleRoute)
	]);
	const canRouteDirect = $derived(googleRoute.ok || appleRoute.ok);

	// How ready the route is to draw, for the map shell's summary. Located stops can be pinned; the rest stay in
	// the list and are counted so the dispatcher knows what is missing rather than wondering where a pin went.
	const locatedCount = $derived(
		ordered.filter((stop) => stopGeocodeState(stop) === 'located').length
	);
	const unplacedCount = $derived(ordered.length - locatedCount);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="route" aria-label="Route for {employeeName}">
	<header class="route__header">
		<div class="route__heading">
			<h2 class="route__title">{employeeName}'s route</h2>
			<p class="route__count">
				{ordered.length}
				{ordered.length === 1 ? 'stop' : 'stops'}
			</p>
		</div>
		<div class="route__actions">
			<!-- Save appears only once the dispatcher has rearranged the route, so there is never a permanently
			     disabled button here; it saves this employee's order for this day and then steps aside. -->
			{#if dirty || saving}
				<button
					type="button"
					class="route__save"
					onclick={save}
					disabled={!canSave}
					aria-busy={saving}
				>
					{@html saveIcon}<span>{saving ? 'Saving…' : 'Save Route Order'}</span>
				</button>
			{/if}
			{#if canRouteDirect}
				<DropdownMenu items={routeItems} triggerLabel="Directions for the whole route">
					{#snippet trigger()}
						<span class="route__direct">{@html directionIcon}<span>Directions</span></span>
					{/snippet}
				</DropdownMenu>
			{/if}
			<button type="button" class="route__close" aria-label="Close map" onclick={onclose}>
				{@html closeIcon}
			</button>
		</div>
	</header>

	<div class="route__body">
		<div class="route__list-pane">
			{#if ordered.length === 0}
				<p class="route__empty">No stops for {employeeName} on this day.</p>
			{:else}
				<ol class="route__list" bind:this={listEl}>
					{#each ordered as stop, index (stop.id)}
						{@const anchor = isAnchor(stop)}
						<li data-stop-id={stop.id} class:route__row--dragging={draggingId === stop.id}>
							<RouteStopCard
								{stop}
								position={index + 1}
								{anchor}
								selected={selectedItemId === stop.id}
								{onselect}
								onpickup={anchor ? undefined : (event) => pickUp(event, stop.id)}
								onmovekey={anchor ? undefined : (direction) => moveByKey(stop.id, direction)}
							/>
						</li>
					{/each}
				</ol>
			{/if}
		</div>

		<!-- The map pane is a shell until live Mapbox tiles arrive. It never pretends to draw a route; it says
		     plainly where the map stands and how many stops can be pinned once it does. -->
		<div class="route__map" role="region" aria-label="Map">
			<div class="route__map-shell">
				<span class="route__map-icon" aria-hidden="true">{@html mapIcon}</span>
				<p class="route__map-title">Map arrives with live maps</p>
				{#if ordered.length === 0}
					<p class="route__map-note">There are no stops to place on this day.</p>
				{:else if locatedCount === 0}
					<p class="route__map-note">
						None of these {ordered.length} stops can be placed on the map yet. They stay in the list,
						and each still offers Directions.
					</p>
				{:else}
					<p class="route__map-note">
						{locatedCount} of {ordered.length} stops ready to map{unplacedCount > 0
							? ` · ${unplacedCount} still to place`
							: ''}.
					</p>
				{/if}
			</div>
		</div>
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.route {
		display: flex;
		flex: 1 1 auto;
		min-width: 0;
		flex-direction: column;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	.route__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.route__heading {
		display: flex;
		align-items: baseline;
		gap: var(--space-small);
		min-width: 0;
	}

	.route__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.route__count {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		white-space: nowrap;
	}

	.route__actions {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.route__direct {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		height: 34px;
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	/* A compact work action sitting next to the Directions pill: green so a pending save reads as the thing to
	   do, matching the header's 34px control height rather than the taller base Button. */
	.route__save {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		height: 34px;
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-interactive);
		border-radius: var(--radius-base);
		background-color: var(--color-interactive);
		color: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;
		transition: background-color var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-interactive--hover);
			border-color: var(--color-interactive--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			background-color: var(--color-disabled--secondary);
			border-color: var(--color-disabled--secondary);
			color: var(--color-disabled);
			cursor: not-allowed;
		}

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.route__close {
		display: inline-grid;
		place-items: center;
		width: 34px;
		height: 34px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		color: var(--color-icon);
		cursor: pointer;
		transition: background-color var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.route__body {
		display: flex;
		flex: 1 1 auto;
		min-height: 420px;
	}

	.route__list-pane {
		flex: 0 0 360px;
		max-width: 45%;
		overflow-y: auto;
		padding: var(--space-base);
		border-right: var(--border-base) solid var(--color-border);
	}

	.route__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.route__row--dragging {
		opacity: 0.6;
	}

	.route__empty {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.route__map {
		display: grid;
		flex: 1 1 auto;
		place-items: center;
		min-width: 0;
		padding: var(--space-large);
		background-color: var(--color-surface--background--subtle);
	}

	.route__map-shell {
		display: flex;
		max-width: 320px;
		flex-direction: column;
		align-items: center;
		gap: var(--space-small);
		text-align: center;
	}

	.route__map-icon {
		display: inline-grid;
		place-items: center;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 40px;
			height: 40px;
		}
	}

	.route__map-title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	.route__map-note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	@media (max-width: 900px) {
		.route__body {
			flex-direction: column;
		}
		.route__list-pane {
			flex-basis: auto;
			max-width: none;
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
		}
		.route__map {
			min-height: 240px;
		}
	}
</style>
