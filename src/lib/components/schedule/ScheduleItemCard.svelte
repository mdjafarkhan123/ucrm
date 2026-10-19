<script lang="ts">
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import { CARD_STATE_LABELS, type CardState } from '$lib/schedule/status';
	import { initials } from '$lib/collaboration/format';
	import type { CardDensity } from '$lib/schedule/layout';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';

	// Work kind owns the fill; status stays in words, with silver for completed work.

	let {
		density,
		state,
		kind = 'visit',
		time,
		startTime,
		client,
		work,
		place = null,
		people = [],
		showPeople = true,
		marker = null,
		sharedLabel = null,
		badge = null,
		selected = false,
		summary,
		interactive = true,
		onclick,
		onpointerdown,
		onkeydown,
		onblur,
		pressed
	}: {
		density: CardDensity;
		state: CardState;
		/** Which kind of work this is. The calendar's empty-space gestures use it to tell cards apart. */
		kind?: 'visit' | 'assessment';
		/** The full time, `9am – 11am`, or `Anytime`. */
		time: string;
		/** Just the start, for the forms too small for a range. */
		startTime: string;
		client: string;
		work: string;
		place?: string | null;
		/** The names of whoever is going, in order. Their initials are drawn; nothing is drawn for none. */
		people?: string[];
		/** False where the surface itself already says who is going, as the Day board's person row does. The
		 * place takes the footer instead. */
		showPeople?: boolean;
		/** A small Tabler icon (raw SVG) before the time, for work that is not a plain visit. */
		marker?: string | null;
		/** `Shared with Sofia Chen`, or `2` on the forms with no room for words. */
		sharedLabel?: string | null;
		/** The status chip sits beside the time rather than under it, for the wide Day board cards. */
		inlineChip?: boolean;
		/** A small number before the name on the one-line Anytime form, for a person's list of dated-only work. */
		badge?: number | null;
		selected?: boolean;
		/** The whole card in words, for a screen reader and for the smallest form. */
		summary: string;
		interactive?: boolean;
		onclick?: (event: MouseEvent & { currentTarget: HTMLElement }) => void;
		onpointerdown?: (event: PointerEvent) => void;
		onkeydown?: (event: KeyboardEvent) => void;
		onblur?: (event: FocusEvent) => void;
		pressed?: boolean;
	} = $props();

	const chip = $derived(
		state === 'late' || state === 'unassigned' ? CARD_STATE_LABELS[state] : null
	);
	const shownTime = $derived(density === 'standard' ? time : startTime);
	const shownPeople = $derived(showPeople && state !== 'completed' ? people.slice(0, 3) : []);
	const kindIcon = $derived(marker ?? hammerIcon);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<button
	type="button"
	class={[
		'item-card',
		`item-card--${kind}`,
		`item-card--${density}`,
		`item-card--${state}`,
		selected && 'item-card--selected'
	]}
	aria-label={summary}
	aria-pressed={pressed ?? selected}
	title={summary}
	disabled={!interactive}
	{onclick}
	{onpointerdown}
	{onkeydown}
	{onblur}
>
	{#if density === 'micro' || density === 'pill'}
		<span class="item-card__marker" aria-hidden="true">{@html kindIcon}</span>
		{#if density === 'micro' && startTime !== 'Anytime'}<span class="item-card__time"
				>{startTime}</span
			>{/if}
		{#if badge !== null}<span class="item-card__badge">{badge}</span>{/if}
		<span class="item-card__client">{client}</span>
		{#if state === 'unassigned'}<span
				class="item-card__dot item-card__dot--unassigned"
				aria-label="Unassigned"
			></span>{/if}
		{#if state === 'completed'}<span class="item-card__check" aria-hidden="true"
				>{@html circleCheckIcon}</span
			>{/if}
	{:else}
		<span class="item-card__top">
			<span class="item-card__time"
				><span class="item-card__marker" aria-hidden="true">{@html kindIcon}</span>{density ===
				'row'
					? time
					: shownTime}</span
			>
			{#if sharedLabel}<span class="item-card__shared"
					><span class="item-card__shared-icon" aria-hidden="true">{@html usersIcon}</span
					>{sharedLabel}</span
				>{/if}
		</span>
		{#if density === 'standard'}
			<span class="item-card__client">{client}</span><span class="item-card__work">{work}</span>
		{:else}
			<span class="item-card__words"
				><span class="item-card__client">{client}</span><span class="item-card__work">{work}</span
				></span
			>
		{/if}
		<span class="item-card__foot">
			{#if shownPeople.length > 0}<span class="item-card__people" aria-hidden="true"
					>{#each shownPeople as person, index (`${person}-${index}`)}<span
							class="item-card__avatar">{initials(person)}</span
						>{/each}</span
				>
			{:else if !showPeople && place && density === 'standard'}<span class="item-card__place"
					><span aria-hidden="true">{@html mapPinIcon}</span>{place}</span
				>{/if}
			{#if chip}<span class={`item-card__chip item-card__chip--${state}`}
					><span class={`item-card__dot item-card__dot--${state}`} aria-hidden="true"
					></span>{chip}</span
				>
			{:else if state === 'completed'}<span class="item-card__chip item-card__chip--completed"
					><span class="item-card__check" aria-hidden="true">{@html circleCheckIcon}</span
					>Completed</span
				>{/if}
		</span>
	{/if}
</button>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.item-card {
		--item-kind: var(--color-job);
		--item-fill: var(--color-job--surface);
		--item-on: var(--color-job--onSurface);
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: 6px var(--space-small);
		overflow: hidden;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		background: var(--item-fill);
		color: var(--color-text);
		font-family: inherit;
		text-align: left;
		cursor: pointer;
		&:hover:not(:disabled),
		&--selected {
			border-color: var(--item-kind);
			box-shadow: 0 4px 12px color-mix(in srgb, var(--color-heading) 12%, transparent);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			cursor: default;
		}
	}
	.item-card--assessment {
		--item-kind: var(--color-request);
		--item-fill: var(--color-request--surface);
		--item-on: var(--color-request--onSurface);
	}
	.item-card--late {
		border-left: 4px solid var(--color-critical);
	}
	.item-card--completed {
		--item-fill: var(--color-surface--active);
		--item-on: var(--color-text--secondary);
		--item-kind: var(--color-icon--secondary);
		border-color: var(--color-border--interactive);
		.item-card__client,
		.item-card__work,
		.item-card__time {
			color: var(--color-text--secondary);
			text-decoration: line-through;
		}
	}
	.item-card__top,
	.item-card__foot {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-smaller);
		min-width: 0;
	}
	.item-card__foot {
		margin-top: auto;
	}
	.item-card__time {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		flex-shrink: 0;
		color: var(--item-on);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		line-height: 1.25;
		white-space: nowrap;
	}
	.item-card__marker,
	.item-card__shared-icon,
	.item-card__check {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--item-kind);
		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	.item-card__client {
		min-width: 0;
		overflow: hidden;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		line-height: 1.25;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.item-card__work {
		min-width: 0;
		overflow: hidden;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		line-height: 1.25;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.item-card__words {
		display: flex;
		align-items: baseline;
		gap: var(--space-smaller);
		min-width: 0;
		overflow: hidden;
	}
	.item-card__people {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
	}
	.item-card__avatar {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 24px;
		height: 24px;
		border: 2px solid var(--item-fill);
		border-radius: var(--radius-circle);
		background: var(--color-heading);
		color: var(--color-surface);
		font-size: var(--typography--fontSize-overline);
		font-weight: 700;
	}
	.item-card__shared {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--item-on);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		white-space: nowrap;
	}
	.item-card__place {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
		text-overflow: ellipsis;
		white-space: nowrap;
		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	.item-card__chip {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		margin-left: auto;
		padding: 3px var(--space-small);
		border: var(--border-base) solid var(--chip-main);
		border-radius: var(--radius-circle);
		background: var(--color-surface);
		color: var(--chip-text);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		line-height: 1;
		white-space: nowrap;
	}
	.item-card__chip--late {
		--chip-main: var(--color-critical);
		--chip-text: var(--color-critical--onSurface);
	}
	.item-card__chip--unassigned {
		--chip-main: var(--color-warning);
		--chip-text: var(--color-warning--onSurface);
	}
	.item-card__chip--completed {
		--chip-main: transparent;
		--chip-text: var(--color-success--onSurface);
		background: var(--color-success--surface);
		.item-card__check {
			color: var(--color-success);
			:global(svg) {
				width: 11px;
				height: 11px;
			}
		}
	}
	.item-card__dot {
		width: 5px;
		height: 5px;
		flex-shrink: 0;
		border-radius: var(--radius-circle);
	}
	.item-card__dot--late {
		background: var(--color-critical);
	}
	.item-card__dot--unassigned {
		background: var(--color-warning);
	}
	.item-card--micro,
	.item-card--pill {
		flex-direction: row;
		align-items: center;
		gap: 5px;
		padding: 0 6px;
		border-radius: var(--radius-tile-small);
		.item-card__time,
		.item-card__client {
			font-size: var(--typography--fontSize-overline);
		}
		.item-card__marker :global(svg) {
			width: 12px;
			height: 12px;
		}
		.item-card__dot,
		.item-card__check {
			margin-left: auto;
		}
	}
	.item-card--pill {
		gap: 6px;
		padding: 0 var(--space-small);
		.item-card__client {
			font-size: var(--typography--fontSize-small);
		}
		.item-card__marker :global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	.item-card--row {
		height: auto;
		min-height: 52px;
		padding: var(--space-small) 10px;
	}
	.item-card--compact {
		padding: 5px var(--space-small);
		.item-card__foot {
			position: absolute;
			top: 5px;
			right: var(--space-small);
			margin: 0;
		}
		.item-card__top {
			min-height: 20px;
		}
		.item-card__avatar {
			width: 20px;
			height: 20px;
			font-size: 9px;
		}
	}
	.item-card__badge {
		color: var(--item-on);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
	}
</style>
