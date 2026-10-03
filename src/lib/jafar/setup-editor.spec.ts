import { describe, expect, it } from 'vitest';
import {
	draftItems,
	draftStages,
	itemsPayload,
	sameItems,
	publishChanges,
	sameStages,
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
				options: null
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
				]
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
});
