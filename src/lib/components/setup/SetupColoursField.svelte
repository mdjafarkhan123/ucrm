<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import { SETUP_COLOURS_MAX } from '$lib/setup/answer-values';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Brand colours for setup (client onboarding A5d): each one a swatch that opens the device's colour picker,
	// beside its code for anyone who knows it, like the brand colour in Settings › Branding. It reads and
	// writes the answer as JSON text — the codes in order — so the page saves it like any other answer.
	let {
		id,
		label,
		labelledby,
		value = $bindable(''),
		invalid = false,
		onedit,
		oncommit
	}: {
		id: string;
		label: string;
		/** The id of the question shown above; the field then draws no legend of its own. */
		labelledby?: string;
		value?: string;
		invalid?: boolean;
		onedit: () => void;
		oncommit: () => void;
	} = $props();

	type Row = { rowId: number; code: string };

	function rowsFrom(raw: string): Row[] {
		try {
			const list = raw ? JSON.parse(raw) : [];
			if (Array.isArray(list))
				return list.map((code, index) => ({ rowId: index, code: String(code) }));
		} catch {
			// An answer of another shape shows as no colours yet.
		}
		return [];
	}

	// The codes as typed, so a half-typed "#1A7" stays in its box. They follow the answer only when it changes
	// from outside, such as when the page loads.
	let rows = $state<Row[]>([]);
	let nextRowId = 0;
	let written: string | null = null;
	$effect.pre(() => {
		if (value === written) return;
		written = value;
		const loaded = rowsFrom(value);
		// An unanswered question starts with one empty colour to fill in.
		rows = loaded.length ? loaded : [{ rowId: 0, code: '' }];
		nextRowId = rows.length;
	});

	const HEX = /^#?[0-9a-f]{6}$/i;
	const withHash = (code: string) => (code.startsWith('#') ? code : `#${code}`);

	function write() {
		const codes = rows.map((row) => row.code.trim()).filter(Boolean);
		// A code typed without its # gets one; anything else is kept as typed so the save can say what is wrong.
		const next = codes.length
			? JSON.stringify(codes.map((code) => (HEX.test(code) ? withHash(code).toUpperCase() : code)))
			: '';
		written = next;
		value = next;
	}

	function pick(row: Row, event: Event) {
		row.code = (event.currentTarget as HTMLInputElement).value.toUpperCase();
		write();
		onedit();
	}

	function type(row: Row, event: Event) {
		row.code = (event.currentTarget as HTMLInputElement).value;
		write();
		onedit();
	}

	function add() {
		rows.push({ rowId: nextRowId++, code: '' });
	}

	function remove(index: number) {
		rows.splice(index, 1);
		write();
		oncommit();
	}

	const swatch = (code: string) => (HEX.test(code.trim()) ? withHash(code.trim()) : '#FFFFFF');
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<fieldset class="setup-colours" aria-labelledby={labelledby}>
	{#if !labelledby}<legend class="setup-colours__label">{label}</legend>{/if}
	{#each rows as row, index (row.rowId)}
		<div class="setup-colours__row">
			<input
				class="setup-colours__swatch"
				type="color"
				aria-label={`Pick colour ${index + 1}`}
				value={swatch(row.code).toLowerCase()}
				oninput={(event) => pick(row, event)}
				onchange={oncommit}
			/>
			<div class="setup-colours__code">
				<Input
					id={`${id}-${row.rowId}`}
					label={`Colour ${index + 1} code`}
					placeholder="#1A73E8"
					maxlength={7}
					autocomplete="off"
					spellcheck="false"
					value={row.code}
					{invalid}
					oninput={(event: Event) => type(row, event)}
					onblur={oncommit}
				/>
			</div>
			<button
				type="button"
				class="setup-colours__remove"
				aria-label={`Remove colour ${index + 1}`}
				onclick={() => remove(index)}>{@html xIcon}</button
			>
		</div>
	{/each}
	{#if rows.length < SETUP_COLOURS_MAX}
		<div>
			<Button size="small" variant="secondary" onclick={add}
				><span class="setup-colours__button-icon" aria-hidden="true">{@html plusIcon}</span>Add a
				colour</Button
			>
		</div>
	{/if}
</fieldset>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-colours {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
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

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__swatch {
			flex: none;
			width: 4.8rem;
			height: 4.8rem;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: none;
			cursor: pointer;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__code {
			flex: 0 1 20rem;
			min-width: 0;
		}

		&__remove {
			display: inline-flex;
			flex: none;
			align-items: center;
			justify-content: center;
			width: 3.6rem;
			height: 3.6rem;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-text--secondary);
			cursor: pointer;

			:global(svg) {
				width: 1.8rem;
				height: 1.8rem;
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

		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 1.6rem;
				height: 1.6rem;
			}
		}
	}
</style>
