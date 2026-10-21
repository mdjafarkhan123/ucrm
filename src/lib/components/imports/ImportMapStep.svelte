<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ImportStepCard from './ImportStepCard.svelte';
	import { IMPORT_FIELD_OPTIONS } from '$lib/imports/api';

	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import columnsIcon from '@tabler/icons/outline/columns-3.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	// Generic on purpose: this step is shared by every import wizard (clients, Price Book, opening balances,
	// ...), each with its own field enum. dont_overwrite is optional because an import with no partial-merge
	// concept (opening balances) never sets it -- showOverwriteToggle hides the column that would edit it.
	type ColumnMapping = Record<string, { field: string; dont_overwrite?: boolean }>;

	let {
		headers,
		previewRows,
		mapping = $bindable(),
		errorMessage = '',
		loading = false,
		fieldOptions = IMPORT_FIELD_OPTIONS,
		showOverwriteToggle = true,
		tone = 'client',
		onBack,
		onReview
	}: {
		headers: string[];
		previewRows: Record<string, string>[];
		mapping: ColumnMapping;
		errorMessage?: string;
		loading?: boolean;
		fieldOptions?: { value: string; label: string }[];
		// Some imports (opening balances) have no partial-merge concept -- a match is always a correction, so
		// there is nothing to protect.
		showOverwriteToggle?: boolean;
		/** The import's colour family, for the card header tile. */
		tone?: string;
		onBack: () => void;
		onReview: () => void;
	} = $props();

	const matchedCount = $derived(headers.filter((header) => mapping[header]).length);

	// Up to three real sample values for a column, so the office can confirm a match at a glance.
	function samples(header: string): string {
		const values = previewRows
			.map((row) => (row[header] ?? '').trim())
			.filter((value) => value.length > 0)
			.slice(0, 3);
		return values.length > 0 ? values.join(' · ') : '—';
	}

	// Pick (or clear) the field a column maps to. A field belongs to one column, so choosing it here removes it
	// from any other column that held it -- the same rule the server enforces, surfaced before it can error.
	function setField(header: string, value: string) {
		if (!value) {
			delete mapping[header];
			mapping = { ...mapping };
			return;
		}
		const field = value;
		const next: ColumnMapping = {};
		for (const [key, entry] of Object.entries(mapping)) {
			if (key !== header && entry.field !== field) next[key] = entry;
		}
		next[header] = { field, dont_overwrite: mapping[header]?.dont_overwrite ?? false };
		mapping = next;
	}

	function toggleOverwrite(header: string, checked: boolean) {
		const entry = mapping[header];
		if (!entry) return;
		mapping = { ...mapping, [header]: { ...entry, dont_overwrite: checked } };
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ImportStepCard
	title="Match your columns to our fields"
	hint={`${matchedCount} of your ${headers.length} columns are matched. Check them, and pick a field for any that aren't.`}
	icon={columnsIcon}
	{tone}
	flush
>
	{#if errorMessage}
		<div class="map__error"><Banner type="error">{errorMessage}</Banner></div>
	{/if}

	<div class="map" role="table" aria-label="Your columns and our fields">
		<div class="map__row map__row--head" role="row">
			<span class="map__column" role="columnheader">Your column</span>
			<span class="map__arrow" aria-hidden="true"></span>
			<span class="map__field" role="columnheader">Our field</span>
			{#if showOverwriteToggle}
				<span class="map__overwrite" role="columnheader">When updating</span>
			{/if}
		</div>

		{#each headers as header, index (header)}
			{@const entry = mapping[header]}
			<div class={['map__row', !entry && 'map__row--unmatched']} role="row">
				<div class="map__column" role="cell">
					<b>{header}</b>
					<span class="map__samples">{samples(header)}</span>
					{#if !entry}<span class="map__pick">Pick one</span>{/if}
				</div>
				<span class="map__arrow" aria-hidden="true">{@html arrowRightIcon}</span>
				<div class="map__field" role="cell">
					<span class="field-box" class:field-box--unset={!entry}>
						<span class="field-box__mark" aria-hidden="true">
							{@html entry ? circleCheckIcon : alertIcon}
						</span>
						<select
							value={entry?.field ?? ''}
							aria-label={`Field for the ${header} column`}
							onchange={(event) => setField(header, event.currentTarget.value)}
						>
							<option value="">Don't import this column</option>
							{#each fieldOptions as option (option.value)}
								<option value={option.value}>{option.label}</option>
							{/each}
						</select>
						<span class="field-box__chevron" aria-hidden="true">{@html chevronIcon}</span>
					</span>
				</div>
				{#if showOverwriteToggle}
					<div class={['map__overwrite', !entry && 'map__overwrite--off']} role="cell">
						<Checkbox
							id={`import-keep-${index}`}
							label="Don't overwrite"
							checked={entry?.dont_overwrite ?? false}
							disabled={!entry}
							onchange={(checked) => toggleOverwrite(header, checked)}
						/>
					</div>
				{/if}
			</div>
		{/each}
	</div>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<Button variant="primary" {loading} disabled={matchedCount === 0} onclick={onReview}>
			Review import <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	{/snippet}
</ImportStepCard>

<style lang="scss">
	.map {
		overflow-x: auto;

		&__error {
			padding: var(--space-base) var(--space-medium) 0;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			min-width: 640px;
			padding: var(--space-slim) var(--space-medium);
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				border-bottom: none;
			}

			&--head {
				padding-block: 10px;
				background: var(--color-surface--background--subtle);

				> span {
					color: var(--color-text--secondary);
					font-size: var(--typography--fontSize-small);
					font-weight: 600;
					letter-spacing: calc(var(--typography--letterSpacing-loose) * 1px);
					text-transform: uppercase;
				}
			}

			&--unmatched {
				background: var(--color-warning--surface);
			}
		}

		&__column {
			display: flex;
			flex: 0 0 240px;
			flex-direction: column;
			align-items: flex-start;
			gap: 2px;
			min-width: 0;

			b {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__samples {
			max-width: 100%;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__pick {
			display: inline-flex;
			align-items: center;
			gap: 5px;
			margin-top: 2px;
			padding: 3px 9px;
			border-radius: var(--radius-circle);
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			&::before {
				width: 5px;
				height: 5px;
				border-radius: var(--radius-circle);
				background: var(--color-warning);
				content: '';
			}
		}

		&__arrow {
			display: block;
			flex: 0 0 16px;
			width: 16px;
			color: var(--color-success);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}

			.map__row--unmatched & {
				color: var(--color-warning--onSurface);
			}
		}

		&__field {
			flex: 1 1 auto;
			min-width: 0;
		}

		&__overwrite {
			flex: 0 0 140px;

			&--off {
				opacity: 0.45;
			}
		}
	}

	.field-box {
		position: relative;
		display: flex;
		align-items: center;
		height: 40px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		transition: border-color 0.12s;

		&:hover {
			border-color: var(--color-interactive);
		}
		&:focus-within {
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-focus);
		}

		&__mark,
		&__chevron {
			position: absolute;
			top: 50%;
			display: block;
			transform: translateY(-50%);
			pointer-events: none;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}
		&__mark {
			left: var(--space-slim);
			color: var(--color-success);
		}
		&__chevron {
			right: var(--space-slim);
			color: var(--color-icon--secondary);
		}

		select {
			width: 100%;
			height: 100%;
			padding: 0 36px;
			border: none;
			border-radius: inherit;
			background: transparent;
			color: var(--color-heading);
			font-family: inherit;
			font-size: var(--typography--fontSize-base);
			cursor: pointer;
			appearance: none;

			&:focus-visible {
				outline: none;
			}
		}

		&--unset {
			border: 1.5px solid var(--color-warning);

			.field-box__mark {
				color: var(--color-warning--onSurface);
			}
			select {
				color: var(--color-warning--onSurface);
				font-weight: 600;
			}
		}
	}

	.btn-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
</style>
