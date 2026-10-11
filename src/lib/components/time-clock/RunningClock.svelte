<script lang="ts">
	import TimerElapsed from '$lib/components/time-clock/TimerElapsed.svelte';

	// The running-clock mark: a pulsing dot and the ticking time, on a green pill. Wherever a timer is shown
	// running — a visit's Stop control, the Job's Labor list — it reads the same, so it is recognised at once.
	let { startedAt, offsetMs = 0 }: { startedAt: string; offsetMs?: number } = $props();
</script>

<span class="running-clock">
	<span class="running-clock__pulse" aria-hidden="true"></span>
	<TimerElapsed {startedAt} {offsetMs} />
</span>

<style lang="scss">
	.running-clock {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-smaller) var(--space-small);
		border-radius: var(--radius-base);
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}

	.running-clock__pulse {
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);
		background: var(--color-success);
		animation: running-clock-pulse 1.6s ease-in-out infinite;
	}

	@keyframes running-clock-pulse {
		0%,
		100% {
			opacity: 1;
		}

		50% {
			opacity: 0.35;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.running-clock__pulse {
			animation: none;
		}
	}
</style>
