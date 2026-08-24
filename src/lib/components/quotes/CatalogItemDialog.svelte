<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { markupPercentFrom, priceFromMarkup } from '$lib/quotes/markup';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import {
		createCatalogItem,
		updateCatalogItem,
		type CatalogItem,
		type PricingCategory,
		type QuoteWriteError
	} from '$lib/quotes/api';
	import {
		fetchPriceBookItem,
		createPriceBookItem,
		updatePriceBookItem,
		type PriceBookWriteError
	} from '$lib/settings/api';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// Adds a reusable price list item, or updates one, without leaving the line you were typing. This is a
	// child record of its own, so it saves itself the moment the button is pressed — it never waits on the
	// request's own save bar. Whatever comes back is handed to the caller so the line can use it.
	//
	// Updating changes what the next line starts from. Nothing already written down moves: request lines
	// and quote versions keep the copy they were given.
	let {
		open,
		mode = 'create',
		itemId,
		name = '',
		description: startDescription = '',
		category: startCategory = 'service',
		unitLabel = null,
		unitPriceMinor: startPrice = 0,
		unitCostMinor: startCost = 0,
		isTaxable: startTaxable = true,
		canViewCost = true,
		managed = false,
		onSaved,
		onClose
	}: {
		open: boolean;
		/** `update` edits an existing saved item instead of adding a new one. */
		mode?: 'create' | 'update';
		/** The saved item being changed. Required in `update` mode. */
		itemId?: string;
		/** What the line already says, so the form starts where the person left off. Ignored in `managed`
		 * update mode, which loads the current record itself instead of trusting a possibly-stale caller. */
		name?: string;
		description?: string;
		category?: PricingCategory;
		unitLabel?: string | null;
		unitPriceMinor?: number;
		unitCostMinor?: number;
		isTaxable?: boolean;
		/** Cost is internal. Hidden outright from someone who may not see it. */
		canViewCost?: boolean;
		/** Settings → Price Book: adds Unit and Labor, writes through the revision-protected commands, and
		 * shows the last editor with a reload-latest path on a stale save. False is the picker's own
		 * unprotected, instant-save behavior — completely unchanged. */
		managed?: boolean;
		onSaved: (item: CatalogItem) => void;
		onClose: () => void;
	} = $props();

	// Taken once on open; the caller mounts this fresh each time.
	let category = $state<PricingCategory>(untrack(() => startCategory));
	let itemName = $state(untrack(() => name));
	let description = $state(untrack(() => startDescription));
	let unitCostMinor = $state(untrack(() => startCost));
	let unitPriceMinor = $state(untrack(() => startPrice));
	let exemptFromTax = $state(untrack(() => !startTaxable));
	let unitLabelDraft = $state(untrack(() => unitLabel ?? ''));
	let isLaborDraft = $state(false);
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	// Managed update starts empty and loads for real: the row a Settings list cached could already be one
	// edit behind, and the last editor's name only exists server-side.
	let itemRevision = $state<number | null>(null);
	let lastEditor = $state<{ name: string | null; at: string | null } | null>(null);
	let loadingItem = $state(false);
	let loadError = $state('');
	let conflict = $state(false);

	async function loadManagedItem() {
		if (!itemId) return;
		loadingItem = true;
		loadError = '';
		try {
			const item = await fetchPriceBookItem(itemId);
			category = item.category;
			itemName = item.name;
			description = item.description ?? '';
			unitLabelDraft = item.unit_label ?? '';
			isLaborDraft = item.is_labor;
			unitPriceMinor = item.unit_price_minor;
			if (item.unit_cost_minor !== undefined) unitCostMinor = item.unit_cost_minor;
			exemptFromTax = !item.is_taxable;
			itemRevision = item.revision;
			lastEditor = item.last_editor;
			conflict = false;
		} catch {
			loadError = 'This item could not be loaded.';
		} finally {
			loadingItem = false;
		}
	}

	$effect(() => {
		if (managed && mode === 'update') void loadManagedItem();
	});

	const title = $derived(mode === 'update' ? 'Update saved item' : 'Add product or service');
	const submitLabel = $derived(mode === 'update' ? 'Update item' : 'Create');

	// Markup is the middle seat of the money row and is never stored — it is only ever the distance
	// between the cost and the price. It follows them while it is not the field being typed in, the same
	// rule `MoneyInput` uses for its own draft. It stays enabled even with no cost yet, or tabbing from
	// Unit cost would skip straight past it to Unit price.
	let markupDraft = $state('');
	let markupFocused = $state(false);

	$effect(() => {
		const next = markupPercentFrom(unitCostMinor, unitPriceMinor);
		if (!untrack(() => markupFocused)) markupDraft = next;
	});

	function commitMarkup() {
		markupFocused = false;
		const parsed = Number(markupDraft);
		if (markupDraft.trim() && Number.isFinite(parsed) && unitCostMinor > 0) {
			unitPriceMinor = priceFromMarkup(unitCostMinor, parsed);
		}
		markupDraft = markupPercentFrom(unitCostMinor, unitPriceMinor);
	}

	const typeOptions = [
		{ value: 'service', label: 'Service' },
		{ value: 'product', label: 'Product' }
	];

	async function submit() {
		if (saving || (managed && loadingItem)) return;
		error = '';
		fieldErrors = {};
		conflict = false;
		if (itemName.trim().length < 2) {
			fieldErrors = { name: 'Give this item a name.' };
			return;
		}
		saving = true;
		try {
			// Cost is internal: somebody who cannot see it never had a figure to send, so it is left out
			// rather than flattened to zero and silently overwriting whatever the item's real cost is.
			const cleanName = itemName.trim();
			const cleanDescription = description.trim() || null;
			if (managed) {
				const payload = {
					category,
					name: cleanName,
					description: cleanDescription,
					unit_label: unitLabelDraft.trim() || null,
					unit_price_minor: unitPriceMinor,
					unit_cost_minor: canViewCost ? unitCostMinor : 0,
					is_taxable: !exemptFromTax,
					is_labor: isLaborDraft
				};
				const result =
					mode === 'update' && itemId
						? await updatePriceBookItem(itemId, {
								...payload,
								expected_revision: itemRevision ?? 0
							})
						: await createPriceBookItem(payload);
				// The commands answer with only id/name/revision. The rest of the saved shape is exactly what
				// was just submitted, so it is rebuilt here rather than round-tripping for it.
				onSaved({
					id: result.id,
					category,
					name: result.name,
					description: cleanDescription,
					unit_label: payload.unit_label,
					unit_price_minor: unitPriceMinor,
					...(canViewCost ? { unit_cost_minor: unitCostMinor } : {}),
					is_taxable: !exemptFromTax,
					is_labor: isLaborDraft,
					archived_at: null,
					updated_at: new Date().toISOString(),
					revision: result.revision
				});
			} else {
				const input = {
					category,
					name: cleanName,
					description: cleanDescription,
					unit_label: unitLabel,
					unit_price_minor: unitPriceMinor,
					...(canViewCost ? { unit_cost_minor: unitCostMinor } : {}),
					is_taxable: !exemptFromTax
				};
				const item =
					mode === 'update' && itemId
						? await updateCatalogItem(itemId, input)
						: await createCatalogItem({ unit_cost_minor: 0, ...input });
				onSaved(item);
			}
		} catch (cause) {
			const failure = cause as QuoteWriteError | PriceBookWriteError;
			if (managed && failure.reason === 'stale') {
				conflict = true;
			} else {
				fieldErrors = failure.fieldErrors ?? {};
				error = Object.keys(fieldErrors).length ? '' : failure.message;
			}
		} finally {
			saving = false;
		}
	}

	// "Review the latest value" from a stale-save banner: reload what is on the server now, including
	// whatever the other editor changed, and let this person decide whether to keep typing over it.
	async function reloadLatest() {
		await loadManagedItem();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} {title} {onClose}>
	<div class="catalog-item-dialog">
		{#if managed && loadingItem}
			<LoadingSkeleton variant="card" rows={3} label="Loading this item" />
		{:else if managed && loadError}
			<p class="catalog-item-dialog__error" role="alert">{loadError}</p>
		{:else}
			{#if error}<p class="catalog-item-dialog__error" role="alert">{error}</p>{/if}
			{#if conflict}
				<p class="catalog-item-dialog__conflict" role="alert">
					<span aria-hidden="true">{@html alertTriangleIcon}</span>
					{lastEditor?.name ?? 'Someone else'} changed this item while you were editing.
					<button type="button" onclick={() => void reloadLatest()}>Reload latest</button>
					or close to discard your changes.
				</p>
			{/if}
			{#if managed && mode === 'update' && lastEditor}
				<p class="catalog-item-dialog__note">
					Last changed by {lastEditor.name ?? 'a teammate'}
					{#if lastEditor.at}
						· <span title={exactTime(lastEditor.at)}>{relativeTime(lastEditor.at)}</span>
					{/if}
				</p>
			{/if}
			{#if mode === 'update' && !managed}
				<p class="catalog-item-dialog__note">
					This changes what future lines start from. Quotes and requests already written down keep
					the prices they were given.
				</p>
			{/if}

			<SegmentedControl
				label="Item type"
				value={category}
				options={typeOptions}
				disabled={saving}
				onchange={(next) => {
					category = next as PricingCategory;
					if (category === 'product') isLaborDraft = false;
				}}
			/>

			<Input
				id="catalog-item-name"
				label="Name"
				required
				disabled={saving}
				bind:value={itemName}
				invalid={Boolean(fieldErrors.name)}
				errorMessage={fieldErrors.name ?? ''}
			/>

			<Textarea
				id="catalog-item-description"
				label="Description"
				rows={3}
				maxlength={2000}
				showCount={false}
				disabled={saving}
				bind:value={description}
				invalid={Boolean(fieldErrors.description)}
				errorMessage={fieldErrors.description ?? ''}
			/>

			{#if managed}
				<div class="catalog-item-dialog__unit">
					<Input
						id="catalog-item-unit"
						label="Unit (optional)"
						placeholder="e.g. sq ft, hour"
						disabled={saving}
						bind:value={unitLabelDraft}
					/>
					{#if category === 'service'}
						<Checkbox
							id="catalog-item-labor"
							label="This is labor"
							disabled={saving}
							bind:checked={isLaborDraft}
						/>
					{/if}
				</div>
			{/if}

			<div
				class="catalog-item-dialog__money"
				class:catalog-item-dialog__money--price-only={!canViewCost}
			>
				{#if canViewCost}
					<MoneyInput
						id="catalog-item-cost"
						label="Unit cost"
						disabled={saving}
						bind:value={unitCostMinor}
						invalid={Boolean(fieldErrors.unit_cost_minor)}
						errorMessage={fieldErrors.unit_cost_minor ?? ''}
					/>
					<Input
						id="catalog-item-markup"
						label="Markup %"
						inputmode="decimal"
						disabled={saving}
						bind:value={markupDraft}
						onfocus={() => (markupFocused = true)}
						onblur={commitMarkup}
					/>
				{/if}
				<MoneyInput
					id="catalog-item-price"
					label="Unit price"
					disabled={saving}
					bind:value={unitPriceMinor}
					invalid={Boolean(fieldErrors.unit_price_minor)}
					errorMessage={fieldErrors.unit_price_minor ?? ''}
				/>
			</div>

			<Checkbox
				id="catalog-item-tax-exempt"
				label="Exempt from tax"
				disabled={saving}
				bind:checked={exemptFromTax}
			/>
		{/if}

		<div class="catalog-item-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			{#if !(managed && (loadingItem || loadError))}
				<Button variant="primary" loading={saving} onclick={submit}>{submitLabel}</Button>
			{/if}
		</div>
	</div>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.catalog-item-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__conflict {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: var(--space-smaller) var(--space-small);
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				width: 16px;
				height: 16px;
				flex: 0 0 auto;
			}

			button {
				padding: 0;
				border: 0;
				color: inherit;
				background: none;
				font: inherit;
				font-weight: 600;
				text-decoration: underline;
				cursor: pointer;
			}
		}

		&__note {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__unit {
			display: flex;
			align-items: end;
			gap: var(--space-base);
		}

		&__money {
			display: grid;
			gap: var(--space-small);
			grid-template-columns: repeat(3, minmax(0, 1fr));

			&--price-only {
				grid-template-columns: minmax(0, 1fr);
			}
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}
	}
</style>
