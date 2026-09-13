<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import { IMPORT_FIELD_OPTIONS } from '$lib/imports/api';

	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// Generic on purpose: this step is shared by every import wizard (clients, Price Book, ...), each with its
	// own field enum. The mapping shape (which column feeds which of our fields, and whether to protect an
	// existing value) is the same regardless of what the fields actually are.
	type ColumnMapping = Record<string, { field: string; dont_overwrite: boolean }>;

	let {
		headers,
		previewRows,
		mapping = $bindable(),
		errorMessage = '',
		loading = false,
		fieldOptions = IMPORT_FIELD_OPTIONS,
		onBack,
		onReview
	}: {
		headers: string[];
		previewRows: Record<string, string>[];
		mapping: ColumnMapping;
		errorMessage?: string;
		loading?: boolean;
		fieldOptions?: { value: string; label: string }[];
		onBack: () => void;
		onReview: () => void;
	} = $props();

	const matchedCount = $derived(headers.filter((header) => mapping[header]).length);

	// Up to three real sample values for a column, so the office can confirm a match at a glance.
	function samples(header: string): string[] {
		const values = previewRows
			.map((row) => (row[header] ?? '').trim())
			.filter((value) => value.length > 0)
			.slice(0, 3);
		return values.length > 0 ? values : ['—'];
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
<section class="panel">
	<header class="panel__head">
		<h2>Match your columns to our fields</h2>
		<p>
			{matchedCount} of your {headers.length} columns are matched. Check them, and pick a field for any
			that aren't.
		</p>
	</header>

	<div class="panel__body">
		{#if errorMessage}
			<p class="form-error" role="alert">{@html alertIcon}<span>{errorMessage}</span></p>
		{/if}

		<div class="table-scroll">
			<table>
				<thead>
					<tr>
						<th>Your column</th>
						<th>Sample from your file</th>
						<th>Matched</th>
						<th>Our field</th>
						<th>When updating</th>
					</tr>
				</thead>
				<tbody>
					{#each headers as header (header)}
						{@const entry = mapping[header]}
						<tr>
							<td class="col-head">{header}</td>
							<td class="samples">
								{#each samples(header) as sample, index (index)}
									{sample}<br />
								{/each}
							</td>
							<td>
								{#if entry}
									<span class="pill pill--ok">{@html checkIcon}Matched</span>
								{:else}
									<span class="pill pill--warn">{@html alertIcon}Pick one</span>
								{/if}
							</td>
							<td>
								<select
									class="mini-select"
									class:mini-select--unset={!entry}
									value={entry?.field ?? ''}
									aria-label={`Field for the ${header} column`}
									onchange={(event) => setField(header, event.currentTarget.value)}
								>
									<option value="">Don't import this column</option>
									{#each fieldOptions as option (option.value)}
										<option value={option.value}>{option.label}</option>
									{/each}
								</select>
							</td>
							<td>
								<label class="chk" class:chk--disabled={!entry}>
									<input
										type="checkbox"
										checked={entry?.dont_overwrite ?? false}
										disabled={!entry}
										onchange={(event) => toggleOverwrite(header, event.currentTarget.checked)}
									/>
									Don't overwrite
								</label>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	</div>

	<footer class="panel__foot">
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<Button variant="primary" {loading} disabled={matchedCount === 0} onclick={onReview}>
			Review import <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	</footer>
</section>

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			padding: var(--space-large);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}

	.form-error {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		margin: 0 0 var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);

		:global(svg) {
			flex: none;
			width: 18px;
			height: 18px;
			margin-top: 1px;
		}
	}

	.table-scroll {
		overflow-x: auto;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--typography--fontSize-base);
		min-width: 720px;
	}

	thead th {
		text-align: left;
		font-weight: 600;
		font-size: var(--typography--fontSize-small);
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
		color: var(--color-text--secondary);
		padding: var(--space-slim) var(--space-base);
		background: var(--color-surface--background--subtle);
		border-bottom: 1px solid var(--color-border);
		white-space: nowrap;
	}

	tbody td {
		padding: var(--space-slim) var(--space-base);
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}
	tbody tr:last-child td {
		border-bottom: none;
	}

	.col-head {
		font-weight: 600;
		color: var(--color-heading);
		white-space: nowrap;
	}
	.samples {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: 1.55;
	}

	.mini-select {
		font-family: inherit;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text);
		background: var(--color-surface);
		border: 1px solid var(--color-border--interactive);
		border-radius: var(--radius-small);
		padding: var(--space-smaller) var(--space-large) var(--space-smaller) var(--space-small);
		appearance: none;
		min-width: 170px;
		background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='%2349646f' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
		background-repeat: no-repeat;
		background-position: right 8px center;
		cursor: pointer;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--unset {
			border-color: var(--color-warning);
			color: var(--color-warning--onSurface);
		}
	}

	.pill {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		white-space: nowrap;

		:global(svg) {
			width: 13px;
			height: 13px;
		}
		&--ok {
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
		}
		&--warn {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}
	}

	.chk {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		cursor: pointer;
		white-space: nowrap;

		input {
			width: 15px;
			height: 15px;
			accent-color: var(--color-interactive);
		}
		&--disabled {
			opacity: 0.5;
			cursor: not-allowed;
		}
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
	}
</style>
