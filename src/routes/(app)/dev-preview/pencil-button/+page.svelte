<script lang="ts">
	// TEMPORARY preview for PencilButton, so Jafar can eyeball every size and state before it spreads
	// across the app. Delete once the component is settled.
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';

	let clicks = $state(0);
</script>

<svelte:head><title>Pencil button preview · Contractor CRM</title></svelte:head>

<PageContainer variant="standard">
	<PageHeader
		eyebrow="QA harness"
		title="Pencil button preview"
		description="The square edit affordance, in both sizes and every state."
	/>

	<Card>
		<div class="preview-stack">
			<SectionBlock title="Sizes" icon={pencilIcon} level={3}>
				<div class="preview-row">
					<span class="preview-row__label">Small, the default</span>
					<PencilButton label="Edit this thing" onclick={() => clicks++} />
					<span class="preview-row__label">Base</span>
					<PencilButton label="Edit this thing" size="base" onclick={() => clicks++} />
				</div>
			</SectionBlock>

			<SectionBlock title="Variations" level={3}>
				<div class="preview-row">
					<span class="preview-row__label">Subtle, the default</span>
					<PencilButton label="Edit quietly" onclick={() => clicks++} />
					<span class="preview-row__label">Work, when editing is the main action</span>
					<PencilButton label="Edit loudly" variation="work" onclick={() => clicks++} />
				</div>
			</SectionBlock>

			<SectionBlock title="Bordered and disabled" level={3}>
				<div class="preview-row">
					<span class="preview-row__label">Secondary keeps its border</span>
					<PencilButton label="Edit on a busy surface" variant="secondary" />
					<span class="preview-row__label">Disabled</span>
					<PencilButton label="Cannot edit this" disabled />
				</div>
			</SectionBlock>

			<SectionBlock title="Beside a heading" level={3}>
				<div class="preview-heading">
					<h4>Riverbend Family Diner</h4>
					<PencilButton label="Edit Riverbend Family Diner" onclick={() => clicks++} />
				</div>
			</SectionBlock>

			<SectionBlock title="At the end of a row" level={3}>
				<ul class="preview-rows">
					{#each ['12 Harbour Road, Savar', '48 Mill Lane, Savar'] as address (address)}
						<li>
							<span>{address}</span>
							<PencilButton label={`Edit ${address}`} onclick={() => clicks++} />
						</li>
					{/each}
				</ul>
			</SectionBlock>

			<p class="preview-count">Clicks so far: {clicks}</p>
		</div>
	</Card>
</PageContainer>

<style lang="scss">
	.preview-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.preview-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-base);

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.preview-heading {
		display: flex;
		align-items: center;
		gap: var(--space-small);

		h4 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
		}
	}

	.preview-rows {
		display: flex;
		flex-direction: column;

		li {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) 0;

			& + li {
				border-top: var(--border-base) solid var(--color-border);
			}
		}
	}

	.preview-count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
