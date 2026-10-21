<script lang="ts">
	import type { Snippet } from 'svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import leafIcon from '@tabler/icons/outline/leaf.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import videoIcon from '@tabler/icons/outline/video.svg?raw';
	import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import { initials } from '$lib/collaboration/format';
	import { LOCATION_WORDS, lengthWords, type LocationKind } from '$lib/jafar/booking';

	// Jafar business management E1/E2: the frame every public booking page sits in -- Uplift's mark, then one card.
	// With `meeting`, the card has the meeting's summary on the left and the work on the right; without it, the
	// card is a narrow single column for a finished or closed state. Look: design skill `layout.md` → Booking page.

	type Props = {
		meeting?: {
			name: string;
			host_name: string;
			duration_minutes: number;
			location_kind: LocationKind;
			description?: string | null;
		};
		/** The time the visitor has chosen, shown as a box under the meeting's facts. */
		chosen?: { when: string; zone: string } | null;
		children: Snippet;
	};

	let { meeting, chosen = null, children }: Props = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="booking-frame">
	<div class="booking-frame__brand">
		<span class="booking-frame__brand-mark" aria-hidden="true">{@html leafIcon}</span>
		Uplift
	</div>

	<section class="booking-frame__card" class:booking-frame__card--narrow={!meeting}>
		{#if meeting}
			<aside class="booking-frame__about">
				<div class="booking-frame__host">
					<span class="booking-frame__avatar" aria-hidden="true">{initials(meeting.host_name)}</span
					>
					<span class="booking-frame__who">
						<b>{meeting.host_name}</b>
						<span>Uplift</span>
					</span>
				</div>
				<div class="booking-frame__intro">
					<h1 class="booking-frame__title">{meeting.name}</h1>
					{#if meeting.description}
						<p class="booking-frame__description">{meeting.description}</p>
					{/if}
				</div>
				<ul class="booking-frame__facts">
					<li>
						<IconTile icon={clockIcon} tone="time" size={32} />
						<span><small>Length</small>{lengthWords(meeting.duration_minutes)}</span>
					</li>
					<li>
						<IconTile
							icon={meeting.location_kind === 'phone' ? phoneIcon : videoIcon}
							tone="conversation"
							size={32}
						/>
						<span><small>How</small>{LOCATION_WORDS[meeting.location_kind]}</span>
					</li>
					{#if chosen}
						<li class="booking-frame__chosen">
							<IconTile icon={calendarCheckIcon} tone="time" size={32} white />
							<span>
								<b>{chosen.when}</b>
								<span class="booking-frame__zone">
									<span aria-hidden="true">{@html worldIcon}</span>{chosen.zone}
								</span>
							</span>
						</li>
					{/if}
				</ul>
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
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 28px;
		min-height: 100vh;
		padding: 40px var(--space-base) var(--space-extravagant);
		background: var(--color-surface--background);
		color: var(--color-text);

		@media (max-width: 640px) {
			padding: var(--space-base) var(--space-base) var(--space-largest);
		}
	}

	.booking-frame__brand {
		display: flex;
		align-items: center;
		gap: 10px;
		color: var(--color-heading);
		font-size: 18px;
		font-weight: 700;
	}

	.booking-frame__brand-mark {
		display: grid;
		width: 32px;
		height: 32px;
		place-items: center;
		border-radius: 9px;
		background: var(--color-interactive);
		color: var(--color-surface);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.booking-frame__card {
		display: grid;
		grid-template-columns: 340px minmax(0, 1fr);
		width: 100%;
		max-width: 1080px;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-larger);
		background: var(--color-surface);
		box-shadow: 0 8px 24px color-mix(in srgb, var(--color-heading) 6%, transparent);

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
		gap: var(--space-large);
		padding: var(--space-larger) 28px;
		border-right: var(--border-base) solid var(--color-border);

		@media (max-width: 860px) {
			padding: var(--space-large) var(--space-base);
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
		}
	}

	.booking-frame__host {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.booking-frame__avatar {
		display: grid;
		flex: none;
		width: 44px;
		height: 44px;
		place-items: center;
		border: var(--border-base) solid var(--color-time--surface-edge);
		border-radius: var(--radius-circle);
		background: var(--color-time--surface);
		color: var(--color-time--onSurface);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	.booking-frame__who {
		display: flex;
		flex-direction: column;
		gap: 2px;

		b {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.booking-frame__intro {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.booking-frame__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-display);
		font-weight: 700;
		letter-spacing: -0.6px;
		line-height: var(--typography--lineHeight-tight);
	}

	.booking-frame__description {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-larger);
		white-space: pre-line;
	}

	.booking-frame__facts {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		margin: 0;
		padding: var(--space-medium) 0 0;
		border-top: var(--border-base) solid var(--color-border);
		list-style: none;

		> li {
			display: flex;
			align-items: center;
			gap: var(--space-slim);

			> span {
				display: flex;
				flex-direction: column;
				gap: 2px;
				min-width: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		small {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
	}

	.booking-frame__facts > li.booking-frame__chosen {
		padding: var(--space-slim) 14px;
		border: var(--border-base) solid var(--color-time--surface-edge);
		border-radius: 12px;
		background: var(--color-time--surface);

		> span {
			color: var(--color-time--onSurface);
			line-height: 1.4;
		}
	}

	.booking-frame__zone {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-size: var(--typography--fontSize-small);
		font-weight: 400;

		:global(svg) {
			display: block;
			width: 12px;
			height: 12px;
		}
	}

	.booking-frame__work {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		min-width: 0;
		padding: var(--space-larger) var(--space-larger) 28px;

		@media (max-width: 860px) {
			padding: var(--space-large) var(--space-base);
		}
	}
</style>
