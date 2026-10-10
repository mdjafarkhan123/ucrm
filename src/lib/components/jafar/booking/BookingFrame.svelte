<script lang="ts">
	import type { Snippet } from 'svelte';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import videoIcon from '@tabler/icons/outline/video.svg?raw';
	import { LOCATION_WORDS, lengthWords, type LocationKind } from '$lib/jafar/booking';

	// Jafar business management E1/E2: the frame every public booking page sits in -- Uplift's mark, then one card.
	// With `meeting`, the card has the meeting's summary on the left and the work on the right; without it, the
	// card is a narrow single column for a finished or closed state.

	type Props = {
		meeting?: {
			name: string;
			host_name: string;
			duration_minutes: number;
			location_kind: LocationKind;
			description?: string | null;
		};
		/** More lines under the meeting's length and how it happens, such as the chosen time. */
		meta?: Snippet;
		children: Snippet;
	};

	let { meeting, meta, children }: Props = $props();
</script>

<main class="booking-frame">
	<div class="booking-frame__brand">
		<span class="booking-frame__brand-mark" aria-hidden="true">U</span>
		Uplift
	</div>

	<section class="booking-frame__card" class:booking-frame__card--narrow={!meeting}>
		{#if meeting}
			<aside class="booking-frame__about">
				<p class="booking-frame__host">{meeting.host_name} · Uplift</p>
				<h1 class="booking-frame__title">{meeting.name}</h1>
				<ul class="booking-frame__meta">
					<li>
						<span aria-hidden="true">{@html clockIcon}</span>{lengthWords(meeting.duration_minutes)}
					</li>
					<li>
						<span aria-hidden="true"
							>{@html meeting.location_kind === 'phone' ? phoneIcon : videoIcon}</span
						>{LOCATION_WORDS[meeting.location_kind]}
					</li>
					{@render meta?.()}
				</ul>
				{#if meeting.description}
					<p class="booking-frame__description">{meeting.description}</p>
				{/if}
			</aside>
			<div class="booking-frame__work">
				{@render children()}
			</div>
		{:else}
			{@render children()}
		{/if}
	</section>
</main>

<style lang="scss">
	.booking-frame {
		min-height: 100vh;
		padding: var(--space-larger) var(--space-base) var(--space-extravagant);
		background: var(--color-surface--background);
		color: var(--color-text);

		@media (max-width: 640px) {
			padding: var(--space-base) var(--space-base) var(--space-largest);
		}
	}

	.booking-frame__brand {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-small);
		margin-bottom: var(--space-large);
		font-weight: 700;
		font-size: var(--typography--fontSize-large);
	}

	.booking-frame__brand-mark {
		display: grid;
		width: 32px;
		height: 32px;
		place-items: center;
		border-radius: var(--radius-small);
		background: var(--color-interactive);
		color: var(--color-surface);
		font-weight: 900;
	}

	.booking-frame__card {
		display: grid;
		grid-template-columns: minmax(240px, 300px) minmax(0, 1fr);
		max-width: 1040px;
		margin: 0 auto;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);

		@media (max-width: 860px) {
			grid-template-columns: 1fr;
		}
	}

	.booking-frame__card--narrow {
		display: block;
		max-width: 560px;
	}

	.booking-frame__about {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-larger) var(--space-large);
		border-right: var(--border-base) solid var(--color-border);

		@media (max-width: 860px) {
			padding: var(--space-large) var(--space-base);
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
		}
	}

	.booking-frame__host {
		margin: 0;
		color: var(--color-text--secondary);
		font-weight: 600;
	}

	.booking-frame__title {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tight);
	}

	.booking-frame__meta {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
		color: var(--color-text--secondary);
		font-weight: 600;

		:global(li) {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
		}

		:global(svg) {
			flex: none;
			width: 1.25rem;
			height: 1.25rem;
		}

		:global(> li > span:first-child) {
			display: inline-flex;
		}
	}

	.booking-frame__description {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
		white-space: pre-line;
	}

	.booking-frame__work {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		padding: var(--space-larger) var(--space-large);

		@media (max-width: 860px) {
			padding: var(--space-large) var(--space-base);
		}
	}
</style>
