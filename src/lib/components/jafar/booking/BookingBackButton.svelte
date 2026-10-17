<script lang="ts">
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';

	// Jafar business management E1/E2: the "back a step" link on a public booking page.

	type Props = { label: string; onclick: () => void };

	let { label, onclick }: Props = $props();
</script>

<div class="booking-back">
	<Button variant="quiet" {onclick}>
		<span aria-hidden="true">{@html arrowLeftIcon}</span>
		{label}
	</Button>
</div>

<style lang="scss">
	.booking-back {
		align-self: flex-start;

		span {
			display: inline-flex;
		}
	}
</style>
