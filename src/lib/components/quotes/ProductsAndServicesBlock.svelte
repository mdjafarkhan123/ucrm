<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { onDestroy, tick, untrack, type Snippet } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { flip } from 'svelte/animate';
	import { dragHandleZone, dragHandle } from 'svelte-dnd-action';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import QuantityInput from '$lib/components/forms/QuantityInput.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import CatalogItemPicker from './CatalogItemPicker.svelte';
	import CatalogItemDialog from './CatalogItemDialog.svelte';
	import PriceBookDrawer from './PriceBookDrawer.svelte';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { createImageThumbnail } from '$lib/collaboration/image-thumbnail';
	import { MAX_ATTACHMENT_SIZE_BYTES } from '$lib/collaboration/attachment-limits';
	import {
		startFileUpload,
		finishFileUpload,
		releaseLinePhoto,
		fileImageUrl
	} from '$lib/files/api';
	import type { FileProcessingState } from '$lib/files/api';
	import PhotoSlot from '$lib/components/files/PhotoSlot.svelte';
	import {
		catalogItemsPagesKey,
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
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
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
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import circlePlusIcon from '@tabler/icons/outline/circle-plus.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import toolIcon from '@tabler/icons/outline/tool.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

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
		showServiceDate = false,
		carrySourceLine = false,
		progressColumn = false,
		subtotalMinor,
		attachTo = null,
		alwaysEditing = false,
		editorTotalLabel = 'Subtotal',
		totalLabel = 'Subtotal',
		saveLabel = 'Save pricing',
		lockedMessage = '',
		hint,
		icon,
		tone,
		clientSees,
		flush = false,
		emptyDescription = 'Add the products and services this job needs before it becomes a quote.',
		totalRows,
		onSave,
		onDraftChange,
		onEditStart,
		onEditCancel,
		pricingControls,
		clientView,
		conceptTotals,
		pendingChanges = false,
		concept = false
	}: {
		/** The concept look (Job details `tNdkX`): each saved line leads with its photo, or a Product /
		 *  Service tile, and carries a Product / Service pill after its name. */
		concept?: boolean;
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
		/** Invoice-only: shows a per-line "Service date" field. Off for quotes/requests/jobs, which have none. */
		showServiceDate?: boolean;
		/**
		 * Visit-pricing-only: carries each row's `source_job_line_item_id` from the saved lines back out
		 * through the draft, so a job line the visit changed stays that job line instead of turning into a
		 * new visit-only line on every save.
		 */
		carrySourceLine?: boolean;
		/**
		 * Progress-invoice-only: splits the saved table's money into "Item total" — the whole item, from
		 * `progress_original_amount_minor` — and "Due this invoice", the share this payment stage bills. The
		 * editor is never shown for these lines, because a progress bill's amounts belong to the job's
		 * payment schedule rather than to the invoice.
		 */
		progressColumn?: boolean;
		/** Exact selected subtotal returned by the database; Quote screens must provide it. */
		subtotalMinor?: number | null;
		/** Where a line photo is stored. Null means there is nothing to attach it to yet, so no photos. */
		attachTo?: { entityType: 'request' | 'quote'; entityId: string } | null;
		/** The new-quote form types straight into the rows and saves from the page's own footer. */
		alwaysEditing?: boolean;
		/** What the editor's own action bar calls the running total, e.g. "Request subtotal". */
		editorTotalLabel?: string;
		/** What the saved table's total row is called, e.g. "Request subtotal". */
		totalLabel?: string;
		saveLabel?: string;
		lockedMessage?: string;
		/** A quiet line under the title in the App look, e.g. "4 items · work done Sep 29 – Oct 3". */
		hint?: string;
		/** The title tile's icon (a Tabler SVG) and colour family, for a page that gives the block its own. */
		icon?: string;
		tone?: string;
		/** What the client's copy shows, e.g. "Client sees every figure". Sits at the end of the locked strip. */
		clientSees?: string;
		/** App look: the saved table runs edge to edge in the card and the totals and locked note close it
		 *  as strips along the foot. Leave off to keep the table inside the card's side padding. */
		flush?: boolean;
		emptyDescription?: string;
		/** App look: the saved table closes with these rows (subtotal, tax, total) in place of the single
		 *  subtotal line. The last row reads as the grand total. Formatted by the page, which owns the money. */
		totalRows?: { label: string; value: string }[];
		onSave?: (
			expectedRevision: number,
			lines: RequestPricingLineInput[],
			linesChanged: boolean
		) => Promise<void>;
		onDraftChange?: (lines: RequestPricingLineInput[], subtotalMinor: number) => void;
		onEditStart?: () => void;
		onEditCancel?: () => void;
		pricingControls?: Snippet;
		/** Quote-only controls rendered where Jobber puts them: below the line editor actions. */
		clientView?: Snippet;
		/** Concept edit mode: what follows the subtotal in the totals panel (discount, tax, total). Told
		 *  whether the lines' money has moved since the save, so saved figures are not shown as current. */
		conceptTotals?: Snippet<[{ linesChanged: boolean }]>;
		/** The page holds unsaved changes of its own in this edit (discount, tax), so closing asks first. */
		pendingChanges?: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

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
		image_file_id: string | null;
		/** A photo picked before its request or quote exists. It stays in the browser until page Save. */
		imageFile: File | null;
		imageThumbnail: Blob | null;
		imagePreviewUrl: string;
		imageUploading: boolean;
		/** A saved line's photo is assumed already checked; one uploaded this session starts 'pending'. */
		imageProcessingState: FileProcessingState;
		/** This line came from a saved item whose cost the API withheld, so nothing here may write one. */
		costHidden: boolean;
		line_kind: QuoteLineKind;
		selection_kind: QuoteSelectionKind;
		is_recommended: boolean;
		/** Invoice-only: the date this line's work was done. Null until set; ignored unless showServiceDate. */
		service_date?: string | null;
		/** Visit-pricing-only: where this row came from. Absent on a row the person added here. */
		source_job_line_item_id?: string | null;
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
	// Photos uploaded during this edit session that have not been claimed by a save yet. Cancelling, or
	// swapping/removing one before Save, deletes it so a picked-then-discarded photo does not sit in
	// storage forever. Never touches a photo that was already on a saved line before this session started.
	const uploadedThisSession = new Set<string>();
	// Photo file ids already on savedLines when this edit session opened. Save diffs this against what it
	// is about to persist and releases each one it drops. A line photo is shared -- a quote's is its
	// request's File, a job's its quote's -- so the server trashes it only when nothing uses it any more.
	let entrySavedFileIds = new Set<string>();

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
			image_file_id: line.image_file_id,
			imageFile: null,
			imageThumbnail: null,
			imagePreviewUrl: '',
			imageUploading: false,
			imageProcessingState: 'available',
			costHidden: false,
			line_kind: line.line_kind ?? 'priced',
			selection_kind: line.selection_kind ?? 'required',
			is_recommended: line.is_recommended ?? false,
			service_date: line.service_date ?? null,
			source_job_line_item_id: line.source_job_line_item_id ?? null
		};
	}

	// The form that types straight into the rows is in edit mode from the moment it appears.
	const isEditing = $derived(alwaysEditing || editing);

	function openEdit() {
		onEditStart?.();
		draftLines = savedLines.map(toDraft);
		entrySavedFileIds = new Set(
			savedLines
				.map((line) => line.image_file_id)
				.filter((fileId): fileId is string => Boolean(fileId))
		);
		error = '';
		notice = '';
		editing = true;
	}

	// A form that types straight into the rows opens empty and stays that way — except when it opens pre-filled,
	// the way "bill a whole job" hands this the job's priced lines. Those arrive a beat after mount, so this
	// adopts them the moment they land, keyed on their identity so a later re-render never overwrites edits the
	// person has since made. Every other always-editing caller passes no lines, so this stays a no-op for them.
	let adoptedFrom = $state<string | null>(null);
	$effect(() => {
		if (!alwaysEditing || savedLines.length === 0) return;
		const key = savedLines.map((line) => line.id).join(',');
		if (adoptedFrom === key) return;
		adoptedFrom = key;
		untrack(() => {
			draftLines = savedLines.map(toDraft);
		});
	});

	// What the page's own footer saves, and what the rail's Overview adds up while somebody types.
	$effect(() => {
		if (!alwaysEditing || !onDraftChange) return;
		const payload = toInputs(draftLines);
		const subtotal = draftSubtotal(draftLines);
		untrack(() => onDraftChange(payload, subtotal));
	});

	async function discardIfOrphaned(fileId: string) {
		if (!uploadedThisSession.has(fileId)) return;
		uploadedThisSession.delete(fileId);
		try {
			await releaseLinePhoto(fileId);
		} catch (caught) {
			console.error('Could not clean up an unsaved line photo.', fileId, caught);
		}
	}

	/** Save already persisted this removal; this only lets a photo nothing shows any more reach Trash
	 *  rather than linger as an untracked orphan. One another record still uses is left where it is. */
	async function releaseDroppedSavedPhoto(fileId: string) {
		try {
			await releaseLinePhoto(fileId);
		} catch (caught) {
			console.error('Could not clean up a removed line photo.', fileId, caught);
		}
	}

	function closeEdit() {
		onEditCancel?.();
		for (const line of draftLines) releaseLocalPreview(line);
		for (const fileId of [...uploadedThisSession]) void discardIfOrphaned(fileId);
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
			!line.image_file_id &&
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
			image_file_id: string | null;
			imageFile?: File | null;
			line_kind?: QuoteLineKind;
			selection_kind?: QuoteSelectionKind;
			is_recommended?: boolean;
			service_date?: string | null;
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
				line.image_file_id ?? '',
				line.line_kind ?? 'priced',
				line.selection_kind ?? 'required',
				line.is_recommended ?? false,
				line.service_date ?? '',
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

	// Only quantity, price and taxability move the money; a new description or photo leaves it alone.
	const moneyKey = (
		rows: {
			quantity: number | null;
			unit_price_minor: number | null;
			is_taxable?: boolean | null;
		}[]
	) =>
		rows
			.map((row) => `${row.quantity ?? 0}:${row.unit_price_minor ?? 0}:${row.is_taxable ?? true}`)
			.sort()
			.join('|');
	const linesMoneyChanged = $derived(
		isEditing &&
			moneyKey(draftLines.filter((line) => !isUntouchedLine(line))) !== moneyKey(savedLines)
	);

	function requestClose() {
		if (dirty || pendingChanges) {
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

	// The empty card's second way in: open the lines and the Price book drawer together.
	function openEditWithPriceBook() {
		openEdit();
		openPriceBook();
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
				image_file_id: null,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false,
				imageProcessingState: 'available',
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
		if (line?.image_file_id) void discardIfOrphaned(line.image_file_id);
		draftLines = draftLines.filter((entry) => entry.id !== id);
	}

	function updateLine(id: string, patch: Partial<DraftLine>) {
		draftLines = draftLines.map((line) => (line.id === id ? { ...line, ...patch } : line));
	}

	function handleReorder(event: CustomEvent<{ items: DraftLine[] }>) {
		draftLines = event.detail.items;
	}

	// The item's photo comes with it, like its name and price. An item without one leaves whatever photo
	// the line already had.
	function catalogPhoto(item: CatalogItem): Partial<DraftLine> {
		if (!item.image_file_id) return {};
		return {
			image_file_id: item.image_file_id,
			imageFile: null,
			imageThumbnail: null,
			imagePreviewUrl: '',
			imageProcessingState: 'available'
		};
	}

	function applyCatalogItem(id: string, item: CatalogItem) {
		const line = draftLines.find((entry) => entry.id === id);
		if (line && item.image_file_id && line.image_file_id !== item.image_file_id) {
			releaseLocalPreview(line);
			if (line.image_file_id) void discardIfOrphaned(line.image_file_id);
		}
		updateLine(id, {
			...catalogPhoto(item),
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
				image_file_id: item.image_file_id ?? null,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false,
				imageProcessingState: 'available',
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
				image_file_id: null,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false,
				imageProcessingState: 'available',
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
			queryKey: catalogItemsPagesKey({}),
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

	function removeImage(id: string) {
		const line = draftLines.find((entry) => entry.id === id);
		if (line) releaseLocalPreview(line);
		if (line?.image_file_id) void discardIfOrphaned(line.image_file_id);
		updateLine(id, {
			image_file_id: null,
			imageFile: null,
			imageThumbnail: null,
			imagePreviewUrl: '',
			imageProcessingState: 'available'
		});
	}

	/** Puts a line photo's bytes in the File Manager, linked to this record as a 'line_photo'. */
	async function uploadLinePhoto(file: File, entityType: 'request' | 'quote', entityId: string) {
		const started = await startFileUpload(file, {
			originType: entityType,
			originId: entityId,
			originRole: 'line_photo'
		});
		await uploadAttachmentFile(started.upload_url, file);
		// Saying the bytes landed is what makes the File claimable by the processing worker. Until it has
		// been checked the photo is not usable yet, which is what the pending state below shows.
		await finishFileUpload(started.file.id);
		uploadedThisSession.add(started.file.id);
		return started.file.id;
	}

	async function handleFileChosen(id: string, file: File) {
		if (!file.type.startsWith('image/')) {
			error = 'Only a photo can be attached to a line.';
			return;
		}
		if (file.size > MAX_ATTACHMENT_SIZE_BYTES) {
			error = 'That photo is over 25 MB.';
			return;
		}

		const previousFileId = draftLines.find((line) => line.id === id)?.image_file_id ?? null;
		updateLine(id, { imageUploading: true });

		try {
			// A create form has no server record yet. Jobber still shows the image box immediately, so keep
			// the photo and its preview locally and let the page's Save hand us the new record id later.
			if (!attachTo) {
				const thumbnail = await createImageThumbnail(file);
				const current = draftLines.find((line) => line.id === id);
				if (current) releaseLocalPreview(current);
				updateLine(id, {
					image_file_id: null,
					imageFile: file,
					imageThumbnail: thumbnail,
					imagePreviewUrl: URL.createObjectURL(thumbnail ?? file),
					imageUploading: false
				});
				return;
			}
			const fileId = await uploadLinePhoto(file, attachTo.entityType, attachTo.entityId);
			updateLine(id, {
				image_file_id: fileId,
				imageUploading: false,
				imageProcessingState: 'pending'
			});
			if (previousFileId) void discardIfOrphaned(previousFileId);
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
		if (!file) return true;
		updateLine(line.id, { imageUploading: true });

		try {
			const fileId = await uploadLinePhoto(file, entityType, entityId);
			releaseLocalPreview(line);
			updateLine(line.id, {
				image_file_id: fileId,
				imageFile: null,
				imageThumbnail: null,
				imagePreviewUrl: '',
				imageUploading: false,
				imageProcessingState: 'pending'
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
		for (const fileId of [...uploadedThisSession]) void discardIfOrphaned(fileId);
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

	const anyLinePhoto = $derived(savedLines.some((line) => line.image_file_id));
	// The concept look puts the photo inside the line's own cell, so it needs no column of its own.
	const photoColumn = $derived(anyLinePhoto && !concept);

	// A priced progress bill drops quantity and unit price. Its lines are a stage's share spread across the
	// job's items, stored as a single lump priced at that share, so a per-unit reading of them is false: the
	// row would claim 1 x the share equals the whole item. Jobber shows the two money columns alone. Quantity
	// survives when money is withheld, because then it is all the table has left to say.
	const progressMoney = $derived(showPrices && progressColumn);

	// How wide the saved table is, so a heading row's single cell spans all of it: line item, optional photo,
	// quantity unless the progress pair replaced it, and — with prices — two money columns either way.
	const savedColumnCount = $derived(
		1 + (photoColumn ? 1 : 0) + (progressMoney ? 0 : 1) + (showPrices ? 2 : 0)
	);

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
				image_file_id: line.image_file_id,
				...(showServiceDate ? { service_date: line.service_date ?? null } : {}),
				...(carrySourceLine
					? { source_job_line_item_id: line.source_job_line_item_id ?? null }
					: {}),
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
			const finalFileIds = new Set(
				draftLines
					.map((line) => line.image_file_id)
					.filter((fileId): fileId is string => Boolean(fileId))
			);
			await onSave(revision, toInputs(draftLines), dirty);
			for (const fileId of entrySavedFileIds) {
				if (!finalFileIds.has(fileId)) void releaseDroppedSavedPhoto(fileId);
			}
			uploadedThisSession.clear();
			editing = false;
			draftLines = [];
			toast.success(saveLabel === 'Save job pricing' ? 'Job pricing saved' : 'Pricing saved');
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
{#snippet addOnPill(recommended: boolean)}
	<span class={['pricing-addon', recommended && 'pricing-addon--recommended']}>
		<span class="pricing-addon__icon" aria-hidden="true"
			>{@html recommended ? starIcon : circlePlusIcon}</span
		>
		{recommended ? 'Recommended add-on' : 'Optional add-on'}
	</span>
{/snippet}

{#snippet emptyChoices(onAdd: () => void, onPick: () => void)}
	<div class="pricing-empty__choices">
		<button type="button" class="pricing-empty__choice" disabled={saving} onclick={onAdd}>
			<IconTile icon={plusIcon} tone="job" />
			<span class="pricing-empty__choice-text">
				<span class="pricing-empty__choice-title">Add a line item</span>
				<span class="pricing-empty__choice-hint">Type a name, quantity and price</span>
			</span>
			<span class="pricing-empty__choice-arrow" aria-hidden="true">{@html chevronRightIcon}</span>
		</button>
		<button
			type="button"
			class="pricing-empty__choice"
			disabled={saving}
			onmouseenter={warmPriceBook}
			onfocus={warmPriceBook}
			onclick={onPick}
		>
			<IconTile icon={bookIcon} tone="quote" />
			<span class="pricing-empty__choice-text">
				<span class="pricing-empty__choice-title">Pick from the price book</span>
				<span class="pricing-empty__choice-hint">Your saved products and services</span>
			</span>
			<span class="pricing-empty__choice-arrow" aria-hidden="true">{@html chevronRightIcon}</span>
		</button>
	</div>
{/snippet}

<SectionBlock
	title="Products and services"
	icon={icon ?? (concept ? packageIcon : listIcon)}
	tone={tone ?? (concept ? 'quote' : undefined)}
	level={2}
	hint={concept && isEditing && !alwaysEditing
		? draftLines.length > 1
			? 'Editing · drag ⠿ to reorder'
			: 'Editing'
		: concept && loading
			? 'Loading…'
			: concept && loadFailed
				? "Couldn't load"
				: concept && !isEditing && savedLines.length === 0
					? 'Nothing priced yet'
					: hint}
	class={[
		flush &&
			(concept
				? !loading && !loadFailed && (isEditing || savedLines.length > 0)
				: !isEditing && !loading && !loadFailed && savedLines.length > 0) &&
			'section-block--flush',
		concept && isEditing && !alwaysEditing && 'pricing-block--editing',
		concept && 'pricing-block--concept'
	]
		.filter(Boolean)
		.join(' ')}
>
	{#snippet actions()}
		{#if editable && !isEditing && savedLines.length > 0}
			<PencilButton onclick={openEdit} label="Edit products and services" />
		{/if}
	{/snippet}

	{#if notice}<p class="pricing-block__notice" role="status">{notice}</p>{/if}

	{#if concept && quoteChoices && !editable && lockedMessage && !loading && !loadFailed}
		<p class="pricing-block__band">
			<span class="pricing-block__strip-icon" aria-hidden="true">{@html lockIcon}</span>
			{lockedMessage}
		</p>
	{/if}

	{#if loading && concept}
		<LoadingSkeleton variant="table" rows={3} label="Loading pricing" />
	{:else if loading}
		<p class="pricing-block__hint">Loading pricing…</p>
	{:else if loadFailed && concept}
		<ErrorState
			title="Couldn't load the pricing"
			description="Something went wrong on our side. Reload the page to try again."
		/>
	{:else if loadFailed}
		<p class="pricing-block__error" role="alert">That pricing could not be loaded.</p>
	{:else if isEditing}
		<div class={['pricing-edit', concept && 'pricing-edit--concept concept-fields']}>
			{#if draftLines.length === 0}
				{#if concept && alwaysEditing}
					<div class="pricing-empty">
						<p class="pricing-empty__line">Nothing priced yet. Choose how to start.</p>
						{@render emptyChoices(addLine, openPriceBook)}
					</div>
				{:else}
					<p class="pricing-block__hint">
						Nothing priced yet. Add a line item, or pick one out of the price book.
					</p>
				{/if}
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
					<div
						class={['pricing-card', concept && 'pricing-card--concept']}
						animate:flip={{ duration: 150 }}
					>
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
											label={concept ? 'Name · from your price book' : 'Name'}
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
										{currencyCode}
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
									<div class="pricing-card__image">
										{#if concept}<span class="pricing-card__photo-label">Photo</span>{/if}
										<PhotoSlot
											addText={concept ? 'Add photo' : undefined}
											previewUrl={line.imagePreviewUrl}
											fileId={line.image_file_id}
											processingState={line.imageProcessingState}
											uploading={line.imageUploading}
											disabled={saving}
											label={line.name || 'Line photo'}
											onChoose={(file) => void handleFileChosen(line.id, file)}
											onRemove={() => removeImage(line.id)}
										/>
									</div>
								</div>
								{#if showServiceDate && !concept}
									<div class="pricing-card__service-date">
										<CalendarPicker
											id={`pricing-service-date-${line.id}`}
											label="Service date"
											{locale}
											disabled={saving}
											bind:value={
												() => calendarDateFromString(line.service_date),
												(value) =>
													updateLine(line.id, { service_date: calendarDateToString(value) })
											}
										/>
										{#if line.service_date}
											<Button
												size="small"
												variant="tertiary"
												disabled={saving}
												onclick={() => updateLine(line.id, { service_date: null })}
											>
												Clear
											</Button>
										{/if}
									</div>
								{/if}
								{#if concept}
									<div class="pricing-card__kind-row">
										<span
											class={[
												'pricing-card__kind',
												line.category === 'service' && 'pricing-card__kind--service'
											]}>{line.category === 'service' ? 'Service' : 'Product'}</span
										>
										<span class="pricing-card__kind-note"
											>{line.is_taxable ? 'Taxed' : 'Not taxed'}{line.catalog_item_id
												? ' · from the price book'
												: ''}</span
										>
										{#if showServiceDate}
											<span class="pricing-card__date">
												<span class="pricing-card__date-label">Service date</span>
												<CalendarPicker
													id={`pricing-service-date-${line.id}`}
													label="Service date"
													hideLabel
													size="small"
													{locale}
													disabled={saving}
													bind:value={
														() => calendarDateFromString(line.service_date),
														(value) =>
															updateLine(line.id, { service_date: calendarDateToString(value) })
													}
												/>
												{#if line.service_date}
													<button
														type="button"
														class="pricing-card__date-clear"
														aria-label="Clear the service date"
														disabled={saving}
														onclick={() => updateLine(line.id, { service_date: null })}
														>{@html xIcon}</button
													>
												{/if}
											</span>
										{/if}
									</div>
								{/if}
							{/if}
						</div>
						<div class="pricing-card__actions">
							<DropdownMenu
								triggerLabel="Line actions"
								triggerClass={concept
									? undefined
									: 'dropdown-menu__trigger pricing-card__menu-trigger'}
								disabled={saving}
								items={lineMenuItems(line)}
							/>
						</div>
					</div>
				{/each}
			</div>
			<div class="pricing-block__footer">
				{#if !(concept && alwaysEditing && draftLines.length === 0)}
					<Button
						size="small"
						variant={concept ? 'secondary' : 'tertiary'}
						disabled={saving}
						onclick={addLine}
					>
						{#if concept}<span class="pricing-block__price-book-icon" aria-hidden="true"
								>{@html plusIcon}</span
							>{/if}
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
							<span class="pricing-block__price-book-icon" aria-hidden="true">{@html bookIcon}</span
							>
							Price book
						</Button>
					</span>
				{/if}
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
				{#if concept}
					<div class="pricing-block__client-view">{@render clientView()}</div>
				{:else}
					{@render clientView()}
				{/if}
			{/if}
			{#if concept && showPrices}
				<div class="pricing-block__concept-totals">
					<div class="pricing-block__concept-panel">
						{#if alwaysEditing}
							<!-- A record not saved yet has no discount or tax, so its subtotal is the figure. -->
							<div class="pricing-block__concept-figure">
								<span>{editorTotalLabel}</span>
								<span>{formatMoney(draftSubtotal(draftLines))}</span>
							</div>
						{:else}
							<div class="pricing-block__concept-subtotal">
								<span>{quoteChoices ? 'Required subtotal' : 'Subtotal'}</span>
								<span>{formatMoney(draftSubtotal(draftLines))}</span>
							</div>
						{/if}
						{@render conceptTotals?.({ linesChanged: linesMoneyChanged })}
					</div>
				</div>
			{:else if !concept}
				<div class="pricing-block__totals">
					<div class="pricing-block__totals-row">
						<span>Subtotal</span>
						<span>{formatMoney(draftSubtotal(draftLines))}</span>
					</div>
				</div>
			{/if}
			{#if pricingControls}
				<div class="pricing-block__pricing-controls">{@render pricingControls()}</div>
			{/if}
			{#if concept && editing && onSave}
				<div class="pricing-block__save-bar">
					{#if error}
						<p class="pricing-block__error" role="alert">{error}</p>
					{:else}
						<span class="pricing-block__save-status"
							>{dirty || pendingChanges ? 'Unsaved changes' : 'No changes yet'}</span
						>
					{/if}
					<Button variant="secondary" onclick={requestClose} disabled={saving}>Cancel</Button>
					<Button variant="primary" onclick={() => void save()} loading={saving}>
						<span class="pricing-block__price-book-icon" aria-hidden="true">{@html checkIcon}</span
						>Save changes
					</Button>
				</div>
			{/if}
		</div>
	{:else if savedLines.length === 0 && concept}
		<div class="pricing-empty">
			<p class="pricing-empty__line">{emptyDescription}</p>
			{#if editable}
				{@render emptyChoices(openEditWithFirstLine, openEditWithPriceBook)}
			{/if}
		</div>
	{:else if concept && !showPrices}
		<!-- Prices hidden (`vsT0H` row 2): the crew's work list — what to bring and do, without money. -->
		<ul class="pricing-crew">
			{#each savedLines as line (line.id)}
				{#if quoteChoices && line.line_kind === 'heading'}
					<li class="pricing-crew__group">{line.name}</li>
				{:else}
					<li class="pricing-crew__line">
						{#if quoteChoices && line.line_kind === 'text'}
							<IconTile icon={fileTextIcon} tone="inactive" size={56} />
						{:else if line.image_file_id}
							<img
								class="pricing-crew__photo"
								src={fileImageUrl(line.image_file_id, 'thumb')}
								alt=""
								loading="lazy"
							/>
						{:else}
							<IconTile
								icon={line.category === 'service' ? toolIcon : packageIcon}
								tone={line.category === 'service' ? 'job' : 'quote'}
								size={56}
							/>
						{/if}
						{#if !(quoteChoices && line.line_kind === 'text')}
							<span class="pricing-crew__count"
								>{line.quantity}{line.unit_label ? ` ${line.unit_label}` : '×'}</span
							>
						{/if}
						<span class="pricing-crew__text">
							<span class="pricing-crew__title">
								<span class="pricing-crew__name">{line.name}</span>
								{#if !(quoteChoices && line.line_kind === 'text') && line.category}
									<span
										class={[
											'pricing-table__kind',
											line.category === 'service' && 'pricing-table__kind--service'
										]}>{line.category === 'service' ? 'Service' : 'Product'}</span
									>
								{/if}
								{#if quoteChoices && line.selection_kind === 'optional'}
									{@render addOnPill(line.is_recommended)}
								{/if}
							</span>
							{#if line.description}
								<span class="pricing-crew__description">{line.description}</span>
							{/if}
						</span>
					</li>
				{/if}
			{/each}
		</ul>
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
			<table class={['pricing-table', concept && 'pricing-table--concept']}>
				<thead>
					<tr>
						<th scope="col">{concept ? 'Product or service' : 'Line item'}</th>
						{#if photoColumn}
							<th scope="col" class="pricing-table__photo" aria-label="Photo"></th>
						{/if}
						{#if !progressMoney}
							<th scope="col" class="pricing-table__number">{concept ? 'Qty' : 'Quantity'}</th>
						{/if}
						{#if showPrices}
							{#if progressMoney}
								<th scope="col" class="pricing-table__number">Item total</th>
								<th scope="col" class="pricing-table__number">Due this invoice</th>
							{:else}
								<th scope="col" class="pricing-table__number">Unit price</th>
								<th scope="col" class="pricing-table__number">Total</th>
							{/if}
						{/if}
					</tr>
				</thead>
				<tbody>
					{#each savedLines as line (line.id)}
						{#if concept && quoteChoices && line.line_kind === 'heading'}
							<tr class="pricing-table__group">
								<th scope="row" colspan={savedColumnCount}>
									<span class="pricing-table__group-title">{line.name}</span>
								</th>
							</tr>
						{:else if concept && quoteChoices && line.line_kind === 'text'}
							<tr>
								<th scope="row" colspan={savedColumnCount}>
									<span class="pricing-table__cell">
										<span class="pricing-table__lead">
											<IconTile icon={fileTextIcon} tone="inactive" />
										</span>
										<span class="pricing-table__text">
											<span class="pricing-table__name">{line.name}</span>
											{#if line.description}<span class="pricing-table__description"
													>{line.description}</span
												>{/if}
										</span>
									</span>
								</th>
							</tr>
						{:else if quoteChoices && line.line_kind !== 'priced'}
							<tr class:pricing-table__heading={line.line_kind === 'heading'}>
								<th scope="row" colspan={savedColumnCount}>
									<span class="pricing-table__name">{line.name}</span>
									{#if line.description}<span class="pricing-table__description"
											>{line.description}</span
										>{/if}
								</th>
							</tr>
						{:else}
							{@const addOn = concept && quoteChoices && line.selection_kind === 'optional'}
							<tr
								class={[
									addOn && 'pricing-table__addon',
									addOn && line.is_recommended && 'pricing-table__addon--recommended'
								]}
							>
								<th scope="row">
									<span class="pricing-table__cell">
										{#if concept}
											<span class="pricing-table__lead">
												{#if addOn}<span class="pricing-table__stripe" aria-hidden="true"
													></span>{/if}
												{#if line.image_file_id}
													<img
														class="pricing-table__thumb"
														src={fileImageUrl(line.image_file_id, 'thumb')}
														alt=""
														loading="lazy"
													/>
												{:else}
													<IconTile
														icon={line.category === 'service' ? toolIcon : packageIcon}
														tone={line.category === 'service' ? 'job' : 'quote'}
													/>
												{/if}
											</span>
										{/if}
										<span class="pricing-table__text">
											<span class="pricing-table__title">
												<span class="pricing-table__name">{line.name}</span>
												{#if concept && line.category}
													<span
														class={[
															'pricing-table__kind',
															line.category === 'service' && 'pricing-table__kind--service'
														]}>{line.category === 'service' ? 'Service' : 'Product'}</span
													>
												{/if}
												{#if addOn}
													{@render addOnPill(line.is_recommended)}
												{:else if quoteChoices && line.selection_kind === 'optional'}
													<span class="pricing-table__choice">
														<span class="pricing-table__choice-icon" aria-hidden="true"
															>{@html circlePlusIcon}</span
														>
														{line.is_recommended ? 'Recommended add-on' : 'Optional add-on'}
													</span>
												{/if}
											</span>
											{#if line.description}
												<span class="pricing-table__description">{line.description}</span>
											{/if}
										</span>
									</span>
								</th>
								{#if photoColumn}
									<td class="pricing-table__photo">
										{#if line.image_file_id}
											<img src={fileImageUrl(line.image_file_id, 'thumb')} alt="" loading="lazy" />
										{/if}
									</td>
								{/if}
								{#if !progressMoney}
									<td class="pricing-table__number">
										{line.quantity}{#if line.unit_label}&nbsp;{line.unit_label}{/if}
									</td>
								{/if}
								{#if showPrices}
									{#if progressMoney}
										<td class="pricing-table__number">
											{formatMoney(line.progress_original_amount_minor ?? line.line_total_minor)}
										</td>
									{:else}
										<td class="pricing-table__number">{formatMoney(line.unit_price_minor)}</td>
									{/if}
									<td class="pricing-table__number pricing-table__line-total">
										{formatMoney(line.line_total_minor)}
									</td>
								{/if}
							</tr>
						{/if}
					{/each}
				</tbody>
			</table>
		</div>
		{#if showPrices && totalRows && totalRows.length > 0}
			<div class="pricing-block__summary">
				<dl class="pricing-block__summary-list">
					{#each totalRows as row, index (row.label)}
						<div
							class={[
								'pricing-block__summary-row',
								index === totalRows.length - 1 && index > 0 && 'pricing-block__summary-row--total'
							]}
						>
							<dt>{row.label}</dt>
							<dd>{row.value}</dd>
						</div>
					{/each}
				</dl>
			</div>
		{:else if showPrices && concept}
			<div class="pricing-block__summary">
				<dl class="pricing-block__summary-list">
					<div class="pricing-block__summary-row pricing-block__summary-row--total">
						<dt>{progressColumn ? 'Due this invoice' : totalLabel}</dt>
						<dd>{formatMoney(savedSubtotal(savedLines))}</dd>
					</div>
				</dl>
			</div>
		{:else if showPrices}
			<div class="pricing-block__totals">
				<div class="pricing-block__totals-row">
					<span>{progressColumn ? 'Due this invoice' : totalLabel}</span>
					<span>{formatMoney(savedSubtotal(savedLines))}</span>
				</div>
			</div>
		{/if}
	{/if}

	{#if concept && !loading && !loadFailed && !isEditing && savedLines.length > 0}
		{@const footLocked = !editable && !quoteChoices ? lockedMessage : ''}
		{@const footClient = !editable && clientSees ? clientSees : ''}
		{#if footLocked || footClient || !showPrices}
			<div class="pricing-block__strip">
				{#if footLocked}
					<p class="pricing-block__strip-item">
						<span
							class={[
								'pricing-block__strip-icon',
								(showServiceDate || progressColumn) && 'pricing-block__strip-icon--invoice'
							]}
							aria-hidden="true">{@html lockIcon}</span
						>
						{footLocked}
					</p>
				{/if}
				{#if !showPrices}
					<p class="pricing-block__strip-item">
						<span
							class="pricing-block__strip-icon pricing-block__strip-icon--informative"
							aria-hidden="true">{@html eyeOffIcon}</span
						>
						Prices are hidden for your role.
					</p>
				{/if}
				{#if footClient && showPrices}
					<p class="pricing-block__strip-item">
						<span
							class="pricing-block__strip-icon pricing-block__strip-icon--client"
							aria-hidden="true">{@html eyeIcon}</span
						>
						{footClient}
					</p>
				{/if}
			</div>
		{/if}
	{:else if !concept && !editable && (lockedMessage || clientSees) && !loading && !loadFailed}
		<div class="pricing-block__locked">
			{#if lockedMessage}
				<p class="pricing-block__hint pricing-block__locked-note">
					<span class="pricing-block__locked-icon" aria-hidden="true">{@html lockIcon}</span>
					{lockedMessage}
				</p>
			{/if}
			{#if clientSees && savedLines.length > 0}
				<p class="pricing-block__client-sees">
					<span class="pricing-block__locked-icon" aria-hidden="true">{@html eyeIcon}</span>
					{clientSees}
				</p>
			{/if}
		</div>
	{/if}
</SectionBlock>

{#if editing && onSave && !concept}
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
{:else if error && !(concept && editing)}
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
		isLabor={catalogDraftLine.is_labor}
		imageFileId={catalogDraftLine.image_file_id}
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
	.pricing-block__pricing-controls {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.pricing-block {
		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		// App look: the totals sit under the table in a right-hand block, and the locked note runs along the
		// foot of the card as a quiet strip.
		&__summary {
			display: flex;
			justify-content: flex-end;
			padding: 16px 24px 20px;
			border-top: var(--border-base) solid var(--color-border);
		}
		&__summary-list {
			display: flex;
			width: min(300px, 100%);
			flex-direction: column;
			gap: 8px;
			margin: 0;
		}
		&__summary-row {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			font-size: 13px;
			font-weight: 500;

			dt {
				color: var(--color-text--secondary);
			}
			dd {
				margin: 0;
				color: var(--color-text);
				font-variant-numeric: tabular-nums;
			}

			&--total {
				padding-top: 10px;
				border-top: var(--border-base) solid var(--color-border);

				dt {
					color: var(--color-heading);
					font-size: var(--typography--fontSize-base);
					font-weight: 700;
				}
				dd {
					color: var(--color-heading);
					font-size: 18px;
					font-weight: 700;
					letter-spacing: -0.3px;
				}
			}
		}
		&__locked {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);
		}
		&__locked-note,
		&__client-sees {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__client-sees {
			margin-left: auto;
			color: var(--color-interactive);
			font-weight: 600;
		}
		&__locked-icon :global(svg) {
			display: block;
			width: 13px;
			height: 13px;
		}
		&__locked-note &__locked-icon {
			color: var(--color-icon--secondary);
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
			grid-template-columns: minmax(0, 3fr) minmax(108px, 1fr) minmax(140px, 1fr) minmax(
					110px,
					1fr
				);
			gap: var(--space-small);
		}
		&__row1 {
			align-items: start;
		}
		&__row2 {
			align-items: stretch;
		}
		// The service date is a narrow field, not a full row — it sits under the line with its Clear button
		// and never stretches to the width of the description above it.
		&__service-date {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);
			max-width: 16rem;
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
		&__image {
			display: grid;
			min-height: 96px;
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
		&__title,
		&__cell {
			display: block;
		}
		&__choice {
			display: block;
			padding-top: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__choice-icon {
			display: none;
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

	// App look: the saved table runs edge to edge inside its card — small uppercase column heads on the
	// tinted row, lines a little taller — and the figures keep their right-hand column.
	:global(.record-detail--cards) .pricing-table__scroll.pricing-table__scroll {
		margin: 0;
		border-top: var(--border-base) solid var(--color-border);
	}
	:global(.record-detail--cards) .pricing-table {
		th,
		td {
			padding: 14px 16px;
		}
		th:first-child,
		td:first-child {
			padding-left: 24px;
		}
		th:last-child,
		td:last-child {
			padding-right: 24px;
		}
		thead th {
			padding-block: 10px;
			color: var(--color-text--secondary);
			font-size: 11px;
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}
		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: var(--border-base) solid var(--color-border);
		}
		&__name {
			font-size: var(--typography--fontSize-base);
		}
		&__title {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 4px 8px;
		}
		&__choice {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			padding: 2px 8px;
			border: var(--border-base) solid var(--color-border);
			border-radius: 999px;
			background: var(--color-surface--background--subtle);
			font-size: 11px;
		}
		&__choice-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 11px;
				height: 11px;
			}
		}
	}

	// The strip along the foot of the saved card; only present when the card is flush, so it carries its
	// own padding. The totals block above it already drew its own top rule.
	:global(.record-detail--cards .section-block--flush) .pricing-block__locked {
		padding: 12px 24px;
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}

	@media (max-width: 1359px) {
		:global(.record-detail--cards) .pricing-table {
			th,
			td {
				padding-inline: 10px;
			}
			th:first-child,
			td:first-child {
				padding-left: 24px;
			}
			th:last-child,
			td:last-child {
				padding-right: 24px;
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

	// Concept look (`tNdkX`, every page since Batch 14 `vsT0H`): each line leads with a 40px photo, or a tile
	// in its kind's colour (Product in the quote colour, Service in the job colour), and names its kind in a pill.
	.pricing-table.pricing-table--concept {
		th,
		td {
			padding-block: var(--space-slim);
			vertical-align: middle;
		}
		th:first-child,
		td:first-child {
			padding-left: var(--space-medium);
		}
		th:last-child,
		td:last-child {
			padding-right: var(--space-medium);
		}
		thead th {
			padding-block: 10px;
			letter-spacing: 0.8px;
		}
		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: 0;
		}
		.pricing-table__cell {
			display: flex;
			align-items: center;
			gap: var(--space-base);
		}
		.pricing-table__text {
			display: block;
			min-width: 0;
		}
		.pricing-table__lead {
			display: inline-flex;
			flex: 0 0 auto;
		}
		.pricing-table__thumb {
			display: block;
			width: 40px;
			height: 40px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			object-fit: cover;
		}
		.pricing-table__kind {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			padding: 3px 10px;
			border-radius: var(--radius-circle);
			color: var(--color-quote--onSurface);
			background: var(--color-quote--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			&::before {
				content: '';
				width: 6px;
				height: 6px;
				border-radius: var(--radius-circle);
				background: var(--color-quote);
			}

			&--service {
				color: var(--color-job--onSurface);
				background: var(--color-job--surface);

				&::before {
					background: var(--color-job);
				}
			}
		}
		.pricing-table__line-total {
			color: var(--color-heading);
			font-weight: 600;
		}
		.pricing-table__description {
			font-size: var(--typography--fontSize-small);
		}

		// A heading line is a group title with a short bar in the quote colour, and no rule under it.
		.pricing-table__group th {
			padding: 18px var(--space-medium) 6px;
			border-bottom: 0;
		}
		.pricing-table__group-title {
			display: flex;
			align-items: center;
			gap: 10px;
			color: var(--color-heading);
			font-size: 16px;
			font-weight: 700;

			&::before {
				content: '';
				width: 4px;
				height: 18px;
				border-radius: 2px;
				background: var(--color-quote);
			}
		}

		// Add-ons the client may choose: tinted rows with a stripe in the same family; the money reads
		// quieter, since it is not in the total until the client picks it.
		.pricing-table__addon {
			th,
			td {
				background: var(--color-inactive--surface);
			}
			td,
			.pricing-table__line-total {
				color: var(--color-text--secondary);
			}
			.pricing-table__stripe {
				background: var(--color-inactive);
			}
			&--recommended {
				th,
				td {
					background: var(--color-warning--surface);
				}
				.pricing-table__stripe {
					background: var(--color-warning);
				}
			}
		}
		.pricing-table__lead:has(.pricing-table__stripe) {
			gap: var(--space-slim);
			align-items: center;
		}
		.pricing-table__stripe {
			width: 3px;
			height: 40px;
			border-radius: 2px;
		}
	}

	// The outlined pill naming an add-on: white, edged and iconed in its row's family.
	.pricing-addon {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 3px 8px;
		border: var(--border-base) solid var(--color-inactive);
		border-radius: var(--radius-circle);
		color: var(--color-inactive--onSurface);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		white-space: nowrap;

		&__icon {
			display: inline-flex;
			color: var(--color-inactive);

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}
		}

		&--recommended {
			border-color: var(--color-warning);
			color: var(--color-warning--onSurface);

			.pricing-addon__icon {
				color: var(--color-warning);
			}
		}
	}

	// Empty (`vsT0H` row 1): one quiet line, then two choice tiles side by side.
	.pricing-empty {
		display: flex;
		flex-direction: column;
		gap: 14px;

		&__line {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__choices {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
			gap: var(--space-slim);
		}

		&__choice {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 14px var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			color: inherit;
			background: var(--color-surface--background);
			font: inherit;
			text-align: left;
			cursor: pointer;
			transition:
				border-color var(--timing-base),
				background-color var(--timing-base);

			&:hover {
				border-color: var(--color-border--interactive--hover);
				background: var(--color-surface--hover);
			}
			&:active {
				background: var(--color-surface--active);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__choice-text {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
			min-width: 0;
		}

		&__choice-title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__choice-hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__choice-arrow {
			display: inline-flex;
			color: var(--color-icon--secondary);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}
	}

	// Prices hidden (`vsT0H` row 2): white line cards on the page colour, a count box, no money.
	.pricing-crew {
		display: flex;
		flex-direction: column;
		gap: 10px;
		margin: 0;
		padding: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background);
		list-style: none;

		&__group {
			display: flex;
			align-items: center;
			gap: 10px;
			padding: var(--space-small) var(--space-smaller) 0;
			color: var(--color-heading);
			font-size: 16px;
			font-weight: 700;

			&::before {
				content: '';
				width: 4px;
				height: 18px;
				border-radius: 2px;
				background: var(--color-quote);
			}
		}

		&__line {
			display: flex;
			align-items: center;
			gap: 14px;
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: 12px;
			background: var(--color-surface);
		}

		&__photo {
			display: block;
			flex: 0 0 auto;
			width: 56px;
			height: 56px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			object-fit: cover;
		}

		&__count {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			min-width: 52px;
			height: 36px;
			padding: 0 var(--space-small);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface--background);
			font-size: 16px;
			font-weight: 700;
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
		}

		&__text {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
		}

		&__title {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 4px var(--space-small);
		}

		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__description {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}

		// The kind pill borrows the table's look.
		:global(.pricing-table__kind) {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			padding: 3px 10px;
			border-radius: var(--radius-circle);
			color: var(--color-quote--onSurface);
			background: var(--color-quote--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			&::before {
				content: '';
				width: 6px;
				height: 6px;
				border-radius: var(--radius-circle);
				background: var(--color-quote);
			}
		}
		:global(.pricing-table__kind--service) {
			color: var(--color-job--onSurface);
			background: var(--color-job--surface);

			&::before {
				background: var(--color-job);
			}
		}
	}

	// A locked quote says so in an informative band right under the header.
	.pricing-block__band {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		padding: 10px var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		font-size: var(--typography--fontSize-label);
		font-weight: 500;

		.pricing-block__strip-icon {
			color: var(--color-informative);
		}
	}

	// The foot strip closing a saved card: why it is locked, hidden prices, what the client sees.
	.pricing-block__strip {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small) var(--space-base);
		padding: var(--space-slim) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background);
	}
	.pricing-block__strip-item {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-label);
		font-weight: 500;
	}
	.pricing-block__strip-icon {
		display: inline-flex;
		flex: 0 0 auto;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}

		color: var(--color-icon--secondary);

		&--invoice {
			color: var(--color-invoice);
		}
		&--informative {
			color: var(--color-informative);
		}
		&--client {
			color: var(--color-client);
		}
	}

	// Concept loading and couldn't load sit inside the card's body.
	:global(.pricing-block--concept) :global(.loading--table) {
		padding: 0;
	}
	:global(.pricing-block--concept) .pricing-block__summary {
		border-top: var(--border-base) solid var(--color-border);
	}

	// Concept (`tNdkX`): the totals sit in a soft grey panel under the table, with the Total in a
	// white box of its own.
	:global(.pricing-block--concept) .pricing-block__summary {
		padding: var(--space-base) var(--space-large) var(--space-large);
	}
	:global(.pricing-block--concept) .pricing-block__summary-list {
		width: min(360px, 100%);
		gap: var(--space-small);
		padding: var(--space-slim);
		border-radius: var(--radius-large);
		background: var(--color-surface--background--subtle);
	}
	:global(.pricing-block--concept) .pricing-block__summary-row {
		padding: 0 var(--space-small);

		&--total {
			padding: var(--space-slim) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			dd {
				font-size: var(--typography--fontSize-largest);
			}
		}
	}

	// Job details edit mode (`jFBRB`): the lines open up edge to edge with labels above their fields, each
	// line closes with its kind and tax note, the totals panel holds discount and tax in place, and the card
	// saves from its own foot. The card's border turns brand green while it is being edited.
	.pricing-edit {
		display: contents;

		&--concept {
			display: block;
		}
	}
	:global(.record-detail--cards .section-block--concept.pricing-block--editing),
	:global(.section-block--concept.pricing-block--editing) {
		border-color: var(--color-interactive);
	}
	.pricing-edit--concept {
		.pricing-block__hint {
			padding: var(--space-base) var(--space-medium);
		}
		.pricing-card-list {
			gap: 0;
		}
		.pricing-block__footer {
			gap: var(--space-small);
			padding: var(--space-base) var(--space-medium);
			border-bottom: var(--border-base) solid var(--color-border);
		}
	}
	.pricing-card--concept {
		gap: var(--space-small);
		padding: var(--space-base) var(--space-slim) var(--space-base) var(--space-small);
		border: 0;
		border-bottom: var(--border-base) solid var(--color-border);
		border-radius: 0;
		background: none;

		// The handle and the menu line up with the first row's boxes, below their labels.
		.pricing-card__handle {
			align-self: flex-start;
			width: 24px;
			height: 40px;
			margin-top: 25px;
		}
		.pricing-card__actions {
			min-width: 0;
			padding-top: 25px;
		}
		&:not(:has(.pricing-card__handle)) {
			padding-left: var(--space-medium);
		}
		.pricing-card__body {
			gap: var(--space-slim);
		}
		.pricing-card__row1,
		.pricing-card__row2 {
			grid-template-columns: minmax(0, 1fr) 108px 140px 110px;
			gap: var(--space-small);
		}
		.pricing-card__image {
			display: flex;
			flex-direction: column;
			gap: 6px;
			min-height: 0;

			:global(.photo-slot) {
				height: 72px;
				min-height: 72px;
			}
		}
		.pricing-card__description :global(textarea) {
			height: 72px;
			min-height: 72px;
		}
		.pricing-card__description :global(.textarea__footer) {
			display: none;
		}
	}
	.pricing-card__photo-label {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
	}
	.pricing-card__kind-row {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.pricing-card__kind {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 3px 10px;
		border-radius: var(--radius-circle);
		color: var(--color-quote--onSurface);
		background: var(--color-quote--surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		&::before {
			content: '';
			width: 6px;
			height: 6px;
			border-radius: var(--radius-circle);
			background: var(--color-quote);
		}

		&--service {
			color: var(--color-job--onSurface);
			background: var(--color-job--surface);

			&::before {
				background: var(--color-job);
			}
		}
	}
	.pricing-card__kind-note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.pricing-card__kind-row:has(.pricing-card__date) {
		flex-wrap: wrap;
	}
	// A small date box with × (`vsT0H` row 4): the calendar's own field sits inside without its frame.
	.pricing-card__date {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		height: 32px;
		padding: 0 6px 0 10px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&:focus-within {
			border-color: var(--color-interactive);
		}

		:global(.calendar-picker) {
			min-width: 0;
		}
		// The picker's own button is the box's calendar icon, in the invoice colour.
		:global(.calendar-picker__trigger) {
			color: var(--color-invoice);
			background: transparent;
		}
		:global(.calendar-picker__date-weekday) {
			display: none;
		}
		:global(.calendar-picker__control) {
			height: 28px;
			min-height: 0;
			border: 0;
			box-shadow: none;
			background: transparent;
		}
	}
	.pricing-card__date-label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-label);
		font-weight: 500;
		white-space: nowrap;
	}
	.pricing-card__date-clear {
		display: inline-grid;
		width: 22px;
		height: 22px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		&:hover:not(:disabled) {
			color: var(--color-icon);
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			cursor: not-allowed;
		}

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}
	}
	.pricing-block__concept-totals {
		display: flex;
		justify-content: flex-end;
		padding: var(--space-base) var(--space-medium) var(--space-medium);
	}
	.pricing-block__concept-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		width: min(480px, 100%);
		padding: var(--space-base) var(--space-base) var(--space-small);
		border-radius: var(--radius-large);
		background: var(--color-surface--background--subtle);
	}
	.pricing-block__concept-subtotal {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		color: var(--color-text--secondary);

		span:last-child {
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}
	}
	.pricing-block__concept-figure {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: 10px var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		span:first-child {
			flex: 1 1 auto;
			color: var(--color-heading);
			font-weight: 700;
		}
		span:last-child {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}
	}
	.pricing-block__save-bar {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);

		.pricing-block__error {
			flex: 1 1 auto;
			margin: 0;
			color: var(--color-critical);
		}
	}
	// The quote's client-view controls keep the edit's side padding.
	.pricing-block__client-view {
		padding: var(--space-small) var(--space-medium);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.pricing-block__save-status {
		flex: 1 1 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.pricing-card__body {
		container-type: inline-size;
	}
	@container (max-width: 600px) {
		.pricing-card__row1,
		.pricing-card--concept .pricing-card__row1 {
			grid-template-columns: repeat(3, minmax(0, 1fr));
		}
		.pricing-card__name {
			grid-column: 1 / -1;
		}
	}
	@container (max-width: 480px) {
		.pricing-card__row1,
		.pricing-card--concept .pricing-card__row1 {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.pricing-card__name {
			grid-column: 1 / -1;
		}
		.pricing-card__row2,
		.pricing-card--concept .pricing-card__row2 {
			grid-template-columns: minmax(0, 1fr);
		}
		.pricing-card__description,
		.pricing-card__image {
			grid-column: 1 / -1;
		}
	}
	@container (max-width: 300px) {
		.pricing-card__row1,
		.pricing-card--concept .pricing-card__row1 {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
