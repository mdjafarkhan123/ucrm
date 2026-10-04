<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import SetupField from '$lib/components/setup/SetupField.svelte';
	import { setupListFieldFact } from '$lib/setup/catalogue';
	import { setupFileIds } from '$lib/setup/files';
	import {
		newSetupListRowId,
		setupListCellText,
		setupListRows,
		type SetupListField
	} from '$lib/setup/lists';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// An add-another list for setup (client onboarding A5e), following the MOJ "Add another" pattern: each
	// entry is a numbered card of the boxes Jafar chose, with its own Remove, and one button adds the next.
	// A list allowed one row is a plain form — one person, one address — with no cards at all. Every box is a
	// SetupField of its own type, so it looks and checks exactly like a question of that type.
	//
	// It reads and writes the answer as JSON text, so the page saves it like any other answer. An entry still
	// completely empty stays on screen but out of the answer, so adding one never trips "fill it in".
	let {
		id,
		factKey,
		label,
		fields,
		maxRows,
		value = $bindable(''),
		error = '',
		currency = null,
		country = null,
		userId = null,
		onedit,
		oncommit
	}: {
		id: string;
		factKey: string;
		label: string;
		fields: SetupListField[];
		maxRows: number;
		value?: string;
		error?: string;
		currency?: string | null;
		country?: string | null;
		userId?: string | null;
		onedit: () => void;
		oncommit: () => void;
	} = $props();

	type Row = { id: string; values: Record<string, string> };

	const form = $derived(maxRows === 1);

	// A file box shows as a photo or file answer, whose text is a list of ids; it holds the one id.
	function toText(field: SetupListField, stored: unknown): string {
		const text = setupListCellText(stored);
		return field.kind === 'file' ? (text ? JSON.stringify([text]) : '') : text;
	}

	function fromText(field: SetupListField, text: string): string {
		return field.kind === 'file' ? (setupFileIds(text)[0] ?? '') : text;
	}

	const blank = (): Row => ({ id: newSetupListRowId(), values: {} });

	// The entries as typed. They follow the answer only when it changes from outside, such as when the page loads.
	let rows = $state<Row[]>([]);
	let written: string | null = null;
	$effect.pre(() => {
		if (value === written) return;
		written = value;
		const loaded = setupListRows(value).map((row) => ({
			id: row.id,
			values: Object.fromEntries(
				fields.map((field) => [field.key, toText(field, row.values[field.key])])
			)
		}));
		// An unanswered list starts with one empty entry to fill in.
		rows = loaded.length ? loaded : [blank()];
	});

	const filled = (row: Row) => Object.values(row.values).some((text) => text.trim());

	function write() {
		const kept = rows.filter(filled).map((row) => ({
			id: row.id,
			values: Object.fromEntries(
				fields.flatMap((field) => {
					const text = fromText(field, row.values[field.key] ?? '').trim();
					return text ? [[field.key, text]] : [];
				})
			)
		}));
		const next = kept.length ? JSON.stringify(kept) : '';
		written = next;
		value = next;
	}

	function setCell(row: Row, field: SetupListField, text: string) {
		row.values[field.key] = text;
		write();
	}

	// What an entry is called on its card: its first box with words in it, so "Roof repair" rather than "2".
	function title(row: Row) {
		for (const field of fields) {
			if (field.kind === 'file' || field.kind === 'yes_no') continue;
			const text = row.values[field.key]?.trim();
			if (text) return field.options?.find((choice) => choice.value === text)?.label ?? text;
		}
		return null;
	}

	function add() {
		rows.push(blank());
		// The new entry's first box takes the cursor, as a person adding one expects.
		const rowId = rows[rows.length - 1].id;
		requestAnimationFrame(() =>
			document
				.getElementById(`${id}-${rowId}`)
				?.querySelector<HTMLElement>('input, textarea, button')
				?.focus()
		);
	}

	function remove(index: number) {
		rows.splice(index, 1);
		if (rows.length === 0) rows.push(blank());
		write();
		oncommit();
	}

	const factFor = (row: Row, field: SetupListField) =>
		setupListFieldFact(field, `${factKey}.${row.id}.${field.key}`);
</script>

{#snippet boxes(row: Row)}
	<div class="setup-list__boxes">
		{#each fields as field (field.key)}
			<div
				class={[
					'setup-list__box',
					field.kind === 'longtext' || field.kind === 'file' ? 'setup-list__box--wide' : ''
				]}
			>
				<SetupField
					fact={factFor(row, field)}
					bind:value={() => row.values[field.key] ?? '', (text) => setCell(row, field, text)}
					{currency}
					{country}
					{userId}
					fileTarget={{ factKey, fieldKey: field.key }}
					{onedit}
					{oncommit}
				/>
			</div>
		{/each}
	</div>
{/snippet}

<!-- eslint-disable svelte/no-at-html-tags -->
<fieldset class="setup-list" aria-describedby={error ? `${id}-error` : undefined}>
	<legend class="setup-list__label">{label}</legend>
	{#if form}
		<div class="setup-list__form" id={`${id}-${rows[0].id}`}>{@render boxes(rows[0])}</div>
	{:else}
		<ol class="setup-list__rows">
			{#each rows as row, index (row.id)}
				<li class="setup-list__row" id={`${id}-${row.id}`}>
					<div class="setup-list__row-head">
						<span class="setup-list__number" aria-hidden="true">{index + 1}</span>
						<span class="setup-list__title">{title(row) ?? 'New entry'}</span>
						<button
							type="button"
							class="setup-list__remove"
							aria-label={`Remove entry ${index + 1}${title(row) ? `, ${title(row)}` : ''}`}
							onclick={() => remove(index)}
							><span aria-hidden="true">{@html trashIcon}</span>Remove</button
						>
					</div>
					{@render boxes(row)}
				</li>
			{/each}
		</ol>
		{#if rows.length < maxRows}
			<div>
				<Button size="small" variant="secondary" onclick={add}
					><span class="setup-list__button-icon" aria-hidden="true">{@html plusIcon}</span>Add
					another</Button
				>
			</div>
		{:else}
			<p class="setup-list__note">That’s the most this list takes ({maxRows}).</p>
		{/if}
	{/if}
	{#if error}
		<p class="setup-list__error" id={`${id}-error`} role="alert">{error}</p>
	{/if}
</fieldset>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		margin: 0;
		padding: 0;
		border: 0;

		&__label {
			margin-bottom: var(--space-small);
			padding: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__rows {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row,
		&__form {
			min-width: 0;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__row-head {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-bottom: var(--space-base);
		}

		&__number {
			display: inline-flex;
			flex: none;
			align-items: center;
			justify-content: center;
			width: 2.4rem;
			height: 2.4rem;
			border-radius: 50%;
			background: var(--color-surface--background);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__title {
			flex: 1;
			min-width: 0;
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__remove {
			display: inline-flex;
			flex: none;
			align-items: center;
			gap: var(--space-smaller);
			min-height: 3.6rem;
			padding: 0 var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-text--secondary);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 1.6rem;
				height: 1.6rem;
			}

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-critical);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__boxes {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(22rem, 1fr));
			gap: var(--space-base);
		}

		&__box {
			min-width: 0;

			&--wide {
				grid-column: 1 / -1;
			}
		}

		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 1.6rem;
				height: 1.6rem;
			}
		}

		&__note {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			line-height: var(--typography--lineHeight-base);
		}
	}
</style>
