// Onboarding & Data Portability, Part 3: the Price Book import's brain.
//
// Given the parsed file rows, the chosen column mapping, and the match action, decide -- purely, row by row --
// what WOULD happen to each row: create / update / skip / hold / error. Nothing here touches the database; the
// route feeds it the organization's current active items and persists nothing else -- Review and Commit both
// call this same function fresh, so there is no batch state to go stale between them.
//
// The identity rule mirrors what the database itself already enforces (create_catalog_item /
// update_catalog_item): two ACTIVE items in one organization can never share a name, compared case- and
// space-insensitively. That is the dedupe key here, the same way email/phone is for clients:
//   * A row's name matches an active item -> Skip or Update (never a second copy).
//   * Two file rows resolve to the same name -> the first is processed; the second is held for a human.
//   * A row that fails validation (bad type, bad price) -> error, with a plain reason.
// An archived item never blocks or absorbs a create -- the database allows a new active item to reuse an
// archived name, and Review does the same.

import { catalogItemCreateSchema } from '$lib/server/validation/quotes.schema';
import type { PricingCategory } from '$lib/server/validation/quotes.schema';
import type { ImportCatalogTarget } from '$lib/server/validation/imports.schema';

export type ImportCatalogMapping = Record<
	string,
	{ field: ImportCatalogTarget; dont_overwrite?: boolean }
>;
export type CatalogMatchAction = 'skip' | 'update';

export type ExistingCatalogItem = {
	id: string;
	revision: number;
	category: PricingCategory;
	name: string;
	description: string | null;
	unit_label: string | null;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable: boolean;
	is_labor: boolean;
};

export type ResolvedCatalogItem = {
	category: PricingCategory;
	name: string;
	description: string | null;
	unit_label: string | null;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable: boolean;
	is_labor: boolean;
};

export type CatalogPlannedAction = 'create' | 'update' | 'skip' | 'hold' | 'error';

export type CatalogReviewRow = {
	source_row_number: number;
	planned_action: CatalogPlannedAction;
	// create: the whole new item. update: the whole replacement item (update_catalog_item always replaces).
	resolved_item: ResolvedCatalogItem | null;
	match_item_id: string | null;
	match_revision: number | null;
	flags: string[];
	error_message: string | null;
};

export type CatalogReviewSummary = {
	total: number;
	create: number;
	update: number;
	skip: number;
	hold: number;
	error: number;
};

export type CatalogReviewInputs = {
	rows: Record<string, string>[];
	mapping: ImportCatalogMapping;
	matchAction: CatalogMatchAction;
	// normalized name -> the active item it belongs to (archived items are never a match target).
	existingByName: Map<string, ExistingCatalogItem>;
};

// Trim + collapse internal whitespace + lowercase -- the same comparison `lower(name)` in
// create_catalog_item/update_catalog_item makes, plus the whitespace collapse so "Lawn  Mowing" and
// "Lawn Mowing" are recognised as the same item.
export function normalizeCatalogName(value: string): string {
	return value.trim().replace(/\s+/g, ' ').toLowerCase();
}

const CATEGORY_ALIASES: Record<string, PricingCategory> = {
	product: 'product',
	products: 'product',
	service: 'service',
	services: 'service'
};

function parseCategory(value: string): PricingCategory | null {
	return CATEGORY_ALIASES[value.trim().toLowerCase()] ?? null;
}

const TRUE_WORDS = new Set(['yes', 'y', 'true', '1']);
const FALSE_WORDS = new Set(['no', 'n', 'false', '0']);

// Empty cell -> undefined (no opinion, caller decides the default). Anything else must read as yes/no.
function parseBooleanish(value: string): boolean | undefined | 'invalid' {
	const trimmed = value.trim().toLowerCase();
	if (trimmed === '') return undefined;
	if (TRUE_WORDS.has(trimmed)) return true;
	if (FALSE_WORDS.has(trimmed)) return false;
	return 'invalid';
}

// "$1,234.56" / "1234.56" / "1234" -> minor units (cents), half-away-from-zero. Empty cell -> undefined.
function parseMoneyToMinor(value: string): number | undefined | 'invalid' {
	const trimmed = value.trim();
	if (trimmed === '') return undefined;
	const cleaned = trimmed.replace(/[$,\s]/g, '');
	if (!/^-?\d+(\.\d+)?$/.test(cleaned)) return 'invalid';
	const dollars = Number(cleaned);
	if (!Number.isFinite(dollars) || dollars < 0) return 'invalid';
	return Math.round(dollars * 100);
}

type Candidate = {
	category?: string;
	name?: string;
	description?: string;
	unit_label?: string;
	unit_price?: string;
	unit_cost?: string;
	is_taxable?: string;
	is_labor?: string;
};

function buildCandidate(
	row: Record<string, string>,
	mapping: ImportCatalogMapping
): { candidate: Candidate; dontOverwrite: Map<ImportCatalogTarget, boolean> } {
	const candidate: Candidate = {};
	const dontOverwrite = new Map<ImportCatalogTarget, boolean>();
	for (const [header, entry] of Object.entries(mapping)) {
		const value = (row[header] ?? '').trim();
		dontOverwrite.set(entry.field, entry.dont_overwrite ?? false);
		if (value) candidate[entry.field as keyof Candidate] = value;
	}
	return { candidate, dontOverwrite };
}

export function runCatalogReview(inputs: CatalogReviewInputs): {
	rows: CatalogReviewRow[];
	summary: CatalogReviewSummary;
} {
	const { rows, mapping, matchAction, existingByName } = inputs;

	// First-come-first-served over the whole file: the first row to resolve to a name wins it, and a later
	// row resolving to the same name (whether it would create that name or update the same existing item) is
	// held for a human rather than silently colliding.
	const claimedNames = new Set<string>();

	const out: CatalogReviewRow[] = [];
	const summary: CatalogReviewSummary = {
		total: 0,
		create: 0,
		update: 0,
		skip: 0,
		hold: 0,
		error: 0
	};

	rows.forEach((row, index) => {
		const source_row_number = index + 1;
		const { candidate, dontOverwrite } = buildCandidate(row, mapping);
		const flags: string[] = [];

		const errorRow = (message: string) => {
			out.push({
				source_row_number,
				planned_action: 'error',
				resolved_item: null,
				match_item_id: null,
				match_revision: null,
				flags,
				error_message: message
			});
			summary.error += 1;
		};

		const holdRow = (reason: string) => {
			out.push({
				source_row_number,
				planned_action: 'hold',
				resolved_item: null,
				match_item_id: null,
				match_revision: null,
				flags: [...flags, reason],
				error_message: null
			});
			summary.hold += 1;
		};

		const rawName = (candidate.name ?? '').trim();
		if (!rawName) return errorRow('Give this item a name.');
		const normName = normalizeCatalogName(rawName);

		const existing = existingByName.get(normName);

		if (claimedNames.has(normName)) return holdRow('duplicate_name_in_file');
		claimedNames.add(normName);

		if (existing) {
			if (matchAction === 'skip') {
				out.push({
					source_row_number,
					planned_action: 'skip',
					resolved_item: null,
					match_item_id: existing.id,
					match_revision: existing.revision,
					flags,
					error_message: null
				});
				summary.skip += 1;
				return;
			}

			const merged = mergeUpdate(candidate, existing, dontOverwrite);
			if (!merged.ok) return errorRow(merged.message);
			if (!merged.changed) {
				flags.push('already_up_to_date');
				out.push({
					source_row_number,
					planned_action: 'skip',
					resolved_item: null,
					match_item_id: existing.id,
					match_revision: existing.revision,
					flags,
					error_message: null
				});
				summary.skip += 1;
				return;
			}

			out.push({
				source_row_number,
				planned_action: 'update',
				resolved_item: merged.item,
				match_item_id: existing.id,
				match_revision: existing.revision,
				flags,
				error_message: null
			});
			summary.update += 1;
			return;
		}

		// No active item by this name -> create. A full item is required (same shape as the manual "Add
		// item" form), so build every field. Category has no default on that form either -- guessing Product
		// vs Service would be exactly the guesswork rule 2 forbids, so a missing one is an error, not a pick.
		if (!candidate.category) return errorRow('Choose Product or Service for this item.');
		const category = parseCategory(candidate.category);
		if (category === null) return errorRow(`"${candidate.category}" is not Product or Service.`);

		const taxable =
			candidate.is_taxable !== undefined ? parseBooleanish(candidate.is_taxable) : true;
		if (taxable === 'invalid') return errorRow(`"${candidate.is_taxable}" is not Yes or No.`);

		const labor = candidate.is_labor !== undefined ? parseBooleanish(candidate.is_labor) : false;
		if (labor === 'invalid') return errorRow(`"${candidate.is_labor}" is not Yes or No.`);

		const price = candidate.unit_price !== undefined ? parseMoneyToMinor(candidate.unit_price) : 0;
		if (price === 'invalid') return errorRow(`"${candidate.unit_price}" is not a valid price.`);

		const cost = candidate.unit_cost !== undefined ? parseMoneyToMinor(candidate.unit_cost) : 0;
		if (cost === 'invalid') return errorRow(`"${candidate.unit_cost}" is not a valid cost.`);

		const parsed = catalogItemCreateSchema.safeParse({
			category,
			name: rawName,
			description: candidate.description || undefined,
			unit_label: candidate.unit_label || undefined,
			unit_price_minor: price,
			unit_cost_minor: cost,
			is_taxable: taxable,
			is_labor: labor
		});
		if (!parsed.success)
			return errorRow(parsed.error.issues[0]?.message ?? 'This row could not be read.');

		out.push({
			source_row_number,
			planned_action: 'create',
			resolved_item: parsed.data,
			match_item_id: null,
			match_revision: null,
			flags,
			error_message: null
		});
		summary.create += 1;
	});

	summary.total = out.length;
	return { rows: out, summary };
}

type MergeResult =
	| { ok: true; changed: true; item: ResolvedCatalogItem }
	| { ok: true; changed: false }
	| { ok: false; message: string };

// Build the full replacement item update_catalog_item needs: every field of `existing`, with whichever mapped
// fields the row changes (honoring "don't overwrite") applied on top.
function mergeUpdate(
	candidate: Candidate,
	existing: ExistingCatalogItem,
	dontOverwrite: Map<ImportCatalogTarget, boolean>
): MergeResult {
	let changed = false;
	const next: ResolvedCatalogItem = {
		category: existing.category,
		name: existing.name,
		description: existing.description,
		unit_label: existing.unit_label,
		unit_price_minor: existing.unit_price_minor,
		unit_cost_minor: existing.unit_cost_minor,
		is_taxable: existing.is_taxable,
		is_labor: existing.is_labor
	};

	if (candidate.category !== undefined && !dontOverwrite.get('category')) {
		const category = parseCategory(candidate.category);
		if (category === null)
			return { ok: false, message: `"${candidate.category}" is not Product or Service.` };
		if (category !== next.category) {
			next.category = category;
			changed = true;
		}
	}

	// The name itself can be remapped too (e.g. a corrected spelling); "don't overwrite" protects it exactly
	// like every other field.
	const rawName = candidate.name?.trim();
	if (rawName && rawName !== existing.name && !dontOverwrite.get('name')) {
		next.name = rawName;
		changed = true;
	}

	if (candidate.description !== undefined && !dontOverwrite.get('description')) {
		const value = candidate.description || null;
		if (value !== (existing.description ?? null)) {
			next.description = value;
			changed = true;
		}
	}

	if (candidate.unit_label !== undefined && !dontOverwrite.get('unit_label')) {
		const value = candidate.unit_label || null;
		if (value !== (existing.unit_label ?? null)) {
			next.unit_label = value;
			changed = true;
		}
	}

	if (candidate.unit_price !== undefined && !dontOverwrite.get('unit_price')) {
		const price = parseMoneyToMinor(candidate.unit_price);
		if (price === 'invalid')
			return { ok: false, message: `"${candidate.unit_price}" is not a valid price.` };
		if (price !== undefined && price !== next.unit_price_minor) {
			next.unit_price_minor = price;
			changed = true;
		}
	}

	if (candidate.unit_cost !== undefined && !dontOverwrite.get('unit_cost')) {
		const cost = parseMoneyToMinor(candidate.unit_cost);
		if (cost === 'invalid')
			return { ok: false, message: `"${candidate.unit_cost}" is not a valid cost.` };
		if (cost !== undefined && cost !== next.unit_cost_minor) {
			next.unit_cost_minor = cost;
			changed = true;
		}
	}

	if (candidate.is_taxable !== undefined && !dontOverwrite.get('is_taxable')) {
		const value = parseBooleanish(candidate.is_taxable);
		if (value === 'invalid')
			return { ok: false, message: `"${candidate.is_taxable}" is not Yes or No.` };
		if (value !== undefined && value !== next.is_taxable) {
			next.is_taxable = value;
			changed = true;
		}
	}

	if (candidate.is_labor !== undefined && !dontOverwrite.get('is_labor')) {
		const value = parseBooleanish(candidate.is_labor);
		if (value === 'invalid')
			return { ok: false, message: `"${candidate.is_labor}" is not Yes or No.` };
		if (value !== undefined && value !== next.is_labor) {
			next.is_labor = value;
			changed = true;
		}
	}

	if (next.is_labor && next.category !== 'service') {
		return { ok: false, message: 'Labor is always a service.' };
	}

	if (!changed) return { ok: true, changed: false };
	return { ok: true, changed: true, item: next };
}
