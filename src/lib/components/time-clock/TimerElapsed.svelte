<script lang="ts">
	import { elapsedLabel } from '$lib/time-clock/api';

	// A running timer's clock, ticking once a second. `offsetMs` is how far the server's clock is ahead of
	// this device's, so a phone set to the wrong time still shows how long the timer has really run.
	let { startedAt, offsetMs = 0 }: { startedAt: string; offsetMs?: number } = $props();

	let now = $state(Date.now());

	$effect(() => {
		const tick = setInterval(() => (now = Date.now()), 1000);
		return () => clearInterval(tick);
	});

	const label = $derived(elapsedLabel(startedAt, now + offsetMs));
</script>

<time class="timer-elapsed" datetime={startedAt}>{label}</time>

<style lang="scss">
	.timer-elapsed {
		font-variant-numeric: tabular-nums;
		font-weight: 700;
		color: var(--color-text);
	}
</style>
