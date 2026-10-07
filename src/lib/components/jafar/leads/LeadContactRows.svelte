<script lang="ts" module>
	import type { ContactMethodKind } from '$lib/jafar/leads';

	/** One contact detail being typed. `id` marks a saved detail: its type stays fixed, so history that used it
	 *  keeps reading correctly. */
	export type ContactRow = {
		key: number;
		id?: string;
		kind: ContactMethodKind;
		value: string;
		found_at: string;
	};

	let rowKey = 0;
	export function contactRow(fields: Omit<ContactRow, 'key'>): ContactRow {
		rowKey += 1;
		return { key: rowKey, ...fields };
	}

	/** An empty row is the starting prompt, not a detail: it is left out when comparing and saving. */
	export function filledRows(rows: ContactRow[]) {
		return rows.filter((row) => row.id || row.value.trim() || row.found_at.trim());
	}
</script>

<script lang="ts">
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		CONTACT_METHOD_KINDS,
		CONTACT_METHOD_LABELS,
		LEAD_CONTACT_METHODS_MAX
	} from '$lib/jafar/leads';

	// Jafar business management: every way to reach a business, each with where it was found. The add form and
	// editing on the Lead page share these rows.
	let {
		rows = $bindable(),
		idPrefix,
		errorFor
	}: {
		rows: ContactRow[];
		idPrefix: string;
		/** The server's message for one row's field, if any. */
		errorFor: (key: number, field: 'value' | 'found_at') => string;
	} = $props();

	function addRow() {
		if (rows.length >= LEAD_CONTACT_METHODS_MAX) return;
		// A second detail is usually a phone after an email.
		const used = new Set(rows.map((row) => row.kind));
		rows.push(
			contactRow({
				kind: used.has('email') && !used.has('phone') ? 'phone' : 'email',
				value: '',
				found_at: ''
			})
		);
	}

	function removeRow(key: number) {
		rows = rows.filter((row) => row.key !== key);
	}

	const kindOptions = CONTACT_METHOD_KINDS.map((kind) => ({
		value: kind,
		label: CONTACT_METHOD_LABELS[kind]
	}));

	const VALUE_LABELS: Record<ContactMethodKind, string> = {
		email: 'Email address',
		phone: 'Phone number, with country code',
		whatsapp: 'WhatsApp number, with country code',
		instagram: 'Instagram profile or @handle',
		facebook: 'Facebook page link',
		linkedin: 'LinkedIn profile link',
		contact_form: 'Contact form page link',
		other: 'Contact detail'
	};
	const VALUE_TYPES: Partial<Record<ContactMethodKind, string>> = {
		email: 'email',
		phone: 'tel',
		whatsapp: 'tel'
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="lead-contact-rows">
	{#each rows as row, index (row.key)}
		<div class="lead-contact-rows__row">
			<div class="lead-contact-rows__kind">
				<!-- A saved detail keeps its type; to change it, remove it and add the new one. -->
				<Select
					id={`${idPrefix}-kind-${row.key}`}
					label="Type"
					options={kindOptions}
					disabled={Boolean(row.id)}
					bind:value={row.kind}
				/>
			</div>
			<Input
				id={`${idPrefix}-value-${row.key}`}
				label={VALUE_LABELS[row.kind]}
				type={VALUE_TYPES[row.kind] ?? 'text'}
				bind:value={row.value}
				invalid={Boolean(errorFor(row.key, 'value'))}
				errorMessage={errorFor(row.key, 'value')}
				autocomplete="off"
			/>
			<Input
				id={`${idPrefix}-found-${row.key}`}
				label="Where you found it"
				placeholder="Contact page of their website"
				bind:value={row.found_at}
				invalid={Boolean(errorFor(row.key, 'found_at'))}
				errorMessage={errorFor(row.key, 'found_at')}
				autocomplete="off"
			/>
			<button
				type="button"
				class="lead-contact-rows__remove"
				aria-label={`Remove contact detail ${index + 1}`}
				title="Remove"
				onclick={() => removeRow(row.key)}
			>
				<span aria-hidden="true">{@html trashIcon}</span>
			</button>
		</div>
	{/each}

	{#if rows.length < LEAD_CONTACT_METHODS_MAX}
		<div>
			<Button type="button" variant="secondary" size="small" onclick={addRow}>
				<span class="lead-contact-rows__button-icon" aria-hidden="true">{@html plusIcon}</span>Add
				contact detail
			</Button>
		</div>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Sized by its own space, not the screen: the add form's wide column and the Lead page's narrow side card
	// both get the layout that fits.
	.lead-contact-rows {
		container-type: inline-size;
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__row {
			display: grid;
			grid-template-columns: minmax(150px, 0.8fr) minmax(0, 1.3fr) minmax(0, 1.3fr) auto;
			align-items: start;
			gap: var(--space-small);
		}

		&__remove {
			display: grid;
			width: 44px;
			height: 44px;
			place-items: center;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: transparent;
			cursor: pointer;

			&:hover {
				color: var(--color-critical);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}

	@container (max-width: 640px) {
		// In a narrow space each contact detail is its own small card: type and remove on one line, then the fields.
		.lead-contact-rows__row {
			grid-template-columns: minmax(0, 1fr) auto;
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);

			> :global(:not(.lead-contact-rows__kind):not(.lead-contact-rows__remove)) {
				grid-column: 1 / -1;
			}
		}

		.lead-contact-rows__remove {
			grid-row: 1;
			grid-column: 2;
		}
	}
</style>
