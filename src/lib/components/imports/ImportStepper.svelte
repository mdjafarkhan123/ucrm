<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import columnsIcon from '@tabler/icons/outline/columns-3.svg?raw';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
	import flagIcon from '@tabler/icons/outline/flag.svg?raw';

	// Display-only progress rail for the import wizard. It never navigates: a real import carries server state
	// (an uploaded batch, a saved mapping), so moving between steps is owned by the wizard's own Back/Continue
	// buttons, not by clicking a rail label out of order.
	let { current }: { current: number } = $props();

	const steps = [
		{ n: 1, title: 'Upload', hint: 'Pick your file', icon: uploadIcon },
		{ n: 2, title: 'Map columns', hint: 'Match your fields', icon: columnsIcon },
		{ n: 3, title: 'Review', hint: 'Check before import', icon: listCheckIcon },
		{ n: 4, title: 'Done', hint: 'Results', icon: flagIcon }
	];
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ol class="import-stepper" aria-label="Import steps">
	{#each steps as step, index (step.n)}
		{@const state = step.n < current ? 'done' : step.n === current ? 'active' : 'upcoming'}
		{#if index > 0}
			<li
				class={['import-stepper__line', step.n <= current && 'import-stepper__line--done']}
				aria-hidden="true"
			></li>
		{/if}
		<li
			class="import-stepper__step import-stepper__step--{state}"
			aria-current={state === 'active' ? 'step' : undefined}
		>
			<span class="import-stepper__tile" aria-hidden="true">
				{@html state === 'done' ? checkIcon : step.icon}
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
		align-items: center;
		gap: var(--space-slim);
		margin: 0;
		padding: 14px var(--space-medium);
		list-style: none;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__step {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-small);
		}

		&__line {
			flex: 1 1 24px;
			min-width: 12px;
			height: 2px;
			border-radius: var(--radius-circle);
			background: var(--color-border);

			&--done {
				background: var(--color-success);
			}
		}

		&__tile {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			.import-stepper__step--done & {
				border-color: var(--color-success--surface-edge);
				background: var(--color-success--surface);
				color: var(--color-success);
			}
			.import-stepper__step--active & {
				border-color: transparent;
				background: var(--color-interactive);
				color: var(--color-text--reverse);
			}
		}

		&__label {
			display: flex;
			flex-direction: column;
			min-width: 0;
			line-height: var(--typography--lineHeight-tight);

			b {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				white-space: nowrap;
			}

			.import-stepper__step--active & b {
				font-weight: 700;
			}
			.import-stepper__step--upcoming & b {
				color: var(--color-text--secondary);
			}
		}
	}
</style>
