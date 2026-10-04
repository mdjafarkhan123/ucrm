import { describe, expect, it } from 'vitest';
import {
	draftItems,
	draftStages,
	itemsPayload,
	sameItems,
	publishChanges,
	sameStages,
	pickSources,
	reuseSources,
	showIfSources,
	stageAudience,
	stagesPayload,
	type SetupEditorItem,
	type SetupEditorStage
} from './setup-editor';

const item = (fields: Partial<SetupEditorItem>): SetupEditorItem => ({
	type: 'question',
	fact_key: null,
	label: '',
	hint: null,
	built_in: false,
	required: false,
	can_defer: false,
	kind: null,
	options: null,
	allow_other: false,
	max_choices: null,
	file_kinds: null,
	max_files: null,
	list_fields: null,
	max_rows: null,
	pick_from: null,
	min_choices: null,
	ordered: false,
	show_if: null,
	...fields
});

const services = [
	{ key: 'website', name: 'Premium website', archived: false },
	{ key: 'marketing', name: 'Marketing campaigns', archived: true }
];

const builtIn = item({ fact_key: 'business.public_name', label: 'Name', built_in: true });
const heading = item({ type: 'heading', label: 'Identity' });
const business: SetupEditorStage = {
	key: 'business',
	title: 'Your business',
	description: 'The basics.',
	service_key: null,
	items: [heading, builtIn]
};
const website: SetupEditorStage = {
	key: 'website',
	title: 'Website',
	description: '',
	service_key: 'website',
	items: []
};

describe('setup stage editor', () => {
	it('counts questions, not headings, and notices built-in ones', () => {
		const [row] = draftStages([business]);
		expect(row).toMatchObject({ key: 'business', questions: 1, builtIn: true });
	});

	it('sends the stages trimmed and in order, without the page-only fields', () => {
		const rows = draftStages([website, business]);
		rows[0].title = '  Website & domain ';
		expect(stagesPayload(rows)).toEqual([
			{ key: 'website', title: 'Website & domain', description: '', service_key: 'website' },
			{ key: 'business', title: 'Your business', description: 'The basics.', service_key: null }
		]);
	});

	it('treats a reorder as a change and whitespace-only edits as none', () => {
		const saved = draftStages([business, website]);
		const padded = draftStages([business, website]);
		padded[0].title = 'Your business ';
		expect(sameStages(padded, saved)).toBe(true);
		expect(sameStages(draftStages([website, business]), saved)).toBe(false);
	});

	it('names who sees a stage', () => {
		expect(stageAudience(null, services)).toBe('Every client');
		expect(stageAudience('website', services)).toBe('Only clients with Premium website');
	});

	it('describes what publishing changes for clients', () => {
		const renamed = { ...business, title: 'About you' };
		const limited = { ...website, service_key: null };
		expect(publishChanges([business], [website, renamed], services)).toEqual([
			'Adds "Website" (only clients with Premium website)',
			'Renames "Your business" to "About you"'
		]);
		expect(publishChanges([business, website], [business], services)).toEqual([
			'Removes "Website". Answers already given are kept.'
		]);
		expect(publishChanges([business, website], [limited, business], services)).toEqual([
			'"Website" now shows to every client',
			'Changes the order of the stages'
		]);
	});

	it('describes question changes inside a kept stage', () => {
		const size = item({
			fact_key: 'business.size',
			label: 'Team size',
			kind: 'choice',
			options: [
				{ value: 'one', label: 'Just me' },
				{ value: 'more', label: 'More' }
			]
		});
		const before = { ...business, items: [heading, builtIn, size] };
		const added = {
			...business,
			items: [heading, builtIn, size, item({ fact_key: 'business.x', label: 'X', kind: 'date' })]
		};
		expect(publishChanges([before], [added], services)).toEqual([
			'Adds 1 question to "Your business"'
		]);
		const removed = { ...business, items: [heading, builtIn] };
		expect(publishChanges([before], [removed], services)).toEqual([
			'Removes 1 question from "Your business". Answers already given are kept.'
		]);
		const reworded = {
			...business,
			items: [heading, { ...builtIn, label: 'Business name' }, size]
		};
		expect(publishChanges([before], [reworded], services)).toEqual([
			'Edits questions or headings in "Your business"'
		]);
		expect(publishChanges([before], [before], services)).toEqual([]);
	});
});

describe('setup question editor', () => {
	const choice = item({
		fact_key: 'business.size',
		label: 'Team size',
		hint: 'Roughly',
		kind: 'choice',
		required: true,
		options: [
			{ value: 'one', label: 'Just me' },
			{ value: 'more', label: 'More' }
		]
	});

	it('sends headings and questions in order, with a built-in question never carrying an answer type', () => {
		const rows = draftItems([heading, builtIn, choice]);
		rows[1].kind = 'text';
		rows[2].options.push({ rowId: 'new', value: null, label: ' Lots ' });
		expect(itemsPayload(rows)).toEqual([
			{ type: 'heading', label: 'Identity', hint: null },
			{
				type: 'question',
				fact_key: 'business.public_name',
				label: 'Name',
				hint: null,
				required: false,
				can_defer: false,
				kind: null,
				options: null,
				allow_other: false,
				max_choices: null,
				file_kinds: null,
				max_files: null,
				list_fields: null,
				max_rows: null,
				pick_from: null,
				min_choices: null,
				ordered: false,
				reuse_from: null,
				show_if: null
			},
			{
				type: 'question',
				fact_key: 'business.size',
				label: 'Team size',
				hint: 'Roughly',
				required: true,
				can_defer: false,
				kind: 'choice',
				options: [
					{ value: 'one', label: 'Just me' },
					{ value: 'more', label: 'More' },
					{ value: null, label: 'Lots' }
				],
				allow_other: false,
				max_choices: null,
				file_kinds: null,
				max_files: null,
				list_fields: null,
				max_rows: null,
				pick_from: null,
				min_choices: null,
				ordered: false,
				reuse_from: null,
				show_if: null
			}
		]);
	});

	it('drops the choices of a question that is no longer pick one', () => {
		const [row] = draftItems([choice]);
		row.kind = 'text';
		expect(itemsPayload([row])[0]).toMatchObject({ kind: 'text', options: null });
	});

	it('notices a change, but not a new row id or padding', () => {
		const saved = draftItems([heading, choice]);
		const padded = draftItems([heading, choice]);
		padded[1].label = 'Team size ';
		expect(sameItems(padded, saved)).toBe(true);
		padded[1].required = false;
		expect(sameItems(padded, saved)).toBe(false);
	});

	it('names a rule source above it by position until that source has a key', () => {
		const rows = draftItems([
			choice,
			item({ fact_key: 'business.vans', label: 'Vans', kind: 'text' })
		]);
		rows.splice(1, 0, { ...draftItems([choice])[0], rowId: 'new-1', fact_key: null });
		rows[2].show_if = [
			{ rowId: 'a', type: 'answer', source: 'business.size', values: ['more'] },
			{ rowId: 'b', type: 'answer', source: 'new-1', values: ['one'] },
			{ rowId: 'c', type: 'service', service_key: 'website' }
		];
		expect(itemsPayload(rows)[2]).toMatchObject({
			show_if: [
				{ fact_key: 'business.size', values: ['more'] },
				{ item: 2, values: ['one'] },
				{ service_key: 'website' }
			]
		});
		const [saved] = draftItems([item({ ...choice, show_if: [{ service_key: 'website' }] })]);
		expect(saved.show_if).toEqual([
			{ rowId: 'condition-0', type: 'service', service_key: 'website' }
		]);
	});

	it('offers as rule sources only earlier pick-one, yes/no and built-in choice questions', () => {
		const country = item({ fact_key: 'business.country', label: 'Country', built_in: true });
		const earlier: SetupEditorStage = { ...business, items: [heading, builtIn, country, choice] };
		const rows = draftItems([
			item({ fact_key: 'website.has_site', label: 'Have a site?', kind: 'yes_no' }),
			item({ fact_key: 'website.notes', label: 'Notes', kind: 'text' }),
			item({ fact_key: 'website.domain', label: 'Domain', kind: 'text' })
		]);
		rows[0].options = [];
		const sources = showIfSources([earlier], rows, 2);
		expect(sources.map((source) => [source.id, source.stageTitle])).toEqual([
			['business.country', 'Your business'],
			['business.size', 'Your business'],
			['website.has_site', null]
		]);
		expect(sources[0].options).toBe('country');
		expect(sources[2].options).toEqual([
			{ value: 'yes', label: 'Yes' },
			{ value: 'no', label: 'No' }
		]);
		const unsaved = draftItems([choice]);
		unsaved[0].options.push({ rowId: 'n', value: null, label: 'Lots' });
		expect(showIfSources([], [...unsaved, ...rows], 1)[0]).toMatchObject({
			options: [
				{ value: 'one', label: 'Just me' },
				{ value: 'more', label: 'More' }
			],
			newChoices: true
		});
	});
});

describe('more answer types (A5d)', () => {
	const choices = [
		{ value: 'cash', label: 'Cash' },
		{ value: 'card', label: 'Card' }
	];

	it('sends "Other" and "up to N" only for the choice types they belong to', () => {
		const [ticks, link] = itemsPayload(
			draftItems([
				item({
					fact_key: 'a.pay',
					kind: 'multi_choice',
					options: choices,
					allow_other: true,
					max_choices: 2
				}),
				item({ fact_key: 'a.site', kind: 'url', allow_other: true, max_choices: 2 })
			])
		);
		expect(ticks).toMatchObject({ options: choices, allow_other: true, max_choices: 2 });
		expect(link).toMatchObject({ options: null, allow_other: false, max_choices: null });
	});

	it('lets a rule depend on a tick-several or yes/no/not sure question', () => {
		const items = draftItems([
			item({ fact_key: 'a.pay', label: 'Pay', kind: 'multi_choice', options: choices }),
			item({ fact_key: 'a.data', label: 'Data', kind: 'yes_no_unsure' }),
			item({ fact_key: 'a.site', label: 'Site', kind: 'url' }),
			item({ fact_key: 'a.next', label: 'Next', kind: 'text' })
		]);
		const sources = showIfSources([], items, 3);
		expect(sources.map((source) => source.id)).toEqual(['a.pay', 'a.data']);
		expect(sources[1].options).toEqual([
			{ value: 'yes', label: 'Yes' },
			{ value: 'no', label: 'No' },
			{ value: 'not_sure', label: 'Not sure' }
		]);
	});
});

describe('pick from an earlier list (A5f)', () => {
	const list = item({
		fact_key: 'services.offered',
		label: 'Add every service you offer',
		kind: 'list',
		list_fields: [{ key: 'name', label: 'Service name', kind: 'text', required: true }],
		max_rows: 20
	});

	it('names a list above it by position until that list has a key', () => {
		const items = draftItems([item({ label: 'Services', kind: 'list', max_rows: 10 })]);
		const [pick] = draftItems([item({ label: 'Top', kind: 'pick', ordered: true })]);
		pick.pick_from = items[0].rowId;
		pick.min_choices = 2;
		expect(itemsPayload([...items, pick])[1]).toMatchObject({
			kind: 'pick',
			pick_from: { item: 1 },
			min_choices: 2,
			ordered: true
		});
		expect(
			itemsPayload(
				draftItems([
					list,
					item({ fact_key: 'services.top', kind: 'pick', pick_from: 'services.offered' })
				])
			)[1]
		).toMatchObject({
			pick_from: { fact_key: 'services.offered' }
		});
	});

	it('offers only list questions: earlier stages as saved, then those above it here', () => {
		const earlier: SetupEditorStage = {
			key: 'services',
			title: 'Services',
			description: '',
			service_key: null,
			items: [list, item({ fact_key: 'services.note', label: 'Note', kind: 'text' })]
		};
		const items = draftItems([
			item({ fact_key: 'website.areas', label: 'Areas', kind: 'list', max_rows: 10 }),
			item({ fact_key: 'website.top', label: 'Top', kind: 'pick' }),
			item({ fact_key: 'website.later', label: 'Later', kind: 'list', max_rows: 10 })
		]);
		expect(pickSources([earlier], items, 1)).toEqual([
			{ id: 'services.offered', label: 'Add every service you offer', stageTitle: 'Services' },
			{ id: 'website.areas', label: 'Areas', stageTitle: null }
		]);
	});

	it('sends no pick settings for another type', () => {
		const [question] = draftItems([item({ label: 'Name', kind: 'text' })]);
		question.pick_from = 'services.offered';
		question.min_choices = 2;
		expect(itemsPayload([question])[0]).toMatchObject({
			pick_from: null,
			min_choices: null,
			ordered: false
		});
	});
});

describe('use an earlier answer (A5g)', () => {
	it('names a question above it by position until that question has a key', () => {
		const items = draftItems([item({ label: 'Phone', kind: 'phone' })]);
		const [reuse] = draftItems([item({ label: 'Website phone', kind: 'reuse' })]);
		reuse.reuse_from = items[0].rowId;
		expect(itemsPayload([...items, reuse])[1]).toMatchObject({
			kind: 'reuse',
			reuse_from: { item: 1 }
		});
		reuse.kind = 'text';
		expect(itemsPayload([...items, reuse])[1]).toMatchObject({ reuse_from: null });
	});

	it('offers questions whose answer can be shown back and is always asked', () => {
		const earlier: SetupEditorStage = {
			key: 'business',
			title: 'Your business',
			description: '',
			service_key: null,
			items: [
				item({ fact_key: 'business.public_phone', label: 'Public phone', built_in: true }),
				item({ fact_key: 'business.logo', label: 'Logo', kind: 'file' }),
				item({
					fact_key: 'business.vat',
					label: 'VAT number',
					kind: 'text',
					show_if: [{ fact_key: 'business.country', values: ['GB'] }]
				}),
				item({
					fact_key: 'business.site',
					label: 'Website address',
					kind: 'url',
					show_if: [{ service_key: 'website' }]
				})
			]
		};
		const items = draftItems([
			item({ type: 'heading', label: 'Contact' }),
			item({ fact_key: 'website.email', label: 'Email', kind: 'email' }),
			item({ fact_key: 'website.top', label: 'Top', kind: 'pick' }),
			item({ fact_key: 'website.phone', label: 'Phone', kind: 'reuse' })
		]);
		expect(reuseSources([earlier], items, 3)).toEqual([
			{ id: 'business.public_phone', label: 'Public phone', stageTitle: 'Your business' },
			{ id: 'business.site', label: 'Website address', stageTitle: 'Your business' },
			{ id: 'website.email', label: 'Email', stageTitle: null }
		]);
	});
});
