<script lang="ts">
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import clipboardListIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import calendarEventIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';

	// The key to the colours and marks on the calendar, so nobody has to guess what a red card or a clipboard
	// means. The note on the right says what the shaded time is, because that differs by view.

	let {
		note,
		shared = false
	}: {
		note: string;
		/** The Day board marks a visit that more than one person is on, so its key says so too. */
		shared?: boolean;
	} = $props();

	const states = [
		{ key: 'scheduled', label: 'Scheduled' },
		{ key: 'in-progress', label: 'In progress' },
		{ key: 'late', label: 'Late' },
		{ key: 'unassigned', label: 'Unassigned' }
	];
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<ul class="schedule-legend" aria-label="What the colours and marks mean">
	{#each states as state (state.key)}
		<li class="schedule-legend__item">
			<span class="schedule-legend__swatch schedule-legend__swatch--{state.key}" aria-hidden="true"
			></span>
			{state.label}
		</li>
	{/each}
	<li class="schedule-legend__item">
		<span class="schedule-legend__icon schedule-legend__icon--done" aria-hidden="true"
			>{@html circleCheckIcon}</span
		>
		Completed
	</li>
	<li class="schedule-legend__divider" aria-hidden="true"></li>
	<li class="schedule-legend__item">
		<span class="schedule-legend__icon" aria-hidden="true">{@html clipboardListIcon}</span>
		Assessment
	</li>
	<li class="schedule-legend__item">
		<span class="schedule-legend__icon" aria-hidden="true">{@html calendarEventIcon}</span>
		Event
	</li>
	{#if shared}
		<li class="schedule-legend__item">
			<span class="schedule-legend__icon" aria-hidden="true">{@html usersIcon}</span>
			Shared visit
		</li>
	{/if}
	<li class="schedule-legend__note">{note}</li>
</ul>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.schedule-legend {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small) 18px;
		margin: 0;
		padding: var(--space-slim) 20px;
		list-style: none;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}

	.schedule-legend__item {
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}

	.schedule-legend__swatch {
		box-sizing: border-box;
		width: 12px;
		height: 12px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: 3.5px;
		background-color: var(--color-surface);

		&--in-progress {
			border: 1.5px solid var(--color-interactive);
		}
		&--late {
			border: 1.5px solid var(--color-critical);
			background-color: var(--color-critical--surface);
		}
		&--unassigned {
			border-color: var(--color-warning--onSurface);
			background-color: var(--color-warning--surface);
		}
	}

	.schedule-legend__icon {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 13px;
			height: 13px;
		}

		&--done {
			color: var(--color-interactive);
		}
	}

	.schedule-legend__divider {
		width: 1px;
		height: 14px;
		background-color: var(--color-border);
	}

	// Pushed to the far end; on a narrow screen it wraps under the key instead.
	.schedule-legend__note {
		margin-left: auto;
	}
</style>
