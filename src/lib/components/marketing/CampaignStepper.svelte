<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// Display-only progress rail for the campaign journey (blueprint §8) -- same contract as
	// ImportStepper: it never navigates. The draft lives in local state across all five steps and only
	// Save draft or Back/Continue changes it, so a click on the rail itself does nothing.
	let { current }: { current: number } = $props();

	const steps = [
		{ n: 1, title: 'Goal', hint: 'Why this campaign' },
		{ n: 2, title: 'Customers', hint: 'Who receives it' },
		{ n: 3, title: 'Email', hint: 'Build the message' },
		{ n: 4, title: 'Delivery', hint: 'When it sends' },
		{ n: 5, title: 'Review', hint: 'Check and launch' }
	];
</script>

<ol class="campaign-stepper" aria-label="Campaign steps">
	{#each steps as step (step.n)}
		{@const state = step.n < current ? 'done' : step.n === current ? 'active' : 'upcoming'}
		<li
			class="campaign-stepper__step campaign-stepper__step--{state}"
			aria-current={state === 'active' ? 'step' : undefined}
		>
			<span class="campaign-stepper__num" aria-hidden="true">
				{#if state === 'done'}
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html checkIcon}
				{:else}
					{step.n}
				{/if}
			</span>
			<span class="campaign-stepper__label">
				<b>{step.title}</b>
				<span>{step.hint}</span>
			</span>
		</li>
	{/each}
</ol>

<style lang="scss">
	.campaign-stepper {
		display: flex;
		gap: var(--space-small);
		margin: 0 0 var(--space-large);
		padding: 0;
		list-style: none;
		flex-wrap: wrap;

		&__step {
			flex: 1 1 150px;
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			background: var(--color-surface);
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
			padding: var(--space-slim) var(--space-base);

			&--active {
				border-color: var(--color-interactive);
				box-shadow: 0 0 0 1px var(--color-interactive);
			}
		}

		&__num {
			flex: none;
			width: 26px;
			height: 26px;
			border-radius: var(--radius-circle);
			display: grid;
			place-items: center;
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			border: 1px solid var(--color-border);

			:global(svg) {
				width: 15px;
				height: 15px;
			}

			.campaign-stepper__step--done & {
				background: var(--color-success--surface);
				color: var(--color-success--onSurface);
				border-color: transparent;
			}
			.campaign-stepper__step--active & {
				background: var(--color-interactive);
				color: var(--color-text--reverse);
				border-color: transparent;
			}
		}

		&__label {
			display: flex;
			flex-direction: column;
			line-height: var(--typography--lineHeight-tight);
			min-width: 0;

			b {
				font-family: var(--typography--fontFamily-display);
				font-weight: 600;
				font-size: var(--typography--fontSize-base);
				color: var(--color-heading);
			}
			span {
				font-size: var(--typography--fontSize-small);
				color: var(--color-text--secondary);
			}
		}
	}
</style>
