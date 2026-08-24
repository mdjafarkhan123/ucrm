<script lang="ts">
	import { onDestroy, tick, untrack, type Snippet } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { flip } from 'svelte/animate';
	import { dragHandleZone, dragHandle } from 'svelte-dnd-action';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import QuantityInput from '$lib/components/forms/QuantityInput.svelte';
	import CatalogItemPicker from './CatalogItemPicker.svelte';
	import CatalogItemDialog from './CatalogItemDialog.svelte';
	import PriceBookDrawer from './PriceBookDrawer.svelte';
	import {
		presignAttachmentUpload,
		uploadAttachmentFile,
		createAttachment,
		deleteAttachment,
		attachmentImageUrl
	} from '$lib/collaboration/api';
	import { createImageThumbnail } from '$lib/collaboration/image-thumbnail';
	import { MAX_ATTACHMENT_SIZE_BYTES } from '$lib/collaboration/attachment-limits';
	import {
		catalogItemsKey,
		fetchCatalogItems,
		type RequestPricingLine,
		type RequestPricingLineInput,
		type PricingCategory,
		type CatalogItem,
		type QuoteWriteError,
		type QuoteLineKind,
		type QuoteSelectionKind
	} from '$lib/quotes/api';
	import { firstLineProblem } from '$lib/quotes/lines';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import bookIcon from '@tabler/icons/outline/book.svg?raw';
	import bookmarkIcon from '@tabler/icons/outline/bookmark.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import requiredIcon from '@tabler/icons/outline/square-check.svg?raw';
	import optionalIcon from '@tabler/icons/outline/checkbox.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import starOffIcon from '@tabler/icons/outline/star-off.svg?raw';
	import taxIcon from '@tabler/icons/outline/receipt-tax.svg?raw';
	import taxOffIcon from '@tabler/icons/outline/receipt-off.svg?raw';
	import gripIcon from '@tabler/icons/outline/grip-vertical.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';

	// One "Products and services" section, matching the real Jobber quote line-item card
	// (jobber-03-quotes.md §8.1): name/qty/price/total on top, description + a photo underneath, drag to
	// reorder once there are two or more lines. There is no separate Labor section — Jobber does not have
	// one on a quote either. Real Jobber Labor comes read-only from time tracking on the Request page, a
	// feature this app does not have yet; a crew's time is priced here as a plain Service line, same as
	// Jobber's own quotes show it.
	//
	// This block knows nothing about which document it is pricing. A request, a saved quote and the new
	// quote form all hand it the same three things — the rows as they stand, the money format, and what to
	// do with a save — so all three price work exactly the same way.
	let {
		lines: savedLines = [],
		quoteChoices = false,
		revision = 0,
		editable = false,
		currencyCode = 'USD',
		locale = 'en-US',
		loading = false,
		loadFailed = false,
		showPrices = true,
		subtotalMinor,
		attachTo = null,
		alwaysEditing = false,
		editorTotalLabel = 'Subtotal',
		saveLabel = 'Save pricing',
		lockedMessage = '',
		emptyDescription = 'Add the products and services this job needs before it becomes a quote.',
		onSave,
		onDraftChange,
		clientView
	}: {
		lines?: RequestPricingLine[];
		/** Enables Quote-only add-ons, text/headings and tax exemption controls. */
		quoteChoices?: boolean;
		revision?: number;
		editable?: boolean;
		currencyCode?: string;
		locale?: string;
		loading?: boolean;
		loadFailed?: boolean;
		/** False when the API withheld prices. Names and quantities remain useful without inventing zeroes. */
		showPrices?: boolean;
		/** Exact selected subtotal returned by the database; Quote screens must provide it. */
		subtotalMinor?: number | null;
		/** Where a line photo is stored. Null means there is nothing to attach it to yet, so no photos. */
		attachTo?: { entityType: 'request' | 'quote'; entityId: string } | null;
		/** The new-quote form types straight into the rows and saves from the page's own footer. */
		alwaysEditing?: boolean;
		/** What the editor's own action bar calls the running total, e.g. "Request subtotal". */
		editorTotalLabel?: string;
		saveLabel?: string;
		lockedMessage?: string;
		emptyDescription?: string;
		onSave?: (expectedRevision: number, lines: RequestPricingLineInput[]) => Promise<void>;
		onDraftChange?: (lines: RequestPricingLineInput[], subtotalMinor: number) => void;
		/** Quote-only controls rendered where Jobber puts them: below the line editor actions. */
		clientView?: Snippet;
	} = $props();

	const queryClient = useQueryClient();

	type DraftLine = {
		id: string;
		catalog_item_id: string | null;
		category: PricingCategory;
		is_labor: boolean;
		name: string;
		description: string | null;
		unit_label: string | null;
		quantity: number;
		unit_price_minor: number;
		unit_cost_minor: number;
		is_taxable: boolean;
		image_attachment_id: string | null;
		/** A photo picked before its request or quote exists. It stays in the browser until page Save. */
		imageFile: File | null;
		imageThumbnail: Blob | null;
		imagePreviewUrl: string;
		imageUploading: boolean;
		/** This line came from a saved item whose cost the API withheld, so nothing here may write one. */
		costHidden: boolean;
		line_kind: QuoteLineKind;
		selection_kind: QuoteSelectionKind;
		is_recommended: boolean;
	};

	let editing = $state(false);
	let draftLines = $state<DraftLine[]>([]);
	let saving = $state(false);
	let error = $state('');
	let notice = $state('');
	let confirmingDiscard = $state(false);
	let priceBookOpen = $state(false);
	let priceBookButton = $state<HTMLElement>();
	// The line whose values are being pushed into the price book, either as a new saved item or over the
	// one it already came from. Null while no such dialog is open.
	let catalogDraft = $state<{ lineId: string; mode: 'create' | 'update'; itemId?: string } | null>(
		null
	);
	// A line only complains about a missing name once the person has actually left the field.
	let nameTouched = $state<Record<string, boolean>>({});
	// Every line owns its own file input. One shared input plus a "which line asked for it" variable meant
	// a pick could land on nothing at all if that variable was ever cleared between the click and the
	// browser handing the file back.
	let fileInputs: Record<string, HTMLInputElement | undefined> = $state({});
	// Photos uploaded during this edit session that have not been claimed by a save yet. Cancelling, or
	// swapping/removing one before Save, deletes it so a picked-then-discarded photo does not sit in
	// storage forever. Never touches a photo that was already on a saved line before this session started.
	const uploadedThisSession = new Set<string>();

	function toDraft(line: RequestPricingLine): DraftLine {
		return {
			id: line.id,
			catalog_item_id: line.catalog_item_id,
			category: line.category,
			is_labor: line.is_labor,
			name: line.name,
			description: line.description,
			unit_label: line.unit_label,
			quantity: line.quantity,
			unit_price_minor: line.unit_price_minor,
			unit_cost_minor: line.unit_cost_minor,
			is_taxable: line.is_taxable,
			image_attachment_id: line.image_attachment_id,
			imageFile: null,
			imageThumbnail: null,
			imagePreviewUrl: '',
			imageUploading: false,
			costHidden: false,
			line_kind: line.line_kind ?? 'priced',
			selection_kind: line.selection_kind ?? 'required',
			is_recommended: line.is_recommended ?? false
		};
	}

	// The form that types straight into the rows is in edit mode from the moment it appears.
	const isEditing = $derived(alwaysEditing || editing);

	function openEdit() {
		draftLines = savedLines.map(toDraft);
		error = '';
		notice = '';
		editing = true;
	}

	// What the page's own footer saves, and what the rail's Overview adds up while somebody types.
	$effect(() => {
		if (!alwaysEditing || !onDraftChange) return;
		const payload = toInputs(draftLines);
		const subtotal = draftSubtotal(draftLines);
		untrack(() => onDraftChange(payload, subtotal));
	});

	async function discardIfOrphaned(attachmentId: string) {
		if (!uploadedThisSession.has(attachmentId)) return;
		uploadedThisSession.delete(attachmentId);
		try {
			await deleteAttachment(attachmentId);
		} catch (caught) {
			console.error('Could not delete an unsaved line photo.', attachmentId, caught);
		}
	}

	function closeEdit() {
		for (const line of draftLines) releaseLocalPreview(line);
		for (const attachmentId of [...uploadedThisSession]) void discardIfOrphaned(attachmentId);
		priceBookOpen = false;
		catalogDraft = null;
		editing = false;
		draftLines = [];
		nameTouched = {};
		error = '';
		confirmingDiscard = false;
	}

	// A line nobody has typed into yet is not a change worth warning about — clicking "Add line item" and
	// then changing your mind should just close.
	function isUntouchedLine(line: DraftLine) {
		return (
			!line.name.trim() &&
			!line.description?.trim() &&
			!line.image_attachment_id &&
			!line.imageFile &&
			line.quantity === 1 &&
			line.unit_price_minor === 0
		);
	}

	function comparable(
		lines: {
			name: string;
			description: string | null;
			quantity: number;
			unit_price_minor: number;
			unit_label: string | null;
			is_taxable: boolean;
			catalog_item_id: string | null;
			image_attachment_id: string | null;
			imageFile?: File | null;
			line_kind?: QuoteLineKind;
			selection_kind?: QuoteSelectionKind;
			is_recommended?: boolean;
		}[]
	) {
		return JSON.stringify(
			lines.map((line) => [
				line.name.trim(),
				line.description ?? '',
				line.unit_label ?? '',
				line.quantity,
				line.unit_price_minor,
				line.is_taxable,
				line.catalog_item_id ?? '',
				line.image_attachment_id ?? '',
				line.line_kind ?? 'priced',
				line.selection_kind ?? 'required',
				line.is_recommended ?? false,
				line.imageFile
					? `${line.imageFile.name}:${line.imageFile.size}:${line.imageFile.lastModified}`
					: ''
			])
		);
	}

	// Kept as two separate deriveds so typing only re-serializes the draft — the saved side is rebuilt
	// only when the server data itself changes.
	const savedComparable = $derived(comparable(savedLines));
	const draftComparable = $derived(comparable(draftLines.filter((line) => !isUntouchedLine(line))));
	const dirty = $derived(isEditing && draftComparable !== savedComparable);

	function requestClose() {
		if (dirty) {
			confirmingDiscard = true;
			return;
		}
		closeEdit();
	}

	// From the empty state the button says "add a line item", so it has to hand back a line to fill in —
	// opening an editor with nothing in it reads as a dead click.
	function openEditWithFirstLine() {
		openEdit();
		if (draftLines.length === 0) void addLine();
	}

	async function addLine() {
		const id = crypto.randomUUID();
		draftLines = [
			...draftLines,
			{
				id,
				catalog_item_id: null,
				category: 'service',
				is_labor: false,
				name: '',
				description: null,
				unit_label: null,
				quantity: 1,
				unit_price_minor: 0,
				unit_cost_minor: 0,
				is_taxable: true,
				image_attachment_id: null,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false,
				costHidden: false,
				line_kind: 'priced',
				selection_kind: 'required',
				is_recommended: false
			}
		];
		// Focusing the new Name opens the price list under it, so the next thing typed searches straight
		// away instead of needing a second click.
		await tick();
		document.getElementById(`pricing-name-${id}`)?.focus();
	}

	function removeLine(id: string) {
		const line = draftLines.find((entry) => entry.id === id);
		if (line) releaseLocalPreview(line);
		if (line?.image_attachment_id) void discardIfOrphaned(line.image_attachment_id);
		draftLines = draftLines.filter((entry) => entry.id !== id);
	}

	function updateLine(id: string, patch: Partial<DraftLine>) {
		draftLines = draftLines.map((line) => (line.id === id ? { ...line, ...patch } : line));
	}

	function handleReorder(event: CustomEvent<{ items: DraftLine[] }>) {
		draftLines = event.detail.items;
	}

	function applyCatalogItem(id: string, item: CatalogItem) {
		updateLine(id, {
			catalog_item_id: item.id,
			category: item.category,
			name: item.name,
			description: item.description,
			unit_label: item.unit_label,
			unit_price_minor: item.unit_price_minor,
			// Cost is left alone when the person may not see it — the API never sent a figure, and the
			// save fills it back in from the same saved item.
			...(item.unit_cost_minor === undefined ? {} : { unit_cost_minor: item.unit_cost_minor }),
			costHidden: item.unit_cost_minor === undefined,
			is_taxable: item.is_taxable,
			line_kind: 'priced',
			selection_kind: 'required',
			is_recommended: false
		});
	}

	// A pick from the price book is a copy, not a link to live prices. The line is the document's from
	// here on: change its quantity, wording or price for this customer and the saved item never moves.
	function addCatalogLine(item: CatalogItem) {
		draftLines = [
			...draftLines,
			{
				id: crypto.randomUUID(),
				catalog_item_id: item.id,
				category: item.category,
				is_labor: item.is_labor,
				name: item.name,
				description: item.description,
				unit_label: item.unit_label,
				quantity: 1,
				unit_price_minor: item.unit_price_minor,
				unit_cost_minor: item.unit_cost_minor ?? 0,
				is_taxable: item.is_taxable,
				image_attachment_id: null,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false,
				costHidden: item.unit_cost_minor === undefined,
				line_kind: 'priced',
				selection_kind: 'required',
				is_recommended: false
			}
		];
	}

	function addCopyLine(lineKind: 'text' | 'heading') {
		draftLines = [
			...draftLines,
			{
				id: crypto.randomUUID(),
				catalog_item_id: null,
				category: 'service',
				is_labor: false,
				name: '',
				description: null,
				unit_label: null,
				quantity: 1,
				unit_price_minor: 0,
				unit_cost_minor: 0,
				is_taxable: false,
				image_attachment_id: null,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false,
				costHidden: false,
				line_kind: lineKind,
				selection_kind: 'required',
				is_recommended: false
			}
		];
	}

	// What this line is, in the two or three words a badge can hold. Only states worth noticing are
	// listed: a required, taxable line is the ordinary case and says nothing.
	function lineBadges(line: DraftLine) {
		const marks: string[] = [];
		if (quoteChoices) {
			if (line.selection_kind === 'optional')
				marks.push(line.is_recommended ? 'Recommended add-on' : 'Optional add-on');
			if (!line.is_taxable) marks.push('Tax exempt');
		}
		return marks;
	}

	// Everything a line can be told to become, in one menu behind its own three dots. These are moves
	// rather than switches - a menu closes the moment it is used, so "Make it optional" says what will
	// happen where a tick box would have to say what already is. What a line currently is shows as a
	// badge on the card itself.
	function lineMenuItems(line: DraftLine) {
		const items: Array<{
			label: string;
			icon?: string;
			disabled?: boolean;
			destructive?: boolean;
			onSelect: () => void;
		}> = [];

		if (quoteChoices && line.line_kind === 'priced') {
			if (line.selection_kind !== 'required')
				items.push({
					label: 'Make it required',
					icon: requiredIcon,
					onSelect: () => changeChoice(line.id, 'required')
				});
			if (line.selection_kind !== 'optional')
				items.push({
					label: 'Make it an optional add-on',
					icon: optionalIcon,
					onSelect: () => changeChoice(line.id, 'optional')
				});
			if (line.selection_kind === 'optional')
				items.push(
					line.is_recommended
						? {
								label: 'Stop recommending it',
								icon: starOffIcon,
								onSelect: () => updateLine(line.id, { is_recommended: false })
							}
						: {
								label: 'Recommend this add-on',
								icon: starIcon,
								onSelect: () => updateLine(line.id, { is_recommended: true })
							}
				);
			items.push(
				line.is_taxable
					? {
							label: 'Mark tax exempt',
							icon: taxOffIcon,
							onSelect: () => updateLine(line.id, { is_taxable: false })
						}
					: {
							label: 'Charge tax on it',
							icon: taxIcon,
							onSelect: () => updateLine(line.id, { is_taxable: true })
						}
			);
		}

		items.push({
			label: line.catalog_item_id ? 'Update saved item' : 'Save to price book',
			icon: bookmarkIcon,
			disabled: !line.name.trim(),
			onSelect: () => startCatalogSave(line.id)
		});
		items.push({
			label: 'Delete',
			icon: trashIcon,
			destructive: true,
			onSelect: () => removeLine(line.id)
		});
		return items;
	}

	function changeChoice(lineId: string, value: QuoteSelectionKind) {
		updateLine(lineId, { selection_kind: value, is_recommended: false });
	}

	// What the drawer marks as already added. Counted off the draft rather than remembered inside the
	// drawer, so closing it, deleting the line and opening it again tells the truth.
	const addedCounts = $derived(
		draftLines.reduce<Record<string, number>>((counts, line) => {
			if (line.catalog_item_id)
				counts[line.catalog_item_id] = (counts[line.catalog_item_id] ?? 0) + 1;
			return counts;
		}, {})
	);

	// The drawer's contents do not load with the page, so reaching the button starts the first page of the
	// price list. The click usually lands on a list that is already there.
	function warmPriceBook() {
		void queryClient.prefetchInfiniteQuery({
			queryKey: catalogItemsKey({}),
			queryFn: () => fetchCatalogItems({}),
			initialPageParam: undefined as string | undefined,
			staleTime: 30_000
		});
	}

	function openPriceBook() {
		priceBookOpen = true;
	}

	function closePriceBook() {
		priceBookOpen = false;
		// Bits UI hands focus back to whatever it opened from, and this panel is opened by a flag rather
		// than by its own trigger, so the button asks for focus itself.
		priceBookButton?.focus();
	}

	async function addCustomLineFromPriceBook() {
		closePriceBook();
		await addLine();
	}

	const catalogDraftLine = $derived.by(() => {
		const draft = catalogDraft;
		if (!draft) return null;
		return draftLines.find((line) => line.id === draft.lineId) ?? null;
	});

	// Saving a line into the price book, or pushing its changes back onto the item it came from, is
	// always something the person asks for. Neither one touches this document.
	function startCatalogSave(lineId: string) {
		const line = draftLines.find((entry) => entry.id === lineId);
		if (!line) return;
		catalogDraft = line.catalog_item_id
			? { lineId, mode: 'update', itemId: line.catalog_item_id }
			: { lineId, mode: 'create' };
	}

	function catalogSaved(item: CatalogItem) {
		const draft = catalogDraft;
		catalogDraft = null;
		void queryClient.invalidateQueries({ queryKey: ['catalog-items'] });
		if (!draft) return;
		// A one-off that has just been saved is a price book line from now on, so later edits can offer to
		// update it. Nothing else about the line changes.
		if (draft.mode === 'create') updateLine(draft.lineId, { catalog_item_id: item.id });
		notice =
			draft.mode === 'update'
				? 'Saved. New lines will start from this — what is written here keeps what it already has.'
				: `“${item.name}” is in the price book now.`;
	}

	function openImagePicker(id: string) {
		fileInputs[id]?.click();
	}

	function removeImage(id: string) {
		const line = draftLines.find((entry) => entry.id === id);
		if (line) releaseLocalPreview(line);
		if (line?.image_attachment_id) void discardIfOrphaned(line.image_attachment_id);
		updateLine(id, {
			image_attachment_id: null,
			imageFile: null,
			imageThumbnail: null,
			imagePreviewUrl: ''
		});
	}

	async function handleFileChosen(id: string, fileList: FileList | null) {
		const chosen = fileList?.[0];
		// Clearing the input lets the same file be picked again after a remove.
		const input = fileInputs[id];
		if (input) input.value = '';
		if (!chosen) return;

		const file = chosen;
		if (!file.type.startsWith('image/')) {
			error = 'Only a photo can be attached to a line.';
			return;
		}
		if (file.size > MAX_ATTACHMENT_SIZE_BYTES) {
			error = 'That photo is over 25 MB.';
			return;
		}

		const previousAttachmentId =
			draftLines.find((line) => line.id === id)?.image_attachment_id ?? null;
		updateLine(id, { imageUploading: true });

		try {
			const thumbnail = await createImageThumbnail(file);
			// A create form has no server record yet. Jobber still shows the image box immediately, so keep
			// the photo and its preview locally and let the page's Save hand us the new record id later.
			if (!attachTo) {
				const current = draftLines.find((line) => line.id === id);
				if (current) releaseLocalPreview(current);
				updateLine(id, {
					image_attachment_id: null,
					imageFile: file,
					imageThumbnail: thumbnail,
					imagePreviewUrl: URL.createObjectURL(thumbnail ?? file),
					imageUploading: false
				});
				return;
			}
			const presigned = await presignAttachmentUpload({
				entityType: attachTo.entityType,
				entityId: attachTo.entityId,
				fileName: file.name,
				mimeType: file.type,
				sizeBytes: file.size
			});
			await uploadAttachmentFile(presigned.upload_url, file);

			let thumbnailObjectKey: string | null = null;
			if (thumbnail && presigned.thumbnail_upload_url && presigned.thumbnail_object_key) {
				try {
					await uploadAttachmentFile(presigned.thumbnail_upload_url, thumbnail);
					thumbnailObjectKey = presigned.thumbnail_object_key;
				} catch (thumbnailError) {
					console.error('Could not upload the preview for a line photo.', thumbnailError);
				}
			}

			const attachment = await createAttachment({
				entityType: attachTo.entityType,
				entityId: attachTo.entityId,
				fileName: file.name,
				mimeType: file.type,
				sizeBytes: file.size,
				objectKey: presigned.object_key,
				thumbnailObjectKey
			});
			uploadedThisSession.add(attachment.id);
			updateLine(id, { image_attachment_id: attachment.id, imageUploading: false });
			if (previousAttachmentId) void discardIfOrphaned(previousAttachmentId);
		} catch (caught) {
			updateLine(id, { imageUploading: false });
			error = caught instanceof Error ? caught.message : 'That photo could not be uploaded.';
		}
	}

	function releaseLocalPreview(line: DraftLine) {
		if (line.imagePreviewUrl) URL.revokeObjectURL(line.imagePreviewUrl);
	}

	async function uploadPendingPhoto(
		line: DraftLine,
		entityType: 'request' | 'quote',
		entityId: string
	) {
		const file = line.imageFile;
		const thumbnail = line.imageThumbnail;
		if (!file) return true;
		updateLine(line.id, { imageUploading: true });

		try {
			const presigned = await presignAttachmentUpload({
				entityType,
				entityId,
				fileName: file.name,
				mimeType: file.type,
				sizeBytes: file.size
			});
			await uploadAttachmentFile(presigned.upload_url, file);

			let thumbnailObjectKey: string | null = null;
			if (thumbnail && presigned.thumbnail_upload_url && presigned.thumbnail_object_key) {
				try {
					await uploadAttachmentFile(presigned.thumbnail_upload_url, thumbnail);
					thumbnailObjectKey = presigned.thumbnail_object_key;
				} catch (thumbnailError) {
					console.error('Could not upload the preview for a line photo.', thumbnailError);
				}
			}

			const attachment = await createAttachment({
				entityType,
				entityId,
				fileName: file.name,
				mimeType: file.type,
				sizeBytes: file.size,
				objectKey: presigned.object_key,
				thumbnailObjectKey
			});
			uploadedThisSession.add(attachment.id);
			releaseLocalPreview(line);
			updateLine(line.id, {
				image_attachment_id: attachment.id,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false
			});
			return true;
		} catch (caught) {
			updateLine(line.id, { imageUploading: false });
			error = caught instanceof Error ? caught.message : 'That photo could not be uploaded.';
			return false;
		}
	}

	/** Uploads photos held by a create form, then returns the exact lines the page should save. */
	export async function savePendingPhotos(
		entityType: 'request' | 'quote',
		entityId: string
	): Promise<{ failures: number; lines: RequestPricingLineInput[] }> {
		const pending = draftLines.filter((line) => line.imageFile);
		if (pending.length === 0) return { failures: 0, lines: toInputs(draftLines) };

		saving = true;
		error = '';
		const results: boolean[] = [];
		try {
			// Four at a time keeps a large quote from opening hundreds of upload connections at once.
			for (let index = 0; index < pending.length; index += 4) {
				results.push(
					...(await Promise.all(
						pending
							.slice(index, index + 4)
							.map((line) => uploadPendingPhoto(line, entityType, entityId))
					))
				);
			}
			return {
				failures: results.filter((saved) => !saved).length,
				lines: toInputs(draftLines)
			};
		} finally {
			saving = false;
		}
	}

	/** The page calls this only after its line save lands, so those uploaded photos are no longer orphans. */
	export function commitPendingPhotos() {
		uploadedThisSession.clear();
	}

	onDestroy(() => {
		for (const line of draftLines) releaseLocalPreview(line);
		for (const attachmentId of [...uploadedThisSession]) void discardIfOrphaned(attachmentId);
	});

	// The database is the only place a line total is calculated once it is saved. This is a preview of the
	// same arithmetic (quantity and price are never negative here, so JS rounding matches Postgres's) so the
	// number on screen does not jump the moment Save lands.
	function previewTotal(line: DraftLine) {
		if (line.line_kind !== 'priced') return 0;
		return Math.round(line.quantity * line.unit_price_minor);
	}

	function draftSubtotal(lines: DraftLine[]) {
		return lines.reduce(
			(sum, line) =>
				sum + (line.selection_kind === 'required' || !quoteChoices ? previewTotal(line) : 0),
			0
		);
	}

	const anyLinePhoto = $derived(savedLines.some((line) => line.image_attachment_id));

	function savedSubtotal(lines: RequestPricingLine[]) {
		if (subtotalMinor !== undefined && subtotalMinor !== null) return subtotalMinor;
		return lines.reduce((sum, line) => sum + line.line_total_minor, 0);
	}

	// Built once per currency, not once per figure. Every line renders four amounts and the block renders
	// two more, so constructing a formatter inside the call was rebuilding it dozens of times a keystroke.
	const moneyFormatter = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);

	function formatMoney(minor: number) {
		return moneyFormatter.format(minor / 100);
	}

	// One row on its way to the database. `id` stays behind: the whole set is replaced every time, so a
	// browser-side key is all a draft row needs.
	function toInputs(lines: DraftLine[]): RequestPricingLineInput[] {
		return lines.map((line) => {
			if (quoteChoices && line.line_kind !== 'priced') {
				return {
					line_kind: line.line_kind,
					name: line.name.trim(),
					description: line.description
				} as RequestPricingLineInput;
			}
			return {
				name: line.name.trim(),
				category: line.category,
				is_labor: line.is_labor,
				catalog_item_id: line.catalog_item_id,
				description: line.description,
				unit_label: line.unit_label,
				quantity: line.quantity,
				unit_price_minor: line.unit_price_minor,
				unit_cost_minor: line.unit_cost_minor,
				is_taxable: line.is_taxable,
				image_attachment_id: line.image_attachment_id,
				...(quoteChoices
					? {
							line_kind: 'priced' as const,
							selection_kind: line.selection_kind,
							is_recommended: line.is_recommended
						}
					: {})
			};
		});
	}

	async function save() {
		if (!onSave || saving) return;
		const problem = firstLineProblem(
			draftLines.map((line) => ({
				name: line.name,
				quantity: line.line_kind === 'priced' ? line.quantity : 1
			}))
		);
		if (problem) {
			error = problem;
			return;
		}
		saving = true;
		error = '';
		try {
			await onSave(revision, toInputs(draftLines));
			uploadedThisSession.clear();
			editing = false;
			draftLines = [];
		} catch (caught) {
			const writeError = caught as QuoteWriteError;
			if (writeError.reason === 'stale') {
				closeEdit();
				notice = 'Someone else changed this while you were editing. Here is the latest version.';
			} else {
				error = writeError.message || 'Those changes could not be saved.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="Products and services" icon={listIcon} level={2}>
	{#snippet actions()}
		{#if editable && !isEditing && savedLines.length > 0}
			<PencilButton onclick={openEdit} label="Edit products and services" />
		{/if}
	{/snippet}

	{#if notice}<p class="pricing-block__notice" role="status">{notice}</p>{/if}

	{#if loading}
		<p class="pricing-block__hint">Loading pricing…</p>
	{:else if loadFailed}
		<p class="pricing-block__error" role="alert">That pricing could not be loaded.</p>
	{:else if isEditing}
		{#if draftLines.length === 0}
			<p class="pricing-block__hint">
				Nothing priced yet. Add a line item, or pick one out of the price book.
			</p>
		{/if}
		<div
			class="pricing-card-list"
			use:dragHandleZone={{
				items: draftLines,
				flipDurationMs: 150,
				dragDisabled: saving || draftLines.length < 2
			}}
			onconsider={handleReorder}
			onfinalize={handleReorder}
		>
			{#each draftLines as line (line.id)}
				<div class="pricing-card" animate:flip={{ duration: 150 }}>
					{#if draftLines.length > 1}
						<div class="pricing-card__handle" use:dragHandle aria-label="Reorder this line">
							{@html gripIcon}
						</div>
					{/if}
					<div class="pricing-card__body">
						{#if quoteChoices && line.line_kind !== 'priced'}
							<div class="pricing-card__copy">
								<Input
									id={`pricing-copy-${line.id}`}
									label={line.line_kind === 'heading' ? 'Heading' : 'Text title'}
									disabled={saving}
									bind:value={() => line.name, (value) => updateLine(line.id, { name: value })}
								/>
								{#if line.line_kind === 'text'}
									<Textarea
										id={`pricing-copy-description-${line.id}`}
										label="Text"
										rows={3}
										maxlength={2000}
										showCount={false}
										disabled={saving}
										bind:value={
											() => line.description ?? '',
											(value) => updateLine(line.id, { description: value || null })
										}
									/>
								{/if}
							</div>
						{:else}
							{#if lineBadges(line).length > 0}
								<div class="pricing-card__marks">
									{#each lineBadges(line) as mark (mark)}
										<Badge size="small">{mark}</Badge>
									{/each}
								</div>
							{/if}
							<div class="pricing-card__row1">
								<div class="pricing-card__name">
									<CatalogItemPicker
										id={`pricing-name-${line.id}`}
										label="Name"
										disabled={saving}
										{currencyCode}
										{locale}
										invalid={Boolean(nameTouched[line.id]) && !line.name.trim()}
										errorMessage={nameTouched[line.id] && !line.name.trim()
											? 'Give this line a name.'
											: ''}
										onBlur={() => (nameTouched = { ...nameTouched, [line.id]: true })}
										bind:value={() => line.name, (value) => updateLine(line.id, { name: value })}
										onSelect={(item) => applyCatalogItem(line.id, item)}
									/>
								</div>
								<QuantityInput
									id={`pricing-qty-${line.id}`}
									label="Quantity"
									disabled={saving}
									bind:value={
										() => line.quantity, (value) => updateLine(line.id, { quantity: value })
									}
								/>
								<MoneyInput
									id={`pricing-price-${line.id}`}
									label="Unit price"
									disabled={saving}
									bind:value={
										() => line.unit_price_minor,
										(value) => updateLine(line.id, { unit_price_minor: value })
									}
								/>
								<Input
									id={`pricing-total-${line.id}`}
									label="Total"
									readonly
									tabindex={-1}
									value={formatMoney(previewTotal(line))}
								/>
							</div>
							<div class="pricing-card__row2">
								<div class="pricing-card__description">
									<Textarea
										id={`pricing-description-${line.id}`}
										label="Description"
										rows={4}
										maxlength={2000}
										showCount={false}
										disabled={saving}
										bind:value={
											() => line.description ?? '',
											(value) => updateLine(line.id, { description: value || null })
										}
									/>
								</div>
								<div
									class="pricing-card__image"
									class:pricing-card__image--filled={Boolean(
										line.imagePreviewUrl || line.image_attachment_id
									)}
								>
									<input
										bind:this={fileInputs[line.id]}
										type="file"
										accept="image/*"
										class="pricing-card__file-input"
										tabindex={-1}
										aria-hidden="true"
										onchange={(event) =>
											void handleFileChosen(
												line.id,
												(event.currentTarget as HTMLInputElement).files
											)}
									/>
									{#if line.imageUploading}
										<span class="pricing-card__image-loading" aria-hidden="true"></span>
									{:else if line.imagePreviewUrl}
										<img src={line.imagePreviewUrl} alt="" />
										<div class="pricing-card__image-tools">
											<button
												type="button"
												class="pricing-card__image-tool pricing-card__image-tool--replace"
												aria-label="Replace photo"
												disabled={saving}
												onclick={() => openImagePicker(line.id)}
											>
												{@html pencilIcon}
											</button>
											<button
												type="button"
												class="pricing-card__image-tool pricing-card__image-tool--remove"
												aria-label="Remove photo"
												disabled={saving}
												onclick={() => removeImage(line.id)}
											>
												{@html trashIcon}
											</button>
										</div>
									{:else if line.image_attachment_id}
										<img
											src={attachmentImageUrl(line.image_attachment_id, 'thumb')}
											alt=""
											loading="lazy"
										/>
										<div class="pricing-card__image-tools">
											<button
												type="button"
												class="pricing-card__image-tool pricing-card__image-tool--replace"
												aria-label="Replace photo"
												disabled={saving}
												onclick={() => openImagePicker(line.id)}
											>
												{@html pencilIcon}
											</button>
											<button
												type="button"
												class="pricing-card__image-tool pricing-card__image-tool--remove"
												aria-label="Remove photo"
												disabled={saving}
												onclick={() => removeImage(line.id)}
											>
												{@html trashIcon}
											</button>
										</div>
									{:else}
										<button
											type="button"
											class="pricing-card__image-add"
											aria-label="Add a photo"
											disabled={saving}
											onclick={() => openImagePicker(line.id)}
										>
											{@html uploadIcon}
										</button>
									{/if}
								</div>
							</div>
						{/if}
					</div>
					<div class="pricing-card__actions">
						<DropdownMenu
							triggerLabel="Line actions"
							triggerClass="dropdown-menu__trigger pricing-card__menu-trigger"
							disabled={saving}
							items={lineMenuItems(line)}
						/>
					</div>
				</div>
			{/each}
		</div>
		<div class="pricing-block__footer">
			<Button size="small" variant="tertiary" disabled={saving} onclick={addLine}>
				Add line item
			</Button>
			<span bind:this={priceBookButton} class="pricing-block__price-book">
				<Button
					size="small"
					variant="secondary"
					disabled={saving}
					onhover={warmPriceBook}
					onclick={openPriceBook}
				>
					<span class="pricing-block__price-book-icon" aria-hidden="true">{@html bookIcon}</span>
					Price book
				</Button>
			</span>
			{#if quoteChoices}
				<Button
					size="small"
					variant="tertiary"
					disabled={saving}
					onclick={() => addCopyLine('text')}
				>
					Add text
				</Button>
				<Button
					size="small"
					variant="tertiary"
					disabled={saving}
					onclick={() => addCopyLine('heading')}
				>
					Add heading
				</Button>
			{/if}
		</div>
		{#if quoteChoices && clientView}
			{@render clientView()}
		{/if}
		<div class="pricing-block__totals">
			<div class="pricing-block__totals-row">
				<span>Subtotal</span>
				<span>{formatMoney(draftSubtotal(draftLines))}</span>
			</div>
		</div>
	{:else if savedLines.length === 0}
		<EmptyState
			icon={listIcon}
			iconLabel="Price this request"
			onIconClick={editable ? openEditWithFirstLine : undefined}
			title="Nothing priced yet"
			description={emptyDescription}
		>
			{#snippet action()}
				{#if editable}
					<Button variant="secondary" onclick={openEditWithFirstLine}>Add a line item</Button>
				{/if}
			{/snippet}
		</EmptyState>
	{:else}
		<div class="pricing-table__scroll">
			<table class="pricing-table">
				<thead>
					<tr>
						<th scope="col">Line item</th>
						{#if anyLinePhoto}
							<th scope="col" class="pricing-table__photo" aria-label="Photo"></th>
						{/if}
						<th scope="col" class="pricing-table__number">Quantity</th>
						{#if showPrices}
							<th scope="col" class="pricing-table__number">Unit price</th>
							<th scope="col" class="pricing-table__number">Total</th>
						{/if}
					</tr>
				</thead>
				<tbody>
					{#each savedLines as line (line.id)}
						{#if quoteChoices && line.line_kind !== 'priced'}
							<tr class:pricing-table__heading={line.line_kind === 'heading'}>
								<th
									scope="row"
									colspan={showPrices ? (anyLinePhoto ? 5 : 4) : anyLinePhoto ? 3 : 2}
								>
									<span class="pricing-table__name">{line.name}</span>
									{#if line.description}<span class="pricing-table__description"
											>{line.description}</span
										>{/if}
								</th>
							</tr>
						{:else}
							<tr>
								<th scope="row">
									<span class="pricing-table__name">{line.name}</span>
									{#if quoteChoices && line.selection_kind === 'optional'}
										<span class="pricing-table__choice">
											{line.is_recommended ? 'Recommended add-on' : 'Optional add-on'}
										</span>
									{/if}
									{#if line.description}
										<span class="pricing-table__description">{line.description}</span>
									{/if}
								</th>
								{#if anyLinePhoto}
									<td class="pricing-table__photo">
										{#if line.image_attachment_id}
											<img
												src={attachmentImageUrl(line.image_attachment_id, 'thumb')}
												alt=""
												loading="lazy"
											/>
										{/if}
									</td>
								{/if}
								<td class="pricing-table__number">
									{line.quantity}{#if line.unit_label}&nbsp;{line.unit_label}{/if}
								</td>
								{#if showPrices}
									<td class="pricing-table__number">{formatMoney(line.unit_price_minor)}</td>
									<td class="pricing-table__number">{formatMoney(line.line_total_minor)}</td>
								{/if}
							</tr>
						{/if}
					{/each}
				</tbody>
			</table>
		</div>
		{#if showPrices}
			<div class="pricing-block__totals">
				<div class="pricing-block__totals-row">
					<span>Subtotal</span>
					<span>{formatMoney(savedSubtotal(savedLines))}</span>
				</div>
			</div>
		{/if}
	{/if}

	{#if !editable && lockedMessage && !loading && !loadFailed}
		<p class="pricing-block__hint">{lockedMessage}</p>
	{/if}
</SectionBlock>

{#if editing && onSave}
	<div class="pricing-block__actions">
		{#if error}<p class="pricing-block__error" role="alert">{error}</p>{/if}
		<div class="pricing-block__actions-row">
			<span class="pricing-block__grand-total">
				{quoteChoices ? 'Required subtotal preview' : editorTotalLabel}
				{formatMoney(draftSubtotal(draftLines))}
			</span>
			<span class="pricing-block__spacer"></span>
			<Button variant="tertiary" onclick={requestClose} disabled={saving}>Cancel</Button>
			<Button variant="primary" onclick={() => void save()} loading={saving}>{saveLabel}</Button>
		</div>
	</div>
{:else if error}
	<p class="pricing-block__error pricing-block__error--standalone" role="alert">{error}</p>
{/if}

{#if isEditing}
	<PriceBookDrawer
		open={priceBookOpen}
		{currencyCode}
		{locale}
		{addedCounts}
		onAdd={addCatalogLine}
		onAddCustomLine={() => void addCustomLineFromPriceBook()}
		onClose={closePriceBook}
	/>
{/if}

{#if catalogDraft && catalogDraftLine}
	<CatalogItemDialog
		open={true}
		mode={catalogDraft.mode}
		itemId={catalogDraft.itemId}
		name={catalogDraftLine.name}
		description={catalogDraftLine.description ?? ''}
		category={catalogDraftLine.category}
		unitLabel={catalogDraftLine.unit_label}
		unitPriceMinor={catalogDraftLine.unit_price_minor}
		unitCostMinor={catalogDraftLine.unit_cost_minor}
		canViewCost={!catalogDraftLine.costHidden}
		isTaxable={catalogDraftLine.is_taxable}
		onSaved={catalogSaved}
		onClose={() => (catalogDraft = null)}
	/>
{/if}

<ConfirmDialog
	open={confirmingDiscard}
	title="Throw away these changes?"
	tone="critical"
	destructive
	confirmLabel="Throw them away"
	cancelLabel="Keep editing"
	onConfirm={closeEdit}
	onClose={() => (confirmingDiscard = false)}
>
	<p>What you changed on these lines has not been saved yet.</p>
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.pricing-block {
		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__notice {
			margin: 0 0 var(--space-base);
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
		}
		&__price-book {
			display: inline-flex;
		}
		&__price-book-icon :global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			// When the page owns the save, the block's own message still needs room under it.
			&--standalone {
				margin-top: var(--space-small);
			}
		}
		&__footer {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding-top: var(--space-small);
		}
		// Money never sits beside the controls. It gets its own stack under the lines, right aligned and
		// narrow, so the eye reads down a single column of figures the way it does on a printed quote.
		&__totals {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-left: auto;
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			margin-top: var(--space-base);
			width: min(320px, 100%);
		}
		&__totals-row {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-base);
			color: var(--color-heading);
			font-weight: 700;
		}
		&__actions {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-slim);
			padding: var(--space-base) var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}
		&__actions-row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}
		&__grand-total {
			color: var(--color-heading);
			font-weight: 700;
		}
		&__spacer {
			flex: 1 1 auto;
		}
	}

	.pricing-card-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	.pricing-card {
		display: flex;
		content-visibility: auto;
		contain-intrinsic-size: auto 240px;
		align-items: stretch;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		// The handle and the line menu live in gutters either side of the fields, never inside the grid, so
		// four columns stay four columns whether or not those controls are there.
		&__actions {
			display: flex;
			flex: 0 0 auto;
			align-items: flex-start;
			justify-content: center;
			min-width: var(--space-larger);
		}

		&__handle {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 20px;
			color: var(--color-icon--secondary);
			cursor: grab;
			touch-action: none;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&:active {
				cursor: grabbing;
			}
		}

		&__body {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-small);
		}
		&__copy {
			display: grid;
			gap: var(--space-small);
		}
		// What the line already is, rather than controls to make it so - those live in the line's own menu.
		&__marks {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
			padding-bottom: var(--space-small);
		}

		// The name carries the wording, so it takes three times the width of each number column. Both rows
		// share one set of column widths, which is what keeps the photo sitting square under Total.
		&__row1,
		&__row2 {
			display: grid;
			grid-template-columns: 3fr 1fr 1fr 1fr;
			gap: var(--space-small);
		}
		&__row1 {
			align-items: start;
		}
		&__row2 {
			align-items: stretch;
		}
		&__name {
			min-width: 0;
			grid-column: 1 / 2;
		}
		&__description {
			min-width: 0;
			grid-column: 1 / 4;
		}
		// A photo of the work is worth reading, so it gets the whole fourth column beside the description
		// rather than a stamp-sized tile.
		&__file-input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}
		&__image {
			position: relative;
			display: grid;
			min-height: 96px;
			place-items: center;
			overflow: hidden;
			border: var(--border-base) dashed var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			// Once there is a photo the box stops inviting a drop and just frames what is there.
			&--filled {
				border-style: solid;
				border-color: var(--color-border);
			}
		}
		&__image img {
			display: block;
			width: 100%;
			height: 100%;
			object-fit: cover;
		}
		&__image-add {
			display: grid;
			width: 100%;
			height: 100%;
			place-items: center;
			border: 0;
			background: transparent;
			color: var(--color-interactive);
			cursor: pointer;

			:global(svg) {
				width: 22px;
				height: 22px;
			}
			&:hover:not(:disabled) {
				color: var(--color-interactive--hover);
				background: var(--color-interactive--background--subtle--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				cursor: not-allowed;
			}
		}
		// Replace and remove sit stacked on the photo and are always visible, so nobody has to guess that
		// a saved photo can still be swapped.
		&__image-tools {
			position: absolute;
			top: var(--space-smallest);
			right: var(--space-smallest);
			display: grid;
			gap: var(--space-smallest);
		}
		&__image-tool {
			display: grid;
			width: 22px;
			height: 22px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			box-shadow: var(--shadow-low);
			cursor: pointer;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				cursor: not-allowed;
				opacity: 0.6;
			}
			&--replace {
				color: var(--color-interactive);

				&:hover:not(:disabled) {
					color: var(--color-interactive--hover);
				}
			}
			&--remove {
				color: var(--color-critical);

				&:hover:not(:disabled) {
					color: var(--color-critical--onSurface);
				}
			}
		}
		&__image-loading {
			width: 22px;
			height: 22px;
			border: 2px solid var(--color-border);
			border-top-color: var(--color-interactive);
			border-radius: var(--radius-circle);
			animation: pricing-card-spin 0.8s linear infinite;
		}
	}

	@keyframes pricing-card-spin {
		to {
			transform: rotate(360deg);
		}
	}

	// Reading a priced request is reading a bill, so the saved state is a plain table: one row per line,
	// the wording on the left, the figures lined up on the right.
	.pricing-table__scroll {
		overflow-x: auto;
	}

	.pricing-table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--typography--fontSize-base);

		th,
		td {
			padding: var(--space-slim) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
			text-align: left;
			vertical-align: top;
		}
		thead th {
			color: var(--color-text);
			background: var(--color-surface--background--subtle);
			font-weight: 700;
			white-space: nowrap;
		}
		tbody th {
			font-weight: 400;
		}
		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: 0;
		}
		th.pricing-table__number,
		td.pricing-table__number {
			text-align: right;
			white-space: nowrap;
		}
		&__name {
			display: block;
			color: var(--color-heading);
			font-weight: 600;
		}
		&__description {
			display: block;
			padding-top: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__choice {
			display: block;
			padding-top: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__heading th {
			background: var(--color-surface--background--subtle);
		}
		&__photo {
			width: 72px;

			img {
				display: block;
				width: 56px;
				height: 56px;
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
				object-fit: cover;
			}
		}
	}

	@media (max-width: 767px) {
		// Four columns will not fit a phone. The name keeps a full row of its own, the three figures pair
		// up underneath it, and the photo drops below the description.
		.pricing-card__row1 {
			grid-template-columns: 1fr 1fr;
		}
		.pricing-card__name {
			grid-column: 1 / -1;
		}
		.pricing-card__row2 {
			grid-template-columns: 1fr;
		}
		.pricing-card__description {
			grid-column: auto;
		}
		.pricing-card__image {
			min-height: 120px;
		}
	}
</style>
