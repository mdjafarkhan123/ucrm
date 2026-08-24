<script lang="ts">
	export type AddSectionOption = {
		id: string;
		label: string;
		icon: string;
	};

	let {
		options,
		onAdd,
		label = 'Add section'
	}: {
		options: AddSectionOption[];
		onAdd: (id: string) => void;
		label?: string;
	} = $props();
</script>

{#if options.length > 0}
	<div class="add-section-control">
		<p class="add-section-control__label">{label}</p>
		<div class="add-section-control__actions">
			{#each options as option (option.id)}
				<button type="button" class="add-section-control__button" onclick={() => onAdd(option.id)}>
					<span aria-hidden="true">{@html option.icon}</span>
					{option.label}
				</button>
			{/each}
		</div>
	</div>
{/if}

<style lang="scss">
	.add-section-control {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding-block: var(--space-small);

		&__label {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__button {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 36px;
			padding: var(--space-smaller) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: var(--color-surface);
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			&:hover {
				border-color: var(--color-interactive);
				background: var(--color-surface--background);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			span :global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}
		}
	}
</style>
