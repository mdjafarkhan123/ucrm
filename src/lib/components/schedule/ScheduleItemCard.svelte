<script lang="ts">
	import { CARD_STATE_LABELS, type CardState } from '$lib/schedule/status';
	import { initials } from '$lib/collaboration/format';
	import type { CardDensity } from '$lib/schedule/layout';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';

	// The one card the calendar draws for a piece of booked work. A visit and an assessment look the same
	// apart from the small marker beside the time, so both hand their words to this card and it draws the
	// colour: the fill and outline say where the work stands (late, unassigned, in progress, done), and the
	// word travels beside the dot so colour is never the only signal.
	//
	// The card does not choose its own size. The grid measured the room and says which form fits, so a
	// fifteen-minute visit keeps its true length and simply shows less.

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
		inlineChip = false,
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
		state === 'scheduled' || state === 'completed' ? null : CARD_STATE_LABELS[state]
	);
	const shownTime = $derived(density === 'standard' ? time : startTime);
	const shownPeople = $derived(showPeople ? people.slice(0, 3) : []);
	// A compact card is short, so its status chip sits beside the time instead of taking a line of its own.
	const chipBesideTime = $derived(inlineChip || density === 'compact');
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<button
	type="button"
	class="item-card item-card--{kind} item-card--{density} item-card--{state}"
	class:item-card--selected={selected}
	aria-label={summary}
	aria-pressed={pressed ?? selected}
	title={summary}
	disabled={!interactive}
	{onclick}
	{onpointerdown}
	{onkeydown}
	{onblur}
>
	{#if density === 'row'}
		<span class="item-card__list-line">
			<span class="item-card__list-time">
				{#if marker}<span class="item-card__marker" aria-hidden="true">{@html marker}</span>{/if}
				{shownTime}
			</span>
			<span class="item-card__list-words">
				<span class="item-card__client">{client}</span>
				<span class="item-card__work">{work}</span>
			</span>
			{#if chip}
				<span class="item-card__chip item-card__chip--{state}">
					<span class="item-card__dot item-card__dot--{state}" aria-hidden="true"></span>
					{chip}
				</span>
			{:else if state === 'completed'}
				<span class="item-card__check" aria-hidden="true">{@html circleCheckIcon}</span>
			{/if}
		</span>
	{:else if density === 'pill'}
		<span class="item-card__line">
			{#if badge !== null}<span class="item-card__badge" aria-hidden="true">{badge}</span>{/if}
			{#if marker}<span class="item-card__marker" aria-hidden="true">{@html marker}</span>{/if}
			<span class="item-card__words"><span class="item-card__client">{client}</span></span>
			{#if state === 'completed'}
				<span class="item-card__check" aria-hidden="true">{@html circleCheckIcon}</span>
			{/if}
			{#if shownPeople.length > 0}
				<span class="item-card__people item-card__people--pill" aria-hidden="true">
					{#each shownPeople as person, index (index)}
						<span class="item-card__avatar">{initials(person)}</span>
					{/each}
				</span>
			{/if}
		</span>
	{:else if density === 'micro'}
		<span class="item-card__line">
			{#if chip}<span class="item-card__dot item-card__dot--{state}" aria-hidden="true"></span>{/if}
			{#if marker}<span class="item-card__marker" aria-hidden="true">{@html marker}</span>{/if}
			<span class="item-card__time">{startTime}</span>
			<span class="item-card__words">
				<span class="item-card__client">{client}</span>
				<span class="item-card__work">{work}</span>
			</span>
			{#if state === 'completed'}
				<span class="item-card__check" aria-hidden="true">{@html circleCheckIcon}</span>
			{/if}
		</span>
	{:else}
		<span class="item-card__top">
			<span class="item-card__time">
				{#if marker}<span class="item-card__marker" aria-hidden="true">{@html marker}</span>{/if}
				{shownTime}
			</span>
			<span class="item-card__flags">
				{#if sharedLabel}
					<span class="item-card__shared">
						<span class="item-card__shared-icon" aria-hidden="true">{@html usersIcon}</span>
						{sharedLabel}
					</span>
				{/if}
				{#if chip && chipBesideTime}
					<span class="item-card__chip item-card__chip--{state}">
						<span class="item-card__dot item-card__dot--{state}" aria-hidden="true"></span>
						{chip}
					</span>
				{/if}
				{#if state === 'completed'}
					<span class="item-card__check" aria-hidden="true">{@html circleCheckIcon}</span>
				{/if}
			</span>
		</span>

		{#if chip && !chipBesideTime}
			<span class="item-card__chip item-card__chip--{state}">
				<span class="item-card__dot item-card__dot--{state}" aria-hidden="true"></span>
				{chip}
			</span>
		{/if}

		{#if density === 'standard'}
			<span class="item-card__client item-card__client--block">{client}</span>
			<span class="item-card__work item-card__work--block">{work}</span>
		{:else}
			<span class="item-card__work item-card__work--line">
				<span class="item-card__client">{client}</span> · {work}
			</span>
		{/if}

		{#if density === 'standard'}
			{#if shownPeople.length > 0}
				<span class="item-card__people" aria-hidden="true">
					{#each shownPeople as person, index (index)}
						<span class="item-card__avatar">{initials(person)}</span>
					{/each}
				</span>
			{:else if !showPeople && place}
				<span class="item-card__place">
					<span class="item-card__place-icon" aria-hidden="true">{@html mapPinIcon}</span>
					<span class="item-card__place-text">{place}</span>
				</span>
			{/if}
		{/if}
	{/if}
</button>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.item-card {
		// What this state paints with. The fill and outline carry the status; the text colours step in to keep
		// the words readable on whatever the fill is.
		--item-fill: var(--color-surface);
		--item-edge: var(--color-border);
		--item-edge-width: 1px;
		--item-time: var(--color-text--secondary);
		--item-client: var(--color-heading);
		--item-work: var(--color-text--secondary);

		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: 7px var(--space-small) var(--space-small) 9px;
		overflow: hidden;
		border: var(--item-edge-width) solid var(--item-edge);
		border-radius: var(--radius-base);
		background-color: var(--item-fill);
		color: var(--color-text);
		font-family: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			background-color var(--timing-quick) ease,
			box-shadow var(--timing-quick) ease;

		&:hover {
			--item-fill: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			cursor: default;
		}
	}

	.item-card--selected {
		box-shadow: var(--shadow-focus);
	}

	.item-card--completed {
		--item-fill: var(--color-surface--background--subtle);
		--item-time: var(--color-icon--secondary);
		--item-client: var(--color-text--secondary);
		--item-work: var(--color-icon--secondary);

		&:hover {
			--item-fill: var(--color-surface--hover);
		}
	}

	.item-card--late {
		--item-fill: var(--color-critical--surface);
		--item-edge: var(--color-critical);
		--item-edge-width: 1.5px;
		--item-time: var(--color-critical);

		&:hover {
			--item-fill: var(--color-critical--surface);
		}
	}

	.item-card--unassigned {
		--item-fill: var(--color-warning--surface);
		--item-edge: var(--color-warning--surface);
		--item-time: var(--color-warning--onSurface);

		&:hover {
			--item-fill: var(--color-warning--surface);
		}
	}

	.item-card--in-progress {
		--item-edge: var(--color-interactive);
		--item-edge-width: 1.5px;
		--item-time: var(--color-interactive);
	}

	.item-card__top {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.item-card__flags {
		display: inline-flex;
		align-items: center;
		flex-shrink: 0;
		gap: var(--space-smaller);
	}

	.item-card__time {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--item-time);
		font-size: 11px;
		font-weight: 600;
		line-height: 1.3;
		white-space: nowrap;
	}

	.item-card__marker {
		display: inline-flex;
		flex-shrink: 0;

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}

	.item-card__check {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--color-interactive);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.item-card__shared {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: 2px 7px 2px 6px;
		border-radius: 99px;
		background-color: var(--color-surface--background--subtle);
		color: var(--color-text--secondary);
		font-size: 10.5px;
		font-weight: 600;
		line-height: 1.3;
		white-space: nowrap;
	}

	.item-card__shared-icon {
		display: inline-flex;

		:global(svg) {
			width: 11px;
			height: 11px;
		}
	}

	.item-card__chip {
		display: inline-flex;
		align-items: center;
		align-self: flex-start;
		gap: 3px;
		padding: 2px 6px 2px 5px;
		border-radius: 99px;
		font-size: 9.5px;
		font-weight: 700;
		line-height: 1.3;
		white-space: nowrap;

		&--late {
			background-color: var(--color-critical--surface);
			color: var(--color-critical);
		}
		&--unassigned {
			background-color: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}
		&--in-progress {
			background-color: var(--color-success--surface);
			color: var(--color-interactive);
		}
	}

	.item-card__dot {
		display: inline-block;
		flex-shrink: 0;
		width: 5px;
		height: 5px;
		border-radius: var(--radius-circle);

		&--late {
			background-color: var(--color-critical);
		}
		&--unassigned {
			background-color: var(--color-warning);
		}
		&--in-progress {
			background-color: var(--color-success);
		}
	}

	.item-card__client {
		color: var(--item-client);
		font-size: 12px;
		font-weight: 600;
		line-height: 1.25;
	}

	.item-card__client--block {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.item-card__work {
		color: var(--item-work);
		font-size: 11px;
		font-weight: 500;
		line-height: 1.3;
	}

	.item-card__work--block {
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 3;
		line-clamp: 3;
		overflow: hidden;
	}

	.item-card__work--line {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.item-card__people {
		display: inline-flex;
		align-items: center;
		margin-top: auto;
		padding-left: 3px;
	}

	.item-card__avatar {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 20px;
		height: 20px;
		margin-left: -3px;
		border: 1.5px solid var(--item-fill);
		border-radius: var(--radius-circle);
		background-color: var(--color-surface--background--subtle);
		color: var(--color-text);
		font-size: 8.5px;
		font-weight: 700;
	}

	.item-card--late .item-card__avatar {
		background-color: var(--color-surface);
	}

	.item-card--completed .item-card__avatar {
		color: var(--color-text--secondary);
	}

	.item-card__place {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin-top: auto;
		min-width: 0;
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 500;
	}

	.item-card__place-icon {
		display: inline-flex;
		flex-shrink: 0;

		:global(svg) {
			width: 11px;
			height: 11px;
		}
	}

	.item-card__place-text {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	// The month cell and the Anytime lane: one line, as tall as the slot gives it.
	.item-card--micro,
	.item-card--pill {
		justify-content: center;
		padding: 0 var(--space-small) 0 var(--space-slim);
		border-radius: var(--radius-base);

		.item-card__line {
			display: flex;
			align-items: center;
			gap: 6px;
			min-width: 0;
		}

		.item-card__time {
			flex-shrink: 0;
			font-weight: 500;
		}

		.item-card__words {
			display: flex;
			flex: 1 1 auto;
			align-items: baseline;
			gap: var(--space-smaller);
			min-width: 0;
			overflow: hidden;
			white-space: nowrap;
		}

		.item-card__client {
			flex-shrink: 0;
			max-width: 70%;
			overflow: hidden;
			text-overflow: ellipsis;
		}

		.item-card__work {
			min-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
		}
	}

	.item-card--pill {
		padding-right: var(--space-small);

		.item-card__client {
			max-width: none;
		}
	}

	.item-card__people--pill {
		margin-top: 0;
	}

	// The list of everything on one date: the time in a column of its own, the name and the work beside it.
	.item-card--row {
		justify-content: center;
		padding: 0 var(--space-small);
		border-radius: var(--radius-base);

		.item-card__list-line {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
		}

		.item-card__list-time {
			display: inline-flex;
			flex: 0 0 56px;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--item-time);
			font-size: 12px;
			font-weight: 500;
			white-space: nowrap;
		}

		.item-card__list-words {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			min-width: 0;
			line-height: 1.25;
		}

		.item-card__client,
		.item-card__work {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		.item-card__work {
			font-size: 11.5px;
		}

		.item-card__chip {
			align-self: center;
		}
	}

	.item-card__badge {
		display: inline-flex;
		flex-shrink: 0;
		align-items: center;
		justify-content: center;
		width: 16px;
		height: 16px;
		border-radius: 999px;
		background-color: var(--color-surface--background--subtle);
		color: var(--color-text--secondary);
		font-size: 10px;
		font-weight: 700;
	}

	.item-card--compact .item-card__work--line .item-card__client {
		font-size: 12px;
	}
</style>
