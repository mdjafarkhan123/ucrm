<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import taskIcon from '@tabler/icons/outline/square-check.svg?raw';
	let { showNow = true }: { showNow?: boolean } = $props();
	const kinds = [
		{ tone: 'job', label: 'Visit', icon: hammerIcon },
		{ tone: 'request', label: 'Assessment', icon: inboxIcon },
		{ tone: 'event', label: 'Event', icon: calendarIcon },
		{ tone: 'task', label: 'Task', icon: taskIcon }
	];
</script>

<ul class="schedule-legend" aria-label="What the colours and marks mean">
	{#each kinds as kind (kind.tone)}<li class="schedule-legend__item">
			<IconTile icon={kind.icon} tone={kind.tone} size={20} />{kind.label}
		</li>{/each}
	<li class="schedule-legend__divider" aria-hidden="true"></li>
	<li><StatusBadge status="critical" size="small">Late</StatusBadge></li>
	<li><StatusBadge status="warning" size="small">Unassigned</StatusBadge></li>
	<li><StatusBadge status="success" size="small">Completed</StatusBadge></li>
	{#if showNow}<li class="schedule-legend__item">
			<span class="schedule-legend__now" aria-hidden="true"></span>Now
		</li>{/if}
</ul>

<style lang="scss">
	.schedule-legend {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small) var(--space-base);
		margin: 0;
		padding: var(--space-slim) var(--space-medium);
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
	.schedule-legend__divider {
		width: var(--border-base);
		height: 20px;
		background: var(--color-border);
	}
	.schedule-legend__now {
		width: 18px;
		height: 2px;
		background: var(--color-interactive);
	}
</style>
