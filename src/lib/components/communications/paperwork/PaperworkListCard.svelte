<script lang="ts">
	import { resolve } from '$app/paths';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PaperworkFlag from './PaperworkFlag.svelte';
	import { paperworkStatus, setMeta, setTitle } from './paperwork-ui';
	import type { PaperworkSummary } from '$lib/communications/number-paperwork';
	import filesIcon from '@tabler/icons/outline/files.svg?raw';
	import filePlusIcon from '@tabler/icons/outline/file-plus.svg?raw';
	import fileXIcon from '@tabler/icons/outline/file-x.svg?raw';
	import filePenIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';

	// "Your paperwork" on the Number paperwork page (`concept.pen` board `A0URqF`): one row per set, a set that
	// needs a fix first with what is wrong under it, and the page states inside the card.
	let {
		sets,
		loading,
		failed,
		retry
	}: {
		sets: PaperworkSummary[];
		loading: boolean;
		failed: boolean;
		retry: () => void;
	} = $props();

	const ordered = $derived(
		[...sets].sort((a, b) => Number(b.status === 'needs_fix') - Number(a.status === 'needs_fix'))
	);
	const needsFix = $derived(sets.filter((set) => set.status === 'needs_fix').length);
	const hint = $derived(
		loading
			? 'Loading…'
			: failed
				? 'Couldn’t load'
				: sets.length === 0
					? 'Nothing yet'
					: [
							`${sets.length} ${sets.length === 1 ? 'set' : 'sets'}`,
							needsFix ? `${needsFix} ${needsFix === 1 ? 'needs' : 'need'} a fix` : ''
						]
							.filter(Boolean)
							.join(' · ')
	);

	function openHref(set: PaperworkSummary): string {
		return resolve('/(app)/settings/communications/sms/paperwork/[id=uuid]', { id: set.id });
	}

	function fixTitle(set: PaperworkSummary): string {
		const fix = set.first_fix;
		if (!fix) return 'The phone company asked for a change';
		return fix.step === 'documents'
			? `${fix.label} wasn’t accepted`
			: `${fix.label} needs changing`;
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="paperwork-list" aria-labelledby="paperwork-list-title">
	<CardHeader
		id="paperwork-list-title"
		title="Your paperwork"
		{hint}
		icon={filesIcon}
		tone="conversation"
	/>

	{#if loading}
		<div class="paperwork-list__skeleton" aria-busy="true" aria-label="Loading paperwork">
			{#each [180, 150, 200, 130] as width (width)}
				<div class="paperwork-list__skeleton-row">
					<span class="paperwork-list__skeleton-dot"></span>
					<span class="paperwork-list__skeleton-lines">
						<span style:width={`${width}px`}></span>
						<span style:width={`${width - 60}px`}></span>
					</span>
					<span class="paperwork-list__skeleton-pill"></span>
				</div>
			{/each}
		</div>
	{:else if failed}
		<ErrorState
			title="Paperwork couldn’t load"
			description="We couldn’t reach the phone company just now. Your paperwork is safe."
			{retry}
		/>
	{:else if sets.length === 0}
		<EmptyState
			title="No paperwork yet"
			description="Most countries outside the US and Canada ask for it before you can buy a texting number there."
			icon={filesIcon}
			tone="conversation"
		>
			{#snippet action()}
				<Button href={resolve('/(app)/settings/communications/sms/paperwork/new')}>
					<span aria-hidden="true">{@html filePlusIcon}</span>
					New paperwork
				</Button>
			{/snippet}
		</EmptyState>
	{:else}
		<div class="paperwork-list__head" aria-hidden="true">
			<span>Country and kind</span>
			<span>Numbers</span>
			<span>Status</span>
			<span></span>
		</div>
		<ul class="paperwork-list__rows">
			{#each ordered as set (set.id)}
				{@const status = paperworkStatus(set.status)}
				<li
					class={[
						'paperwork-list__item',
						set.status === 'needs_fix' && 'paperwork-list__item--fix'
					]}
				>
					<a class="paperwork-list__row" href={openHref(set)}>
						<PaperworkFlag code={set.country_code} />
						<span class="paperwork-list__name">
							<strong>{setTitle(set)}</strong>
							<span>{setMeta(set)}</span>
						</span>
						<span class="paperwork-list__numbers">
							{#if set.numbers.length}
								<span class="paperwork-list__number-icon" aria-hidden="true">{@html phoneIcon}</span
								>
								<span class="paperwork-list__number">
									{set.numbers[0]}{set.numbers.length > 1 ? ` +${set.numbers.length - 1}` : ''}
								</span>
							{:else}
								<span class="paperwork-list__none-icon" aria-hidden="true"
									>{@html hourglassIcon}</span
								>
								<span class="paperwork-list__none">None yet</span>
							{/if}
						</span>
						<span class="paperwork-list__status">
							<StatusBadge status={status.tone}>{status.label}</StatusBadge>
						</span>
						<span class="paperwork-list__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
					</a>
					{#if set.status === 'needs_fix'}
						<div class="paperwork-list__fix">
							<IconTile icon={fileXIcon} tone="critical" size={32} />
							<span class="paperwork-list__fix-copy">
								<strong>{fixTitle(set)}</strong>
								<span>{set.first_fix?.reason ?? set.failure_reason ?? ''}</span>
							</span>
							<Button variant="secondary" size="small" href={`${openHref(set)}?step=${set.first_fix?.step ?? 'details'}`}>
								<span aria-hidden="true">{@html filePenIcon}</span>
								Fix and send again
							</Button>
						</div>
					{/if}
				</li>
			{/each}
		</ul>
		<p class="paperwork-list__foot">
			<span aria-hidden="true">{@html infoIcon}</span>
			US and Canadian numbers need no paperwork to buy. They need a texting registration instead, in Phone
			&amp; SMS.
		</p>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-list {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__head,
		&__row {
			display: grid;
			grid-template-columns: 32px minmax(0, 1fr) 140px 130px 16px;
			align-items: center;
			column-gap: var(--space-slim);
		}

		&__head {
			padding: 10px var(--space-medium);
			border-bottom: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;

			span:first-child {
				grid-column: 1 / 3;
				padding-left: calc(32px + var(--space-slim));
			}
		}

		&__rows {
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item + &__item {
			border-top: var(--border-base) solid var(--color-border);
		}

		&__row {
			padding: 14px var(--space-medium);
			color: inherit;
			text-decoration: none;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:active {
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: -2px;
			}
		}

		&__name {
			display: grid;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}

		&__numbers {
			display: flex;
			align-items: center;
			gap: 6px;
			font-size: var(--typography--fontSize-smaller);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__number-icon {
			color: var(--color-conversation);
		}

		&__number {
			color: var(--color-heading);
			font-weight: 500;
		}

		&__none-icon,
		&__none {
			color: var(--color-text--secondary);
		}

		&__chevron {
			color: var(--color-icon--secondary);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__item--fix {
			padding-bottom: var(--space-base);
			background: var(--color-critical--surface);

			.paperwork-list__row:hover {
				background: transparent;
			}

			.paperwork-list__name span {
				color: var(--color-critical--onSurface);
			}
		}

		&__fix {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			margin: 0 var(--space-medium);
			padding: var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-critical--surface-edge);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__fix-copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				line-height: var(--typography--lineHeight-large);
			}
		}

		&__foot {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;

			span {
				flex: none;
				color: var(--color-informative);
			}

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__skeleton {
			display: grid;
			gap: var(--space-medium);
			padding: var(--space-large) var(--space-medium);
		}

		&__skeleton-row {
			display: flex;
			align-items: center;
			gap: var(--space-base);
		}

		&__skeleton-dot,
		&__skeleton-lines span,
		&__skeleton-pill {
			background: var(--color-surface--background);
		}

		&__skeleton-dot {
			flex: none;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-circle);
		}

		&__skeleton-lines {
			display: grid;
			flex: 1;
			gap: var(--space-small);

			span {
				height: 10px;
				border-radius: var(--radius-circle);
			}

			span + span {
				height: 8px;
				background: var(--color-surface--background--subtle);
			}
		}

		&__skeleton-pill {
			width: 56px;
			height: 20px;
			border-radius: var(--radius-circle);
		}
	}
</style>
