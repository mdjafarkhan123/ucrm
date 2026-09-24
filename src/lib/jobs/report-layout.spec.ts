import { describe, expect, it } from 'vitest';
import type { JobReportCandidatePhoto } from './report-types';
import {
	addPhotos,
	addSection,
	canMoveItem,
	fromLayout,
	layoutFileIds,
	makePair,
	moveItem,
	moveSection,
	presort,
	removeItem,
	removeSection,
	splitPair,
	swapPair,
	toLayout,
	unnamedSections,
	updateSection,
	type ArrangedLayout
} from './report-layout';

const candidate = (id: string, labels: string[] = []): JobReportCandidatePhoto => ({
	file_id: id,
	file_name: `${id}.jpg`,
	mime_type: 'image/jpeg',
	has_thumbnail: false,
	created_at: '2026-09-24T00:00:00Z',
	caption: null,
	labels
});

const plain = (arranged: ArrangedLayout) => toLayout(arranged);

describe('presort', () => {
	it('makes a heading per label in Before, During, After, Damage order, the rest under Other', () => {
		const layout = presort([
			candidate('a', ['After']),
			candidate('b', ['before']),
			candidate('c'),
			candidate('d', ['Damage', 'Before']),
			candidate('e', ['Roof'])
		]);
		expect(plain(layout)).toEqual({
			top: [],
			sections: [
				{ heading: 'Before', note: null, items: [{ file_id: 'b' }, { file_id: 'd' }] },
				{ heading: 'After', note: null, items: [{ file_id: 'a' }] },
				{ heading: 'Other', note: null, items: [{ file_id: 'c' }, { file_id: 'e' }] }
			]
		});
	});

	it('leaves photos with none of those labels as one plain list', () => {
		expect(plain(presort([candidate('a'), candidate('b', ['Roof'])]))).toEqual({
			top: [{ file_id: 'a' }, { file_id: 'b' }],
			sections: []
		});
	});
});

describe('addPhotos', () => {
	it('pre-sorts only an empty report', () => {
		const first = addPhotos({ top: [], sections: [] }, [candidate('a', ['Before'])]);
		expect(plain(first).sections.map((section) => section.heading)).toEqual(['Before']);

		const second = addPhotos(first, [candidate('b', ['After'])]);
		expect(plain(second)).toEqual({
			top: [],
			sections: [{ heading: 'Before', note: null, items: [{ file_id: 'a' }, { file_id: 'b' }] }]
		});
	});

	it('adds to the end of the plain list when there is no heading, and never twice', () => {
		const start = fromLayout({ top: [{ file_id: 'a' }], sections: [] });
		const next = addPhotos(start, [candidate('a'), candidate('b')]);
		expect(layoutFileIds(next)).toEqual(['a', 'b']);
	});
});

describe('moving', () => {
	const start = () =>
		fromLayout({
			top: [{ file_id: 'a' }],
			sections: [
				{ heading: 'One', note: null, items: [{ file_id: 'b' }, { file_id: 'c' }] },
				{ heading: 'Two', note: null, items: [] }
			]
		});

	it('moves within a heading, then across into the neighbouring one', () => {
		let layout = start();
		const c = layout.sections[0].items[1].id;
		layout = moveItem(layout, c, -1);
		expect(layoutFileIds(layout)).toEqual(['a', 'c', 'b']);
		layout = moveItem(layout, c, -1);
		expect(plain(layout).top).toEqual([{ file_id: 'a' }, { file_id: 'c' }]);

		const b = layout.sections[0].items[0].id;
		layout = moveItem(layout, b, 1);
		expect(plain(layout).sections[1].items).toEqual([{ file_id: 'b' }]);
	});

	it('knows the first and last places cannot move further', () => {
		const layout = start();
		expect(canMoveItem(layout, layout.top[0].id, -1)).toBe(false);
		expect(canMoveItem(layout, layout.top[0].id, 1)).toBe(true);
		const last = moveItem(layout, layout.sections[0].items[1].id, 1);
		const moved = last.sections[1].items[0].id;
		expect(canMoveItem(last, moved, 1)).toBe(false);
	});

	it('moves whole headings with their photos', () => {
		const layout = start();
		const moved = moveSection(layout, layout.sections[1].id, -1);
		expect(plain(moved).sections.map((section) => section.heading)).toEqual(['Two', 'One']);
		expect(plain(moved).sections[1].items).toEqual([{ file_id: 'b' }, { file_id: 'c' }]);
	});
});

describe('headings', () => {
	it('removing one keeps its photos, at the end of the heading above', () => {
		const layout = fromLayout({
			top: [{ file_id: 'a' }],
			sections: [
				{ heading: 'One', note: null, items: [{ file_id: 'b' }] },
				{ heading: 'Two', note: null, items: [{ file_id: 'c' }] }
			]
		});
		expect(plain(removeSection(layout, layout.sections[1].id)).sections).toEqual([
			{ heading: 'One', note: null, items: [{ file_id: 'b' }, { file_id: 'c' }] }
		]);
		expect(plain(removeSection(layout, layout.sections[0].id)).top).toEqual([
			{ file_id: 'a' },
			{ file_id: 'b' }
		]);
	});

	it('a new heading needs a name, and trims what it saves', () => {
		const { layout, sectionId } = addSection({ top: [], sections: [] });
		expect(unnamedSections(layout)).toEqual([sectionId]);
		const named = updateSection(layout, sectionId, { heading: '  Kitchen ', note: '  ' });
		expect(unnamedSections(named)).toEqual([]);
		expect(plain(named).sections[0]).toEqual({ heading: 'Kitchen', note: null, items: [] });
	});
});

describe('pairs', () => {
	it("pairs two photos in the before photo's place, swaps, and splits back", () => {
		let layout = fromLayout({
			top: [{ file_id: 'a' }, { file_id: 'b' }],
			sections: [{ heading: 'One', note: null, items: [{ file_id: 'c' }] }]
		});
		layout = makePair(layout, layout.sections[0].items[0].id, layout.top[0].id);
		expect(plain(layout)).toEqual({
			top: [{ file_id: 'b' }],
			sections: [
				{ heading: 'One', note: null, items: [{ before_file_id: 'c', after_file_id: 'a' }] }
			]
		});

		const pairId = layout.sections[0].items[0].id;
		layout = swapPair(layout, pairId);
		expect(plain(layout).sections[0].items).toEqual([{ before_file_id: 'a', after_file_id: 'c' }]);

		layout = splitPair(layout, pairId);
		expect(plain(layout).sections[0].items).toEqual([{ file_id: 'a' }, { file_id: 'c' }]);
	});

	it('removing a pair takes both photos off', () => {
		let layout = fromLayout({
			top: [{ before_file_id: 'a', after_file_id: 'b' }, { file_id: 'c' }],
			sections: []
		});
		layout = removeItem(layout, layout.top[0].id);
		expect(layoutFileIds(layout)).toEqual(['c']);
	});

	it('will not pair a photo with itself or with a pair', () => {
		const layout = fromLayout({
			top: [{ file_id: 'a' }, { before_file_id: 'b', after_file_id: 'c' }],
			sections: []
		});
		expect(makePair(layout, layout.top[0].id, layout.top[0].id)).toBe(layout);
		expect(makePair(layout, layout.top[0].id, layout.top[1].id)).toBe(layout);
	});
});
