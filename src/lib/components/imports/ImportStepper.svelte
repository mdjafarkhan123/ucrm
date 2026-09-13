<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// Display-only progress rail for the import wizard. It never navigates: a real import carries server state
	// (an uploaded batch, a saved mapping), so moving between steps is owned by the wizard's own Back/Continue
	// buttons, not by clicking a rail label out of order.
	let { current }: { current: number } = $props();

	const steps = [
		{ n: 1, title: 'Upload', hint: 'Pick your file' },
		{ n: 2, title: 'Map columns', hint: 'Match your fields' },
		{ n: 3, title: 'Review', hint: 'Check before import' },
		{ n: 4, title: 'Done', hint: 'Results' }
	];
</script>

<ol class="import-stepper" aria-label="Import steps">
	{#each steps as step (step.n)}
		{@const state = step.n < current ? 'done' : step.n === current ? 'active' : 'upcoming'}
		<li
			class="import-stepper__step import-stepper__step--{state}"
			aria-current={state === 'active' ? 'step' : undefined}
		>
			<span class="import-stepper__num" aria-hidden="true">
				{#if state === 'done'}
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html checkIcon}
				{:else}
					{step.n}
				{/if}
			</span>
			<span class="import-stepper__label">
				<b>{step.title}</b>
				<span>{step.hint}</span>
			</span>
		</li>
	{/each}
</ol>

<style lang="scss">
	.import-stepper {
		display: flex;
		gap: var(--space-small);
		margin: 0 0 var(--space-large);
		padding: 0;
		list-style: none;
		flex-wrap: wrap;

		&__step {
			flex: 1 1 180px;
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

			.import-stepper__step--done & {
				background: var(--color-success--surface);
				color: var(--color-success--onSurface);
				border-color: transparent;
			}
			.import-stepper__step--active & {
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
