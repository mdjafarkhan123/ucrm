<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { untrack } from 'svelte';
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import { page } from '$app/state';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import serviceIcon from '@tabler/icons/outline/tool.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import bookIcon from '@tabler/icons/outline/book.svg?raw';
	import laborIcon from '@tabler/icons/outline/helmet.svg?raw';
	import taxIcon from '@tabler/icons/outline/receipt.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import PhotoSlot from '$lib/components/files/PhotoSlot.svelte';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { MAX_ATTACHMENT_SIZE_BYTES } from '$lib/collaboration/attachment-limits';
	import { startFileUpload, finishFileUpload } from '$lib/files/api';
	import { markupPercentFrom, priceFromMarkup } from '$lib/quotes/markup';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import {
		createCatalogItem,
		updateCatalogItem,
		setCatalogItemPhoto,
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
		isLabor: startLabor = false,
		imageFileId = null,
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
		isLabor?: boolean;
		imageFileId?: string | null;
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
	let isLaborDraft = $state(untrack(() => startLabor));
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

	// Settings → Price Book only: the item's one optional photo. A newly picked photo is held here and only
	// uploaded once the item is saved, because the upload has to name the item it belongs to.
	let savedPhotoId = $state<string | null>(untrack(() => imageFileId));
	let photoFile = $state<File | null>(null);
	let photoPreviewUrl = $state('');
	let photoRemoved = $state(false);
	// A new item whose photo failed after the item itself saved: the next press retries only the photo.
	let savedItem = $state<CatalogItem | null>(null);

	const shownPhotoId = $derived(photoRemoved ? null : savedPhotoId);

	function choosePhoto(file: File) {
		error = '';
		if (!file.type.startsWith('image/')) {
			error = 'Only a photo can be added to an item.';
			return;
		}
		if (file.size > MAX_ATTACHMENT_SIZE_BYTES) {
			error = 'That photo is over 25 MB.';
			return;
		}
		if (photoPreviewUrl) URL.revokeObjectURL(photoPreviewUrl);
		photoFile = file;
		photoPreviewUrl = URL.createObjectURL(file);
	}

	function removePhoto() {
		if (photoPreviewUrl) URL.revokeObjectURL(photoPreviewUrl);
		photoFile = null;
		photoPreviewUrl = '';
		photoRemoved = true;
	}

	$effect(() => () => {
		if (photoPreviewUrl) URL.revokeObjectURL(photoPreviewUrl);
	});

	/** Uploads a newly picked photo onto the saved item, or takes a removed one off. */
	async function savePhoto(itemId: string): Promise<string | null> {
		if (photoFile) {
			const started = await startFileUpload(photoFile, {
				originType: 'catalog_item',
				originId: itemId,
				originRole: 'item_photo'
			});
			await uploadAttachmentFile(started.upload_url, photoFile);
			await finishFileUpload(started.file.id);
			await setCatalogItemPhoto(itemId, started.file.id);
			return started.file.id;
		}
		if (photoRemoved && savedPhotoId) {
			await setCatalogItemPhoto(itemId, null);
			return null;
		}
		return photoRemoved ? null : savedPhotoId;
	}

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
			savedPhotoId = item.image_file_id ?? null;
			photoRemoved = false;
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

	const title = $derived(mode === 'update' ? 'Update saved item' : 'New price book item');
	const submitLabel = $derived(
		mode === 'update' ? 'Update item' : savedItem ? 'Save photo' : 'Create item'
	);

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

	const currency = $derived('currencyCode' in page.data ? String(page.data.currencyCode) : 'USD');
	const previewMoney = $derived(new Intl.NumberFormat('en-US', { style: 'currency', currency }));
	const formatPreviewMoney = (minor: number) => previewMoney.format(minor / 100);
	const profit = $derived(unitPriceMinor - unitCostMinor);
	const margin = $derived(unitPriceMinor > 0 ? Math.round((profit / unitPriceMinor) * 100) : 0);
	const costShare = $derived(
		unitPriceMinor > 0 ? Math.max(0, Math.min(100, (unitCostMinor / unitPriceMinor) * 100)) : 0
	);
	function close() {
		if (!saving) onClose();
	}

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
				const updatingId = itemId ?? savedItem?.id;
				const result =
					mode === 'update' || savedItem
						? await updatePriceBookItem(updatingId ?? '', {
								...payload,
								expected_revision: itemRevision ?? savedItem?.revision ?? 0
							})
						: await createPriceBookItem(payload);
				let imageFileId: string | null;
				try {
					imageFileId = await savePhoto(result.id);
				} catch (cause) {
					// The item is saved; only its photo is not. Stay open so the photo can be tried again, and
					// make the next press an update of this item rather than a second copy of it.
					savedItem = {
						id: result.id,
						category,
						name: result.name,
						description: cleanDescription,
						unit_label: payload.unit_label,
						unit_price_minor: unitPriceMinor,
						is_taxable: !exemptFromTax,
						is_labor: isLaborDraft,
						archived_at: null,
						updated_at: new Date().toISOString(),
						revision: result.revision,
						image_file_id: savedPhotoId
					};
					itemRevision = result.revision;
					error = `The item was saved, but its photo was not. ${
						cause instanceof Error ? cause.message : 'The upload failed.'
					} Or remove the photo and save.`;
					return;
				}
				// The commands answer with only id/name/revision. The rest of the saved shape is exactly what
				// was just submitted, so it is rebuilt here rather than round-tripping for it.
				onSaved({
					image_file_id: imageFileId,
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
					unit_label: unitLabelDraft.trim() || null,
					is_labor: category === 'service' && isLaborDraft,
					unit_price_minor: unitPriceMinor,
					...(canViewCost ? { unit_cost_minor: unitCostMinor } : {}),
					is_taxable: !exemptFromTax
				};
				const item =
					(mode === 'update' && itemId) || savedItem
						? await updateCatalogItem(itemId ?? savedItem!.id, input)
						: await createCatalogItem({ unit_cost_minor: 0, ...input });
				try {
					const imageFileId = await savePhoto(item.id);
					onSaved({ ...item, image_file_id: imageFileId });
				} catch (cause) {
					savedItem = item;
					error = `The item was saved, but its photo was not. ${cause instanceof Error ? cause.message : 'Try again, or remove the photo.'}`;
				}
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
<DialogPrimitive.Root
	{open}
	onOpenChange={(next) => {
		if (!next) close();
	}}
>
	<DialogPrimitive.Portal>
		<DialogPrimitive.Overlay class="catalog-modal__overlay" />
		<DialogPrimitive.Content
			class="catalog-modal"
			onEscapeKeydown={(event) => {
				if (saving) event.preventDefault();
			}}
			onInteractOutside={(event) => {
				if (saving) event.preventDefault();
			}}
		>
			<div class="catalog-modal__layout">
				<aside class="catalog-modal__preview">
					<div class="catalog-modal__eyebrow">
						<span aria-hidden="true">{@html eyeIcon}</span>On a quote it looks like
					</div>
					<div class="catalog-modal__line">
						<IconTile icon={category === 'product' ? packageIcon : serviceIcon} tone="feature" size={40} />
						<div>
							<strong>{itemName.trim() || 'Your item name'}</strong>
							<p>{description.trim() || 'The description your customer sees.'}</p>
						</div>
					</div>
					<div>
						<p class="catalog-modal__quiet">Customer pays</p>
						<strong class="catalog-modal__price">{formatPreviewMoney(unitPriceMinor)}</strong><span
							>{unitLabelDraft ? ` per ${unitLabelDraft}` : ''}</span
						>
					</div>
					{#if canViewCost}
						<div
							class="catalog-modal__profit"
							aria-label={`Cost ${formatPreviewMoney(unitCostMinor)}, you keep ${formatPreviewMoney(profit)}`}
						>
							<span
								style:width={`${costShare}%`}
								class:catalog-modal__profit--service={category === 'service'}
							></span>
						</div>
						<div class="catalog-modal__legend">
							<p><span>Unit cost</span><strong>{formatPreviewMoney(unitCostMinor)}</strong></p>
							<p><span>You keep</span><strong>{formatPreviewMoney(profit)} · {margin}%</strong></p>
						</div>
					{/if}
					<div class="catalog-modal__chips">
						{#if !exemptFromTax}<span>{@html taxIcon}Taxed</span
							>{/if}{#if category === 'service' && isLaborDraft}<span>{@html laborIcon}Labor</span
							>{/if}
					</div>
					<p class="catalog-modal__quiet catalog-modal__preview-note">
						Saved quotes keep the price they were given.
					</p>
				</aside>
				<div class="catalog-modal__form">
					<header class="catalog-modal__header">
						<div>
							<DialogPrimitive.Title level={2} class="catalog-modal__title"
								>{title}</DialogPrimitive.Title
							><DialogPrimitive.Description class="catalog-modal__description"
								>Save what you sell often, ready for the next quote or job.</DialogPrimitive.Description
							>
						</div>
						<Button iconOnly variant="secondary" label="Close" disabled={saving} onclick={close}
							>{@html closeIcon}</Button
						>
					</header>
					<div class="catalog-item-dialog">
						{#if managed && loadingItem}<LoadingSkeleton
								variant="card"
								rows={3}
								label="Loading this item"
							/>
						{:else if managed && loadError}<p class="catalog-item-dialog__error" role="alert">
								{loadError}
							</p>
						{:else}
							{#if error}<p class="catalog-item-dialog__error" role="alert">{error}</p>{/if}
							{#if conflict}<div class="catalog-item-dialog__conflict" role="alert">
									{@html alertTriangleIcon}{lastEditor?.name ?? 'Someone else'} changed this item while
									you were editing.<Button
										size="small"
										variant="secondary"
										onclick={reloadLatest}
										loading={loadingItem}>Reload latest</Button
									>
								</div>{/if}
							{#if managed && mode === 'update' && lastEditor}<p class="catalog-item-dialog__note">
									Last changed by {lastEditor.name ?? 'a teammate'}{#if lastEditor.at}
										· <span title={exactTime(lastEditor.at)}>{relativeTime(lastEditor.at)}</span
										>{/if}
								</p>{/if}
							<div class="catalog-item-dialog__types" role="group" aria-label="Item type">
								{#each ['service', 'product'] as kind (kind)}<button
										type="button"
										class="catalog-item-dialog__type catalog-item-dialog__type--{kind}"
										aria-pressed={category === kind}
										disabled={saving}
										onclick={() => {
											category = kind as PricingCategory;
											if (category === 'product') isLaborDraft = false;
										}}
										><IconTile
											icon={kind === 'product' ? packageIcon : serviceIcon}
											tone={kind === 'product' ? 'quote' : 'job'}
										/><span
											><strong>{kind === 'product' ? 'Product' : 'Service'}</strong><small
												>{kind === 'product' ? 'Something you sell' : 'Work you do'}</small
											></span
										><span class="catalog-item-dialog__type-check" aria-hidden="true"
											>{#if category === kind}{@html checkIcon}{/if}</span
										></button
									>{/each}
							</div>
							<Input
								id="catalog-item-name"
								label="Name"
								required
								disabled={saving}
								bind:value={itemName}
								invalid={Boolean(fieldErrors.name)}
								errorMessage={fieldErrors.name ?? ''}
							/>
							<div class="catalog-item-dialog__description">
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
								<div class="catalog-item-dialog__photo">
									<PhotoSlot
										previewUrl={photoPreviewUrl}
										fileId={shownPhotoId}
										disabled={saving}
										label={itemName.trim() || 'Item photo'}
										onChoose={choosePhoto}
										onRemove={removePhoto}
									/>
								</div>
							</div>
							<div class="catalog-item-dialog__price-label">
								Price {#if canViewCost}<small>· markup follows cost and price</small>{/if}
							</div>
							<div
								class="catalog-item-dialog__money"
								class:catalog-item-dialog__money--price-only={!canViewCost}
							>
								{#if canViewCost}<MoneyInput
										id="catalog-item-cost"
										label="Unit cost"
										disabled={saving}
										bind:value={unitCostMinor}
										invalid={Boolean(fieldErrors.unit_cost_minor)}
										errorMessage={fieldErrors.unit_cost_minor ?? ''}
									/><Input
										id="catalog-item-markup"
										label="Markup %"
										inputmode="decimal"
										disabled={saving}
										bind:value={markupDraft}
										onfocus={() => (markupFocused = true)}
										onblur={commitMarkup}
									/>{/if}
								<MoneyInput
									id="catalog-item-price"
									label="Unit price"
									disabled={saving}
									bind:value={unitPriceMinor}
									invalid={Boolean(fieldErrors.unit_price_minor)}
									errorMessage={fieldErrors.unit_price_minor ?? ''}
								/><Input
									id="catalog-item-unit"
									label="Unit"
									placeholder="e.g. hour"
									disabled={saving}
									bind:value={unitLabelDraft}
								/>
							</div>
							<div class="catalog-item-dialog__options">
								{#if category === 'service'}<div>
										<IconTile icon={laborIcon} tone="time" size={32} /><Checkbox
											id="catalog-item-labor"
											label="This is labor"
											description="Track this as work, rather than materials."
											disabled={saving}
											bind:checked={isLaborDraft}
										/>
									</div>{/if}
								<div>
									<IconTile icon={taxIcon} tone="invoice" size={32} /><Checkbox
										id="catalog-item-tax-exempt"
										label="Exempt from tax"
										description="Leave tax off this item."
										disabled={saving}
										bind:checked={exemptFromTax}
									/>
								</div>
							</div>
						{/if}
					</div>
					<footer class="catalog-modal__footer">
						<span>{@html bookIcon}Goes into your price book</span><Button
							variant="secondary"
							disabled={saving}
							onclick={close}>Cancel</Button
						>{#if !(managed && (loadingItem || loadError))}<Button loading={saving} onclick={submit}
								>{@html checkIcon}{submitLabel}</Button
							>{/if}
					</footer>
				</div>
			</div>
		</DialogPrimitive.Content>
	</DialogPrimitive.Portal>
</DialogPrimitive.Root>

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	:global(.catalog-modal__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}
	:global(.catalog-modal) {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		z-index: var(--elevation-modal);
		width: min(940px, calc(100vw - var(--space-large)));
		max-height: calc(100dvh - var(--space-large));
		overflow: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	.catalog-modal {
		&__layout {
			display: grid;
			grid-template-columns: 340px minmax(0, 1fr);
		}
		&__preview {
			display: flex;
			flex-direction: column;
			gap: var(--space-medium);
			padding: 28px;
			color: var(--color-feature--text);
			background:
				radial-gradient(at top right, var(--color-feature--glow), var(--color-feature--glow-end)),
				linear-gradient(135deg, var(--color-feature--start), var(--color-feature--end));
		}
		&__eyebrow {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			text-transform: uppercase;
			color: var(--color-feature--text--secondary);
			span {
				display: grid;
				place-items: center;
				width: 32px;
				height: 32px;
				background: var(--color-feature--subtle);
				border-radius: var(--radius-base);
			}
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__line {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
			padding: 14px;
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-large);
			background: var(--color-feature--subtle);
			overflow-wrap: anywhere;
			strong {
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
			p {
				font-size: var(--typography--fontSize-small);
				line-height: 1.45;
				margin-top: var(--space-smaller);
				color: var(--color-feature--text--secondary);
			}
		}
		&__quiet {
			font-size: var(--typography--fontSize-label);
			color: var(--color-feature--text--secondary);
			line-height: 1.5;
		}
		&__price {
			font-size: var(--typography--fontSize-stat);
			font-weight: 700;
			letter-spacing: -0.8px;
		}
		&__profit {
			display: flex;
			height: 10px;
			background: var(--color-feature--text);
			border-radius: var(--radius-circle);
			overflow: hidden;
			span {
				height: 100%;
				background: var(--color-feature--items);
			}
			span.catalog-modal__profit--service {
				background: var(--color-feature--labor);
			}
		}
		&__legend {
			display: grid;
			gap: 10px;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-feature--subtle);
			p {
				display: flex;
				justify-content: space-between;
				gap: var(--space-small);
				font-size: var(--typography--fontSize-label);
			}
		}
		&__chips {
			display: flex;
			gap: var(--space-small);
			flex-wrap: wrap;
			span {
				display: flex;
				align-items: center;
				gap: 6px;
				height: 28px;
				padding: 0 10px;
				border-radius: var(--radius-circle);
				background: var(--color-feature--text);
				color: var(--color-feature--start);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}
			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&__preview-note {
			margin-top: auto;
		}
		&__form {
			min-width: 0;
			display: flex;
			flex-direction: column;
		}
		&__header {
			display: flex;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-large) var(--space-medium) var(--space-small) 28px;
		}
		&__footer {
			display: flex;
			align-items: center;
			justify-content: flex-end;
			gap: var(--space-small);
			padding: var(--space-base) var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			margin-top: auto;
			> span {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				margin-right: auto;
				font-size: var(--typography--fontSize-label);
				color: var(--color-text--secondary);
				:global(svg) {
					width: 16px;
					height: 16px;
				}
			}
		}
	}
	:global(.catalog-modal__title) {
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		letter-spacing: -0.5px;
		color: var(--color-heading);
		margin: 0;
	}
	:global(.catalog-modal__description) {
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
		margin-top: var(--space-small);
	}
	.catalog-item-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);
		padding: var(--space-base) 28px var(--space-large);
		&__types {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-slim);
		}
		&__type {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface);
			text-align: left;
			cursor: pointer;
			> span:nth-child(2) {
				flex: 1;
				min-width: 0;
			}
			strong {
				display: block;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
			}
			small {
				display: block;
				font-size: var(--typography--fontSize-small);
				color: var(--color-text--secondary);
				margin-top: 2px;
			}
		}
		&__type[aria-pressed='true'] {
			border-color: var(--color-interactive);
			box-shadow:
				var(--shadow-button),
				inset 0 0 0 0.5px var(--color-interactive);
		}
		&__type:hover:not(:disabled) {
			background: var(--color-surface--hover);
		}
		&__type:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&__type:disabled {
			opacity: 0.6;
			cursor: default;
		}
		&__type-check {
			display: grid;
			place-items: center;
			width: 20px;
			height: 20px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-circle);
			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__type[aria-pressed='true'] &__type-check {
			background: var(--color-interactive);
			border-color: var(--color-interactive);
			color: var(--color-text--reverse);
		}
		&__description {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 112px;
			gap: var(--space-slim);
			align-items: end;
		}
		&__photo {
			height: 88px;
		}
		&__price-label {
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			color: var(--color-heading);
			margin-bottom: calc(-1 * var(--space-slim));
			small {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 400;
			}
		}
		&__money {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr)) 90px;
			gap: var(--space-small);
			padding: 10px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface--background--subtle);
		}
		&__money--price-only {
			grid-template-columns: minmax(0, 1fr) 110px;
		}
		&__options {
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			> div {
				display: flex;
				gap: var(--space-slim);
				align-items: center;
				padding: var(--space-slim) var(--space-base);
				+ div {
					border-top: var(--border-base) solid var(--color-border);
				}
			}
		}
		&__error,
		&__conflict {
			padding: var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}
		&__conflict {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__note {
			font-size: var(--typography--fontSize-small);
			color: var(--color-text--secondary);
		}
	}
	@media (max-width: 767px) {
		.catalog-modal__layout {
			grid-template-columns: 1fr;
		}
		.catalog-modal__preview {
			padding: var(--space-medium);
		}
		.catalog-modal__preview-note {
			display: none;
		}
		.catalog-item-dialog {
			padding: var(--space-base);
		}
		.catalog-item-dialog__money {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.catalog-item-dialog__type {
			flex-wrap: wrap;
		}
		.catalog-modal__footer {
			flex-wrap: wrap;
		}
		.catalog-modal__footer > span {
			flex-basis: 100%;
		}
	}

	.catalog-item-dialog__options :global(.checkbox) {
		width: 100%;
		align-items: center;
	}
	.catalog-item-dialog__options :global(.checkbox__content) {
		order: -1;
		flex: 1;
	}
	.catalog-item-dialog__money {
		gap: 0;
		padding: 0;
		overflow: hidden;
		background: var(--color-surface);
	}
	.catalog-item-dialog__money :global(.input) {
		padding: 10px 14px;
		box-sizing: border-box;
		min-width: 0;
	}
	.catalog-item-dialog__money > :global(*) + :global(*) {
		border-left: var(--border-base) solid var(--color-border);
	}
	.catalog-item-dialog__money :global(.input__label) {
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		text-transform: uppercase;
		color: var(--color-text--secondary);
		margin-bottom: var(--space-smaller);
	}
	.catalog-item-dialog__money :global(.input__control) {
		border: 0;
		border-radius: var(--radius-small);
		min-height: 24px;
		background: transparent;
		padding: 0;
	}
	.catalog-item-dialog__money :global(.input__control input) {
		padding: 0;
		font-size: var(--typography--fontSize-large);
		font-weight: 600;
	}
	.catalog-item-dialog__money :global(.money-input__currency) {
		width: auto;
		min-width: 0;
		padding-right: var(--space-smaller);
		border: 0;
		background: transparent;
		color: var(--color-text--secondary);
	}
	.catalog-item-dialog__money :global(.money-input:has(#catalog-item-price)) {
		background: var(--color-surface--background--subtle);
	}
	.catalog-item-dialog__money :global(#catalog-item-price) {
		font-weight: 700;
	}
	@media (max-width: 479px) {
		.catalog-item-dialog__money > :global(*) {
			border-bottom: var(--border-base) solid var(--color-border);
		}
		.catalog-item-dialog__description {
			grid-template-columns: minmax(0, 1fr) 88px;
		}
	}
</style>
