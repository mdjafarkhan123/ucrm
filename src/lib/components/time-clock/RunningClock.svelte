<script lang="ts">
	import TimerElapsed from '$lib/components/time-clock/TimerElapsed.svelte';
	import { LONG_TIMER_MS } from '$lib/time-clock/api';

	// The running-clock mark: a pulsing dot and the ticking time, on a green pill. Wherever a timer is shown
	// running — a visit's Stop control, the Job's Labor list — it reads the same, so it is recognised at once.
	// With `flagLong`, a timer past 12 hours turns amber and says so (plan § Forgotten timers).
	let {
		startedAt,
		offsetMs = 0,
		flagLong = false
	}: { startedAt: string; offsetMs?: number; flagLong?: boolean } = $props();

	let now = $state(Date.now());

	// The flag only needs to notice the 12-hour mark, so it checks twice a minute rather than every second.
	$effect(() => {
		if (!flagLong) return;
		const tick = setInterval(() => (now = Date.now()), 30_000);
		return () => clearInterval(tick);
	});

	const long = $derived(flagLong && now + offsetMs - Date.parse(startedAt) > LONG_TIMER_MS);
</script>

<span class="running-clock" class:running-clock--long={long}>
	<span class="running-clock__pulse" aria-hidden="true"></span>
	<TimerElapsed {startedAt} {offsetMs} />
	{#if long}<span class="running-clock__flag">Over 12 hours</span>{/if}
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

		&--long {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}
	}

	.running-clock__pulse {
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);
		background: var(--color-success);
		animation: running-clock-pulse 1.6s ease-in-out infinite;

		.running-clock--long & {
			background: var(--color-warning);
		}
	}

	.running-clock__flag {
		font-weight: 700;
		white-space: nowrap;
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
