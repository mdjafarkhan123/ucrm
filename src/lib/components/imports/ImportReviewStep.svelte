<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import ImportStepCard from './ImportStepCard.svelte';
	import type { ReviewSummary } from '$lib/imports/api';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	let {
		summary,
		rowCount,
		errorMessage = '',
		loading = false,
		newLabel = 'New clients',
		itemLabel = 'clients',
		attentionNote = (n: number) =>
			`${n} ${n === 1 ? 'row needs' : 'rows need'} a decision — a shared phone, or a contact that matches two different clients. ${n === 1 ? 'It' : 'They'} won't be imported, and you'll get a file listing ${n === 1 ? 'it' : 'them'} to fix once the import finishes.`,
		safetyNote = 'Importing never emails or texts your clients, and never starts automations, welcome messages, or review requests.',
		tone = 'client',
		newIcon = userPlusIcon,
		onBack,
		onCommit
	}: {
		summary: ReviewSummary;
		rowCount: number;
		errorMessage?: string;
		loading?: boolean;
		newLabel?: string;
		itemLabel?: string;
		attentionNote?: (attentionCount: number) => string;
		safetyNote?: string;
		/** The import's colour family: the card header tile and the "new" count card. */
		tone?: string;
		/** A Tabler icon (raw SVG) for the "new" count card. */
		newIcon?: string;
		onBack: () => void;
		onCommit: () => void;
	} = $props();

	const attention = $derived(summary.hold + summary.error);
	const willImport = $derived(summary.create + summary.update);

	const counts = $derived([
		{ key: 'create', n: summary.create, label: newLabel, icon: newIcon, tone },
		{
			key: 'update',
			n: summary.update,
			label: 'Updates to existing',
			icon: refreshIcon,
			tone: 'informative'
		},
		{ key: 'skip', n: summary.skip, label: 'Duplicates skipped', icon: copyIcon, tone: 'inactive' },
		{
			key: 'attention',
			n: attention,
			label: 'Need your attention',
			icon: alertIcon,
			tone: 'warning'
		}
	]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ImportStepCard
	title="Here's what will happen"
	hint={`Review before anything is saved. ${rowCount} rows in your file.`}
	icon={listCheckIcon}
	{tone}
>
	{#if errorMessage}
		<Banner type="error">{errorMessage}</Banner>
	{/if}

	<div class="counts">
		{#each counts as count (count.key)}
			<div class="count">
				<IconTile icon={count.icon} tone={count.tone} size={32} />
				<span class="count__n">{count.n}</span>
				<span class="count__label">{count.label}</span>
			</div>
		{/each}
	</div>

	{#if attention > 0}
		<Banner type="warning">{attentionNote(attention)}</Banner>
	{/if}

	<Banner type="notice" icon={shieldIcon}><b>Nothing gets sent.</b> {safetyNote}</Banner>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<Button variant="primary" {loading} disabled={willImport === 0} onclick={onCommit}>
			<span class="btn-icon" aria-hidden="true">{@html checkIcon}</span>
			{willImport === 0 ? 'Nothing to import' : `Import ${willImport} ${itemLabel}`}
		</Button>
	{/snippet}
</ImportStepCard>

<style lang="scss">
	.counts {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-slim);
	}

	.count {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 10px;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__n {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-stat);
			font-weight: 700;
			font-variant-numeric: tabular-nums;
			line-height: 1;
		}
		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			font-weight: 500;
		}
	}

	.btn-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	@media (max-width: 640px) {
		.counts {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
</style>
