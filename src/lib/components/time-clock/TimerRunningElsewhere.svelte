<script lang="ts">
	import { resolve } from '$app/paths';
	import type { WorkRunningTimer } from '$lib/time-clock/api';

	// Only one visit or Assessment timer runs at a time. Rather than offer a Start that can only be refused, say
	// where the running one is so the person can go and stop it.
	let { timer }: { timer: WorkRunningTimer } = $props();
</script>

<p class="timer-elsewhere">
	Your timer is running on
	{#if timer.kind === 'visit'}
		<a href={resolve('/(app)/jobs/[id=uuid]', { id: timer.job_id })}>
			{timer.job_number ? `Job #${timer.job_number}` : 'another job'}</a
		>.
	{:else if timer.request_id}
		<a href={resolve('/(app)/requests/[id=uuid]', { id: timer.request_id })}>an assessment</a>.
	{:else}
		an assessment.
	{/if}
	Stop it there to start another.
</p>

<style lang="scss">
	.timer-elsewhere {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);

		a {
			color: var(--color-interactive--subtle);
			font-weight: 700;

			&:hover {
				color: var(--color-interactive--subtle--hover);
			}

			&:focus-visible {
				outline: 2px solid var(--color-interactive--subtle);
				outline-offset: 2px;
				border-radius: var(--radius-small);
			}
		}
	}
</style>
