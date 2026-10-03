import { describe, expect, it } from 'vitest';
import {
	draftStages,
	publishChanges,
	sameStages,
	stageAudience,
	stagesPayload,
	type SetupEditorStage
} from './setup-editor';

const services = [
	{ key: 'website', name: 'Premium website', archived: false },
	{ key: 'marketing', name: 'Marketing campaigns', archived: true }
];

const builtIn = {
	type: 'question' as const,
	fact_key: 'business.public_name',
	label: 'Name',
	built_in: true
};
const business: SetupEditorStage = {
	key: 'business',
	title: 'Your business',
	description: 'The basics.',
	service_key: null,
	items: [{ type: 'heading', fact_key: null, label: 'Identity', built_in: false }, builtIn]
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
});
