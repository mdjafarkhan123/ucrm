<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	export type AddSectionOption = {
		id: string;
		label: string;
		icon: string;
		hint?: string;
	};

	let {
		options,
		onAdd,
		label = 'Add section',
		cards = false,
		tone = 'inactive'
	}: {
		options: AddSectionOption[];
		onAdd: (id: string) => void;
		label?: string;
		cards?: boolean;
		tone?: string;
	} = $props();
</script>

<!-- SVGs below are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->

{#if cards}
	{#each options as option (option.id)}
		<section class="add-section-card" aria-label={option.label}>
			<IconTile icon={option.icon} {tone} size={40} />
			<div class="add-section-card__words">
				<div class="add-section-card__heading">
					<h2>{option.label}</h2>
					<span class="add-section-card__optional">Optional</span>
				</div>
				{#if option.hint}<p>{option.hint}</p>{/if}
			</div>
			<Button variant="secondary" size="small" onclick={() => onAdd(option.id)}>
				<span aria-hidden="true">{@html plusIcon}</span>Add {option.label.toLowerCase()}
			</Button>
		</section>
	{/each}
{:else if options.length > 0}
	<div class="add-section-control">
		<p class="add-section-control__label">{label}</p>
		<div class="add-section-control__actions">
			{#each options as option (option.id)}
				<Button variant="secondary" onclick={() => onAdd(option.id)}>
					{@html option.icon}
					{option.label}
				</Button>
			{/each}
		</div>
	</div>
{/if}

<style lang="scss">
	.add-section-card {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 14px var(--space-medium);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		&__words {
			flex: 1;
			min-width: 0;
			display: grid;
			gap: var(--space-smaller);
		}
		&__heading {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}
		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}
		p {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__optional {
			padding: 2px var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		:global(.button) {
			flex-shrink: 0;
		}
		@media (max-width: 767px) {
			display: grid;
			grid-template-columns: 40px minmax(0, 1fr);
			:global(.button) {
				grid-column: 2;
				justify-self: start;
			}
		}
	}

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
	}
</style>
