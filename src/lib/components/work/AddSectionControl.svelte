<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';

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
				<Button variant="secondary" onclick={() => onAdd(option.id)}>
					{@html option.icon}
					{option.label}
				</Button>
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
	}
</style>
