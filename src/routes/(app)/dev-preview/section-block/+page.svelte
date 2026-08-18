<script lang="ts">
	// TEMPORARY preview for SectionBlock, so Jafar can eyeball both the form and non-form renderings
	// before the pattern spreads. Delete once the pattern is settled.
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import chartBarIcon from '@tabler/icons/outline/chart-bar.svg?raw';

	let name = $state('');
</script>

<svelte:head><title>Section block preview · Contractor CRM</title></svelte:head>

<PageContainer variant="standard">
	<PageHeader
		eyebrow="QA harness"
		title="Section block preview"
		description="The same titled block in every combination: on the page background, inside a card, with and without form controls."
	/>

	<h2 class="preview-label">On the page background</h2>
	<div class="preview-stack preview-stack--on-background">
		<SectionBlock title="Work summary" icon={chartBarIcon} level={3}>
			<p>
				A plain block sitting straight on the page. No form controls, so it renders as a section.
			</p>
			<div class="preview-row">
				<Badge status="success">Customer</Badge>
				<Badge status="informative">Lead</Badge>
			</div>
		</SectionBlock>

		<SectionBlock
			title="Attachments"
			icon={paperclipIcon}
			level={3}
			hint="A block with a control on its top border."
		>
			{#snippet actions()}
				<Button variant="secondary" size="small">Add</Button>
			{/snippet}
			<p>Nothing attached yet.</p>
		</SectionBlock>
	</div>

	<h2 class="preview-label">Inside a card</h2>
	<Card>
		<div class="preview-stack">
			<SectionBlock title="Primary details" icon={userIcon} variant="filled" form>
				<Input id="preview-name" label="First name" bind:value={name} />
			</SectionBlock>

			<SectionBlock title="Client address" icon={mapPinIcon} hint="Optional." form>
				<Input id="preview-street" label="Street address 1" />
			</SectionBlock>
		</div>
	</Card>
</PageContainer>

<style lang="scss">
	.preview-label {
		margin: var(--space-larger) 0 var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}

	.preview-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	// The blocks here sit on the page background rather than a card, so the notch has to match it.
	.preview-stack--on-background {
		--section-block-notch: var(--color-surface--background);
	}

	.preview-row {
		display: flex;
		gap: var(--space-small);
	}
</style>
