<script lang="ts">
	import TimerElapsed from '$lib/components/time-clock/TimerElapsed.svelte';
	import { LONG_TIMER_MS } from '$lib/time-clock/api';

	// The running-clock mark: a pulsing dot and the ticking time, on an indigo capsule. Wherever a timer is shown
	// running — a visit's Stop control, the Job's Labor list — it reads the same, so it is recognised at once.
	// With `flagLong`, a timer past 12 hours turns amber and says so (plan § Forgotten timers).
	let {
		startedAt,
		offsetMs = 0,
		flagLong = true,
		joined = false
	}: { startedAt: string; offsetMs?: number; flagLong?: boolean; joined?: boolean } = $props();

	let now = $state(Date.now());

	// The flag only needs to notice the 12-hour mark, so it checks twice a minute rather than every second.
	$effect(() => {
		if (!flagLong) return;
		const tick = setInterval(() => (now = Date.now()), 30_000);
		return () => clearInterval(tick);
	});

	const long = $derived(flagLong && now + offsetMs - Date.parse(startedAt) > LONG_TIMER_MS);
</script>

<span class="running-clock" class:running-clock--long={long} class:running-clock--joined={joined}>
	<span class="running-clock__pulse" aria-hidden="true"></span>
	<TimerElapsed {startedAt} {offsetMs} />
	{#if long}<span class="running-clock__flag">Over 12 hours</span>{/if}
</span>

<style lang="scss">
	.running-clock {
		--clock-color: var(--color-time);
		--clock-surface: var(--color-time--surface);
		--clock-text: var(--color-time--onSurface);
		--timer-elapsed-color: var(--clock-text);
		--timer-elapsed-size: var(--typography--fontSize-small);
		display: inline-flex;
		align-items: center;
		gap: 6px;
		min-height: 26px;
		box-sizing: border-box;
		padding: 0 10px 0 6px;
		border-radius: var(--radius-circle);
		background: var(--clock-surface);
		color: var(--clock-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: 1;
		white-space: nowrap;
		&--long {
			--clock-color: var(--color-warning);
			--clock-surface: var(--color-warning--surface);
			--clock-text: var(--color-warning--onSurface);
		}
		&--joined {
			--timer-elapsed-size: var(--typography--fontSize-label);
			height: 32px;
			padding: 0 10px 0 var(--space-small);
			border: 1.5px solid var(--clock-color);
			border-radius: var(--radius-base) 0 0 var(--radius-base);
		}
		&__pulse {
			position: relative;
			display: grid;
			place-items: center;
			width: 14px;
			height: 14px;
			flex-shrink: 0;
			border-radius: var(--radius-circle);
			background: color-mix(in srgb, var(--clock-color) 25%, transparent);
			animation: running-clock-pulse 1.6s ease-in-out infinite;
			&::after {
				content: '';
				width: 6px;
				height: 6px;
				border-radius: var(--radius-circle);
				background: var(--clock-color);
				animation: running-clock-dot 1.6s ease-in-out infinite;
			}
		}
		&__flag {
			font-weight: 600;
			white-space: nowrap;
		}
	}
	@keyframes running-clock-pulse {
		50% {
			background: color-mix(in srgb, var(--clock-color) 10%, transparent);
		}
	}
	@keyframes running-clock-dot {
		50% {
			opacity: 0.5;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.running-clock__pulse,
		.running-clock__pulse::after {
			animation: none;
		}
	}
</style>
