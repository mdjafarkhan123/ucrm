<script lang="ts">
	import { tick } from 'svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import type { SetupListRow } from '$lib/setup/lists';
	import {
		keptSetupPickIds,
		setupPickIds,
		setupPickInstruction,
		setupPickRowName
	} from '$lib/setup/picks';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';

	// A pick from an earlier list (client onboarding A5f): every row the client added to that list as a
	// checkbox, as in survey tools that carry choices forward. When the question asks for an order, the picked
	// rows then show numbered, each with Move up and Move down — buttons rather than dragging, so a keyboard,
	// a screen reader and a thumb can all do it. The answer is the picked rows' ids as JSON text; nothing
	// picked is an empty answer.
	let {
		id,
		label,
		rows,
		nameKey,
		minChoices,
		maxChoices,
		ordered = false,
		value = $bindable(''),
		invalid = false,
		oncommit
	}: {
		id: string;
		label: string;
		/** The earlier list's rows as they stand now. */
		rows: SetupListRow[];
		/** The box of each row that names it. */
		nameKey?: string;
		minChoices?: number;
		maxChoices?: number;
		ordered?: boolean;
		value?: string;
		invalid?: boolean;
		oncommit: () => void;
	} = $props();

	const names = $derived(
		new Map(rows.map((row, index) => [row.id, setupPickRowName(row, index, nameKey)]))
	);
	// A row since removed from the list is no longer picked.
	const picked = $derived(keptSetupPickIds(setupPickIds(value), rows));
	const full = $derived(maxChoices !== undefined && picked.length >= maxChoices);
	const instruction = $derived(
		setupPickInstruction({ minChoices, maxChoices }, rows.length) +
			(ordered ? ' Then put them in order, most important first.' : '')
	);

	let orderList = $state<HTMLOListElement>();

	function write(next: string[]) {
		value = next.length ? JSON.stringify(next) : '';
		oncommit();
	}

	function choose(rowId: string, checked: boolean) {
		if (!checked) return write(picked.filter((each) => each !== rowId));
		// In order, a new pick goes last; otherwise picks follow the list's own order.
		write(
			ordered
				? [...picked, rowId]
				: rows.map((row) => row.id).filter((each) => each === rowId || picked.includes(each))
		);
	}

	async function move(index: number, by: -1 | 1) {
		const next = [...picked];
		const target = index + by;
		[next[index], next[target]] = [next[target], next[index]];
		write(next);
		// Keep the person's place: the same button on the row they moved, or its other button at an end.
		await tick();
		const buttons = orderList?.querySelectorAll<HTMLButtonElement>(
			`[data-row="${next[target]}"] button`
		);
		const button = buttons?.[by === -1 ? 0 : 1];
		(button && !button.disabled ? button : buttons?.[by === -1 ? 1 : 0])?.focus();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<fieldset class="setup-pick">
	<legend class="setup-pick__label">{label}</legend>
	<p class="setup-pick__limit">{instruction}</p>
	<div class="setup-pick__options">
		{#each rows as row (row.id)}
			{@const checked = picked.includes(row.id)}
			<Checkbox
				id={`${id}-${row.id}`}
				label={names.get(row.id) ?? ''}
				{checked}
				disabled={!checked && full}
				{invalid}
				onchange={(next) => choose(row.id, next)}
			/>
		{/each}
	</div>

	{#if ordered && picked.length > 1}
		<div class="setup-pick__order">
			<p class="setup-pick__order-title" id={`${id}-order`}>Your order</p>
			<ol class="setup-pick__ranks" aria-labelledby={`${id}-order`} bind:this={orderList}>
				{#each picked as rowId, index (rowId)}
					{@const name = names.get(rowId) ?? ''}
					<li class="setup-pick__rank" data-row={rowId}>
						<span class="setup-pick__number" aria-hidden="true">{index + 1}</span>
						<span class="setup-pick__name">{name}</span>
						<button
							type="button"
							class="setup-pick__move"
							aria-label={`Move ${name} up`}
							disabled={index === 0}
							onclick={() => move(index, -1)}>{@html arrowUpIcon}</button
						>
						<button
							type="button"
							class="setup-pick__move"
							aria-label={`Move ${name} down`}
							disabled={index === picked.length - 1}
							onclick={() => move(index, 1)}>{@html arrowDownIcon}</button
						>
					</li>
				{/each}
			</ol>
		</div>
	{/if}
</fieldset>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-pick {
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

		&__limit {
			margin: calc(var(--space-small) * -1) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__options {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
			gap: var(--space-small) var(--space-base);
		}

		&__order {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin-top: var(--space-small);
		}

		&__order-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__ranks {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			list-style: none;
		}

		&__rank {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-smaller) var(--space-small);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__number {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 24px;
			height: 24px;
			border-radius: var(--radius-circle);
			color: var(--color-interactive);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__name {
			flex: 1 1 auto;
			min-width: 0;
			overflow-wrap: anywhere;
			color: var(--color-text);
		}

		// Thumb-sized: setup is often filled in on a phone.
		&__move {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 40px;
			height: 40px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: none;
			cursor: pointer;
			transition: all var(--timing-quick) ease-out;

			&:hover:not(:disabled),
			&:focus-visible:not(:disabled) {
				border-color: var(--color-border--interactive);
				color: var(--color-interactive);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}
</style>
