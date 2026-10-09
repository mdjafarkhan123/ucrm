<script lang="ts">
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';

	// Jafar business management E1/E2: the "back a step" link on a public booking page.

	type Props = { label: string; onclick: () => void };

	let { label, onclick }: Props = $props();
</script>

<button type="button" class="booking-back" {onclick}>
	<span aria-hidden="true">{@html arrowLeftIcon}</span>
	{label}
</button>

<style lang="scss">
	.booking-back {
		display: inline-flex;
		align-self: flex-start;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-smaller) 0;
		border: 0;
		background: none;
		color: var(--color-interactive);
		font: inherit;
		font-weight: 600;
		cursor: pointer;

		:global(svg) {
			width: 1.125rem;
			height: 1.125rem;
		}

		span {
			display: inline-flex;
		}

		&:hover {
			color: var(--color-interactive--hover);
		}

		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}
</style>
