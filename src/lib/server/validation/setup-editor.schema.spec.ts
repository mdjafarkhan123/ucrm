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

	describe('show-only-if rules (A5b)', () => {
		const ruled = (show_if: unknown) =>
			saveSetupStageItemsSchema.safeParse({
				...draft,
				items: [question, { ...question, label: 'Vans', kind: 'text', options: null, show_if }]
			});

		it('accepts an earlier answer, a question above by position, or a service', () => {
			const parsed = ruled([
				{ fact_key: 'business.type', values: ['company'] },
				{ item: 1, values: ['more'] },
				{ service_key: 'website' },
				{ fact_key: 'business.country', values: ['GB', 'IE'] }
			]);
			expect(parsed.error).toBeUndefined();
			expect(ruled([]).data?.items[1]).toMatchObject({ show_if: null });
		});

		it('explains a rule that is not finished', () => {
			expect(ruled([{ fact_key: 'business.type', values: [] }]).error?.issues[0]).toMatchObject({
				path: ['items', 1, 'show_if', 0],
				message: 'Tick at least one answer for each rule.'
			});
			expect(ruled([{ fact_key: '', values: ['x'] }]).error?.issues[0].message).toBe(
				'Choose a question for each rule.'
			);
			expect(ruled([{ service_key: '' }]).error?.issues[0].message).toBe(
				'Choose a service for each rule.'
			);
			expect(ruled([{ fact_key: 'business.type', item: 1, values: ['x'] }]).success).toBe(false);
			expect(ruled(Array(6).fill({ service_key: 'website' })).success).toBe(false);
		});

		it('checks rules on built-in questions against the choices in code', () => {
			expect(ruled([{ fact_key: 'business.public_name', values: ['x'] }]).success).toBe(false);
			expect(ruled([{ fact_key: 'business.type', values: ['plc'] }]).success).toBe(false);
			expect(ruled([{ fact_key: 'business.country', values: ['gb'] }]).success).toBe(false);
			expect(ruled([{ fact_key: 'business.trade', values: ['Plumbing'] }]).error).toBeUndefined();
		});
	});

	it('keeps "Other" and "up to N" only on the choice types they belong to (A5d)', () => {
		const parsed = saveSetupStageItemsSchema.parse({
			...draft,
			items: [
				{ ...question, kind: 'multi_choice', allow_other: true, max_choices: 4 },
				{
					...question,
					label: 'Site',
					kind: 'url',
					options: null,
					allow_other: true,
					max_choices: 2
				}
			]
		});
		expect(parsed.items[0]).toMatchObject({
			kind: 'multi_choice',
			allow_other: true,
			max_choices: 4
		});
		expect(parsed.items[0]).toHaveProperty('options.length', 3);
		expect(parsed.items[1]).toMatchObject({ allow_other: false, max_choices: null, options: null });
	});

	it('refuses more ticks than there are choices, and a typed "Other" beside "Add Other" (A5d)', () => {
		const tooMany = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [{ ...question, kind: 'multi_choice', max_choices: 4 }]
		});
		expect(tooMany.error?.issues[0]).toMatchObject({ path: ['items', 0, 'max_choices'] });
		const twoOthers = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [
				{
					...question,
					allow_other: true,
					options: [
						{ value: null, label: 'Cash' },
						{ value: null, label: 'Other' }
					]
				}
			]
		});
		expect(twoOthers.error?.issues[0]).toMatchObject({ path: ['items', 0, 'options'] });
	});
	describe('photo or file questions (A5c)', () => {
		const fileQuestion = { ...question, kind: 'file', options: null };

		it('keeps the ticked kinds in a fixed order and the chosen file limit', () => {
			const parsed = saveSetupStageItemsSchema.parse({
				...draft,
				items: [{ ...fileQuestion, file_kinds: ['audio', 'photo'], max_files: 5 }]
			});
			expect(parsed.items[0]).toMatchObject({ file_kinds: ['photo', 'audio'], max_files: 5 });
		});

		it('needs at least one kind ticked and a limit from the list', () => {
			const noKinds = saveSetupStageItemsSchema.safeParse({
				...draft,
				items: [{ ...fileQuestion, file_kinds: [], max_files: 5 }]
			});
			expect(noKinds.error?.issues[0]).toMatchObject({ path: ['items', 0, 'file_kinds'] });
			const oddLimit = saveSetupStageItemsSchema.safeParse({
				...draft,
				items: [{ ...fileQuestion, file_kinds: ['photo'], max_files: 7 }]
			});
			expect(oddLimit.error?.issues[0]).toMatchObject({ path: ['items', 0, 'max_files'] });
			const noLimit = saveSetupStageItemsSchema.safeParse({
				...draft,
				items: [{ ...fileQuestion, file_kinds: ['photo'] }]
			});
			expect(noLimit.error?.issues[0]).toMatchObject({ path: ['items', 0, 'max_files'] });
		});

		it('refuses a kind of file it does not know', () => {
			expect(
				saveSetupStageItemsSchema.safeParse({
					...draft,
					items: [{ ...fileQuestion, file_kinds: ['video'], max_files: 1 }]
				}).success
			).toBe(false);
		});

		it('drops file settings from a question that is not a photo or file question', () => {
			const parsed = saveSetupStageItemsSchema.parse({
				...draft,
				items: [{ ...question, kind: 'date', options: null, file_kinds: ['photo'], max_files: 5 }]
			});
			expect(parsed.items[0]).toMatchObject({ file_kinds: null, max_files: null });
		});
	});

	describe('add-another lists (A5e)', () => {
		const list = {
			...question,
			label: 'Your services',
			kind: 'list',
			options: null,
			max_rows: 10,
			list_fields: [
				{ key: 'name', label: 'Service name', kind: 'text', required: true },
				{ key: null, label: 'Seasonal?', kind: 'yes_no', required: false, options: [] },
				{
					key: null,
					label: 'Status',
					kind: 'choice',
					required: false,
					options: [
						{ value: null, label: 'Active' },
						{ value: null, label: 'Paused' }
					],
					file_kinds: ['photo']
				},
				{ key: null, label: '2nd photo', kind: 'file', required: false, file_kinds: ['photo'] }
			]
		};

		it('keeps saved box keys, makes new ones from names, and keeps only the settings each type uses', () => {
			const parsed = saveSetupStageItemsSchema.parse({ ...draft, items: [list] });
			expect(parsed.items[0]).toMatchObject({
				kind: 'list',
				options: null,
				max_rows: 10,
				list_fields: [
					{ key: 'name', label: 'Service name', kind: 'text', required: true },
					{ key: 'seasonal', label: 'Seasonal?', kind: 'yes_no', required: false },
					{
						key: 'status',
						kind: 'choice',
						options: [
							{ value: 'active', label: 'Active' },
							{ value: 'paused', label: 'Paused' }
						]
					},
					{ key: 'box_2nd_photo', kind: 'file', file_kinds: ['photo'] }
				]
			});
			const fields = (parsed.items[0] as { list_fields: Record<string, unknown>[] }).list_fields;
			expect(fields[1]).not.toHaveProperty('options');
			expect(fields[2]).not.toHaveProperty('file_kinds');
		});

		it('needs a box, a row limit from the list, different box names and two choices', () => {
			const problems = (changes: object) =>
				saveSetupStageItemsSchema
					.safeParse({ ...draft, items: [{ ...list, ...changes }] })
					.error?.issues.map((issue) => issue.message);
			expect(problems({ list_fields: [] })).toContain('Add at least one box.');
			expect(problems({ max_rows: 7 })).toContain('Choose how many entries a client can add.');
			expect(
				problems({
					list_fields: [
						{ key: null, label: 'Name', kind: 'text', required: true },
						{ key: null, label: 'name', kind: 'text', required: false }
					]
				})
			).toContain('Two boxes have the same name.');
			expect(
				problems({
					list_fields: [
						{
							key: null,
							label: 'Status',
							kind: 'choice',
							required: false,
							options: [{ value: null, label: 'Only' }]
						}
					]
				})
			).toContain('Give "Status" at least two choices.');
		});

		it('drops the boxes from a question that is not a list', () => {
			const parsed = saveSetupStageItemsSchema.parse({
				...draft,
				items: [{ ...list, kind: 'text' }]
			});
			expect(parsed.items[0]).toMatchObject({ kind: 'text', list_fields: null, max_rows: null });
		});
	});
});

describe('pick from an earlier list (A5f)', () => {
	const pick = {
		type: 'question',
		fact_key: null,
		label: 'Which services should we promote first?',
		hint: null,
		required: true,
		can_defer: false,
		kind: 'pick',
		options: null,
		pick_from: { fact_key: 'services.offered' },
		min_choices: 3,
		max_choices: 5,
		ordered: true
	};

	it('keeps the list, the fewest and most picks, and the order switch', () => {
		const parsed = saveSetupStageItemsSchema.parse({ ...draft, items: [pick] });
		expect(parsed.items[0]).toMatchObject({
			kind: 'pick',
			pick_from: { fact_key: 'services.offered' },
			min_choices: 3,
			max_choices: 5,
			ordered: true
		});
	});

	it('needs a list to pick from', () => {
		const result = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [{ ...pick, pick_from: null }]
		});
		expect(result.success).toBe(false);
		expect(result.error?.issues[0]).toMatchObject({
			path: ['items', 0, 'pick_from'],
			message: 'Choose the list clients pick from.'
		});
	});

	it('refuses a fewest above the most', () => {
		const result = saveSetupStageItemsSchema.safeParse({
			...draft,
			items: [{ ...pick, min_choices: 6 }]
		});
		expect(result.error?.issues[0]).toMatchObject({
			path: ['items', 0, 'min_choices'],
			message: 'The fewest can’t be more than the most.'
		});
	});

	it('drops pick settings from a question of another type', () => {
		const parsed = saveSetupStageItemsSchema.parse({
			...draft,
			items: [{ ...pick, kind: 'text' }]
		});
		expect(parsed.items[0]).toMatchObject({
			pick_from: null,
			min_choices: null,
			max_choices: null,
			ordered: false
		});
	});
});
