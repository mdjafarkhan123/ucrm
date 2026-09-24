import type { JobReportCandidatePhoto, JobReportLayout, JobReportLayoutItem } from './report-types';

// The work-report editor's working copy of a photo arrangement (Part 7C), and every change the editor can
// make to it. Each change returns a new arrangement, so the editor only ever assigns. Items and sections carry
// an `id` because the drag-and-drop zones key on one; the database never sees them.

export type ArrangedItem =
	| { id: string; kind: 'photo'; fileId: string }
	| { id: string; kind: 'pair'; beforeId: string; afterId: string };

export type ArrangedSection = { id: string; heading: string; note: string; items: ArrangedItem[] };

export type ArrangedLayout = { top: ArrangedItem[]; sections: ArrangedSection[] };

// Label names that pre-sort a brand-new report, in the order their headings appear (approved 2026-09-24).
export const PRESORT_LABELS = ['Before', 'During', 'After', 'Damage'] as const;
export const PRESORT_OTHER_HEADING = 'Other';

let nextId = 0;
const newId = (prefix: string) => `${prefix}-${++nextId}`;

const photo = (fileId: string): ArrangedItem => ({ id: newId('photo'), kind: 'photo', fileId });

export function fromLayout(layout: JobReportLayout): ArrangedLayout {
	const item = (entry: JobReportLayoutItem): ArrangedItem =>
		'file_id' in entry
			? photo(entry.file_id)
			: {
					id: newId('pair'),
					kind: 'pair',
					beforeId: entry.before_file_id,
					afterId: entry.after_file_id
				};
	return {
		top: layout.top.map(item),
		sections: layout.sections.map((section) => ({
			id: newId('section'),
			heading: section.heading,
			note: section.note ?? '',
			items: section.items.map(item)
		}))
	};
}

export function toLayout(arranged: ArrangedLayout): JobReportLayout {
	const item = (entry: ArrangedItem): JobReportLayoutItem =>
		entry.kind === 'photo'
			? { file_id: entry.fileId }
			: { before_file_id: entry.beforeId, after_file_id: entry.afterId };
	return {
		top: arranged.top.map(item),
		sections: arranged.sections.map((section) => ({
			heading: section.heading.trim(),
			note: section.note.trim() || null,
			items: section.items.map(item)
		}))
	};
}

const itemFileIds = (item: ArrangedItem) =>
	item.kind === 'photo' ? [item.fileId] : [item.beforeId, item.afterId];

/** Every photo on the report, in order. */
export function layoutFileIds(arranged: ArrangedLayout): string[] {
	return [arranged.top, ...arranged.sections.map((section) => section.items)]
		.flat()
		.flatMap(itemFileIds);
}

export function isEmpty(arranged: ArrangedLayout) {
	return arranged.top.length === 0 && arranged.sections.length === 0;
}

// A brand-new report starts sorted by label: a heading for each of Before / During / After / Damage that some
// photo carries, the rest under "Other". A photo with two of those labels goes under the first in that order.
// When no photo carries any of them there is nothing to sort by, so they stay one plain list.
export function presort(photos: JobReportCandidatePhoto[]): ArrangedLayout {
	const groups = new Map<string, string[]>();
	const other: string[] = [];
	for (const candidate of photos) {
		const names = new Set(candidate.labels.map((label) => label.trim().toLowerCase()));
		const match = PRESORT_LABELS.find((label) => names.has(label.toLowerCase()));
		if (match) groups.set(match, [...(groups.get(match) ?? []), candidate.file_id]);
		else other.push(candidate.file_id);
	}
	if (groups.size === 0) return { top: other.map(photo), sections: [] };

	const sections: ArrangedSection[] = PRESORT_LABELS.filter((label) => groups.has(label)).map(
		(label) => ({
			id: newId('section'),
			heading: label,
			note: '',
			items: (groups.get(label) ?? []).map(photo)
		})
	);
	if (other.length) {
		sections.push({
			id: newId('section'),
			heading: PRESORT_OTHER_HEADING,
			note: '',
			items: other.map(photo)
		});
	}
	return { top: [], sections };
}

/** Adds photos: pre-sorted into an empty report, otherwise at the very end. */
export function addPhotos(
	arranged: ArrangedLayout,
	photos: JobReportCandidatePhoto[]
): ArrangedLayout {
	const present = new Set(layoutFileIds(arranged));
	const fresh = photos.filter((candidate) => !present.has(candidate.file_id));
	if (fresh.length === 0) return arranged;
	if (isEmpty(arranged)) return presort(fresh);

	const added = fresh.map((candidate) => photo(candidate.file_id));
	if (arranged.sections.length === 0) return { ...arranged, top: [...arranged.top, ...added] };
	const last = arranged.sections.length - 1;
	return {
		...arranged,
		sections: arranged.sections.map((section, index) =>
			index === last ? { ...section, items: [...section.items, ...added] } : section
		)
	};
}

// Every group of items in reading order: above the first heading, then each heading.
type Group = { sectionId: string | null; items: ArrangedItem[] };

function groups(arranged: ArrangedLayout): Group[] {
	return [
		{ sectionId: null, items: arranged.top },
		...arranged.sections.map((section) => ({ sectionId: section.id, items: section.items }))
	];
}

function withGroups(arranged: ArrangedLayout, next: Group[]): ArrangedLayout {
	return {
		top: next[0].items,
		sections: arranged.sections.map((section, index) => ({
			...section,
			items: next[index + 1].items
		}))
	};
}

function locate(arranged: ArrangedLayout, itemId: string) {
	const all = groups(arranged);
	for (let group = 0; group < all.length; group++) {
		const index = all[group].items.findIndex((item) => item.id === itemId);
		if (index !== -1) return { all, group, index };
	}
	return null;
}

/**
 * Moves an item one place up or down. At the edge of its heading it crosses into the neighbouring one --
 * the end of the one above, or the start of the one below -- so the buttons alone can reach anywhere.
 */
export function moveItem(arranged: ArrangedLayout, itemId: string, direction: -1 | 1) {
	const found = locate(arranged, itemId);
	if (!found) return arranged;
	const { all, group, index } = found;
	const next = all.map((entry) => ({ ...entry, items: [...entry.items] }));
	const target = index + direction;
	if (target >= 0 && target < all[group].items.length) {
		const [item] = next[group].items.splice(index, 1);
		next[group].items.splice(target, 0, item);
		return withGroups(arranged, next);
	}
	const neighbour = group + direction;
	if (neighbour < 0 || neighbour >= next.length) return arranged;
	const [item] = next[group].items.splice(index, 1);
	if (direction === -1) next[neighbour].items.push(item);
	else next[neighbour].items.unshift(item);
	return withGroups(arranged, next);
}

/** Whether an item can move any further in that direction. */
export function canMoveItem(arranged: ArrangedLayout, itemId: string, direction: -1 | 1) {
	const found = locate(arranged, itemId);
	if (!found) return false;
	const { all, group, index } = found;
	if (direction === -1) return index > 0 || group > 0;
	return index < all[group].items.length - 1 || group < all.length - 1;
}

export function moveSection(arranged: ArrangedLayout, sectionId: string, direction: -1 | 1) {
	const index = arranged.sections.findIndex((section) => section.id === sectionId);
	const target = index + direction;
	if (index === -1 || target < 0 || target >= arranged.sections.length) return arranged;
	const sections = [...arranged.sections];
	[sections[index], sections[target]] = [sections[target], sections[index]];
	return { ...arranged, sections };
}

export function addSection(arranged: ArrangedLayout): {
	layout: ArrangedLayout;
	sectionId: string;
} {
	const section: ArrangedSection = { id: newId('section'), heading: '', note: '', items: [] };
	return {
		layout: { ...arranged, sections: [...arranged.sections, section] },
		sectionId: section.id
	};
}

export function updateSection(
	arranged: ArrangedLayout,
	sectionId: string,
	change: Partial<Pick<ArrangedSection, 'heading' | 'note'>>
): ArrangedLayout {
	return {
		...arranged,
		sections: arranged.sections.map((section) =>
			section.id === sectionId ? { ...section, ...change } : section
		)
	};
}

/** Removes a heading. Its photos stay on the report, moving to the end of the heading above. */
export function removeSection(arranged: ArrangedLayout, sectionId: string): ArrangedLayout {
	const index = arranged.sections.findIndex((section) => section.id === sectionId);
	if (index === -1) return arranged;
	const orphans = arranged.sections[index].items;
	const sections = arranged.sections.filter((section) => section.id !== sectionId);
	if (index === 0) return { top: [...arranged.top, ...orphans], sections };
	return {
		top: arranged.top,
		sections: sections.map((section, position) =>
			position === index - 1 ? { ...section, items: [...section.items, ...orphans] } : section
		)
	};
}

function mapItems(
	arranged: ArrangedLayout,
	change: (items: ArrangedItem[]) => ArrangedItem[]
): ArrangedLayout {
	return {
		top: change(arranged.top),
		sections: arranged.sections.map((section) => ({ ...section, items: change(section.items) }))
	};
}

/** Takes an item off the report. Removing a pair takes both of its photos off. */
export function removeItem(arranged: ArrangedLayout, itemId: string) {
	return mapItems(arranged, (items) => items.filter((item) => item.id !== itemId));
}

/**
 * Makes a before/after pair of two single photos. The pair takes the before photo's place; the after photo
 * leaves its own, so each photo still appears once.
 */
export function makePair(arranged: ArrangedLayout, beforeItemId: string, afterItemId: string) {
	const before = locate(arranged, beforeItemId);
	const after = locate(arranged, afterItemId);
	if (!before || !after || beforeItemId === afterItemId) return arranged;
	const beforeItem = before.all[before.group].items[before.index];
	const afterItem = after.all[after.group].items[after.index];
	if (beforeItem.kind !== 'photo' || afterItem.kind !== 'photo') return arranged;
	const pair: ArrangedItem = {
		id: newId('pair'),
		kind: 'pair',
		beforeId: beforeItem.fileId,
		afterId: afterItem.fileId
	};
	return mapItems(arranged, (items) =>
		items
			.filter((item) => item.id !== afterItemId)
			.map((item) => (item.id === beforeItemId ? pair : item))
	);
}

export function swapPair(arranged: ArrangedLayout, itemId: string) {
	return mapItems(arranged, (items) =>
		items.map((item) =>
			item.id === itemId && item.kind === 'pair'
				? { ...item, beforeId: item.afterId, afterId: item.beforeId }
				: item
		)
	);
}

/** Splits a pair back into two single photos in its place, before first. */
export function splitPair(arranged: ArrangedLayout, itemId: string) {
	return mapItems(arranged, (items) =>
		items.flatMap((item) =>
			item.id === itemId && item.kind === 'pair'
				? [photo(item.beforeId), photo(item.afterId)]
				: [item]
		)
	);
}

/** Headings left without a name, which the database would refuse. */
export function unnamedSections(arranged: ArrangedLayout) {
	return arranged.sections
		.filter((section) => !section.heading.trim())
		.map((section) => section.id);
}
