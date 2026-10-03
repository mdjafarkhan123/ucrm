import { describe, expect, it } from 'vitest';
import { saveSetupStageItemsSchema } from './setup-editor.schema';

const draft = { version_id: '4af3850c-35a6-4015-82f3-2e8911ae9abf', revision: 3 };
const question = {
	type: 'question',
	fact_key: null,
	label: 'Team size',
	hint: null,
	required: false,
	can_defer: false,
	kind: 'choice',
	options: [
		{ value: null, label: 'Just me' },
		{ value: null, label: 'Just me!' },
		{ value: 'more', label: 'More than ten' }
	]
};

describe('saveSetupStageItemsSchema', () => {
	it('gives each new choice a value from its words, and keeps the value of a saved one', () => {
		const parsed = saveSetupStageItemsSchema.parse({ ...draft, items: [question] });
		expect(parsed.items[0]).toMatchObject({
			options: [
				{ value: 'just_me', label: 'Just me' },
				{ value: 'just_me_2', label: 'Just me!' },
				{ value: 'more', label: 'More than ten' }
			]
		});
	});

	it('drops choices from a question that is not pick one', () => {
		const parsed = saveSetupStageItemsSchema.parse({
			...draft,
			items: [{ ...question, kind: 'date' }]
		});
		expect(parsed.items[0]).toMatchObject({ kind: 'date', options: null });
	});

	it('needs two different choices for pick one', () => {
		const one = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [{ ...question, options: [{ value: null, label: 'A' }] }]
		});
		expect(one.error?.issues[0]).toMatchObject({ path: ['items', 0, 'options'] });
		const twins = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [
				{
					...question,
					options: [
						{ value: null, label: 'A' },
						{ value: null, label: 'a' }
					]
				}
			]
		});
		expect(twins.success).toBe(false);
	});

	it('needs an answer type for a new question but not for a built-in one', () => {
		const fresh = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [{ ...question, kind: null, options: null }]
		});
		expect(fresh.error?.issues[0]).toMatchObject({ path: ['items', 0, 'kind'] });
		const builtIn = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [{ ...question, fact_key: 'business.public_name', kind: null, options: null }]
		});
		expect(builtIn.success).toBe(true);
	});

	it('accepts headings and refuses an unknown answer type', () => {
		expect(
			saveSetupStageItemsSchema.safeParse({
				...draft,
				items: [{ type: 'heading', label: 'About you', hint: '' }]
			}).success
		).toBe(true);
		expect(
			saveSetupStageItemsSchema.safeParse({
				...draft,
				items: [{ ...question, kind: 'signature' }]
			}).success
		).toBe(false);
	});
});
