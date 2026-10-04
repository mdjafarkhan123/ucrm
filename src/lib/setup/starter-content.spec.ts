import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { SETUP_VERSION_1 } from './catalogue.fixture';
import {
	BUILT_IN_FACTS,
	buildSetupCatalogue,
	catalogueFacts,
	sectionFacts,
	shownFacts,
	type SetupAnswers,
	type SetupCatalogueRow
} from './catalogue';
import { followUpSuggestions } from './follow-ups';

// B3b–B12 load the approved starter content (docs/client-onboarding-setup-content-blueprint.md) into the setup
// draft through private.setup_load_starter_stage. The database cannot check a "show only if" rule against a
// built-in question's choices, which live in code, so these tests read each stage straight from its migration.

type Item = SetupCatalogueRow['stages'][number]['items'][number];

const MIGRATIONS = 'supabase/migrations';
const STAGE_CALL =
	/select private\.setup_load_starter_stage\(\s*'([a-z_]+)',\s*'([^']+)',\s*'([^']+)',\s*(null|'[a-z_]+'),\s*\$items\$([\s\S]*?)\$items\$::jsonb/g;

function starterStages(): SetupCatalogueRow['stages'] {
	const stages = new Map<string, SetupCatalogueRow['stages'][number]>();
	for (const file of readdirSync(MIGRATIONS).sort()) {
		if (!file.includes('_setup_starter_')) continue;
		for (const [, key, title, description, service, json] of readFileSync(
			`${MIGRATIONS}/${file}`,
			'utf8'
		).matchAll(STAGE_CALL)) {
			const items = (JSON.parse(json) as Partial<Item>[]).map((item): Item => ({
				fact_key: null,
				hint: null,
				built_in: false,
				required: false,
				can_defer: false,
				kind: null,
				options: null,
				max_length: null,
				...item,
				type: item.type ?? 'question',
				label: item.label ?? ''
			}));
			stages.set(key, {
				key,
				title,
				description,
				service_key: service === 'null' ? null : service.slice(1, -1),
				items
			});
		}
	}
	return [...stages.values()];
}

const stages = starterStages();
const starter = buildSetupCatalogue({ version_id: 'starter', stages });
const facts = catalogueFacts(starter);
const have = (value: string) => ({ availability: 'have' as const, value, note: null });

describe('starter setup content', () => {
	it('loads the Your business stage', () => {
		expect(stages.map((stage) => stage.key)).toContain('business');
	});

	it('leaves no question out for want of answer rules', () => {
		const questions = stages.flatMap((stage) =>
			stage.items.filter((item) => item.type === 'question')
		);
		expect(facts.size).toBe(questions.length);
		for (const item of questions)
			if (item.built_in) expect(BUILT_IN_FACTS[item.fact_key!], item.fact_key!).toBeDefined();
	});

	it('only shows a question for answers its earlier question can give', () => {
		for (const fact of facts.values())
			for (const condition of fact.showIf ?? []) {
				if (!('values' in condition)) continue;
				const source = facts.get(condition.factKey);
				expect(source, `${fact.key} depends on ${condition.factKey}`).toBeDefined();
				const choices = source!.options?.map((option) => option.value) ?? [];
				for (const value of condition.values) expect(choices, fact.key).toContain(value);
			}
	});

	it('still asks every question clients answered in version 1, so their answers show again', () => {
		const before = catalogueFacts(buildSetupCatalogue(SETUP_VERSION_1));
		for (const [key, fact] of before) {
			expect(facts.has(key), key).toBe(true);
			expect(facts.get(key)!.kind, key).toBe(fact.kind);
		}
	});

	describe('Your business', () => {
		const business = starter.sections.find((section) => section.key === 'business')!;
		const shown = (answers: SetupAnswers) => shownFacts(sectionFacts(business), answers);

		it('asks the legal name only when it differs', () => {
			expect(shown({}).has('business.legal_name')).toBe(false);
			expect(shown({ 'business.legal_name_differs': have('no') }).has('business.legal_name')).toBe(
				false
			);
			expect(shown({ 'business.legal_name_differs': have('yes') }).has('business.legal_name')).toBe(
				true
			);
		});

		it('asks for the final approver only when the main contact is not the one', () => {
			const approver = [
				'business.approver_name',
				'business.approver_email',
				'business.approver_phone'
			];
			const whenYes = shown({ 'business.contact_is_approver': have('yes') });
			const whenNo = shown({ 'business.contact_is_approver': have('no') });
			for (const key of approver) {
				expect(whenYes.has(key)).toBe(false);
				expect(whenNo.has(key)).toBe(true);
			}
		});

		it('asks whether the address may be public only when customers visit it', () => {
			expect(
				shown({ 'business.address_customers_visit': have('no') }).has('business.address_public')
			).toBe(false);
			expect(
				shown({ 'business.address_customers_visit': have('yes') }).has('business.address_public')
			).toBe(true);
		});

		it('asks for weekly hours only for set opening hours, and after hours unless always open', () => {
			const always = shown({ 'business.availability': have('always') });
			expect(always.has('business.hours')).toBe(false);
			expect(always.has('business.after_hours')).toBe(false);
			const set = shown({ 'business.availability': have('set_hours') });
			expect(set.has('business.hours')).toBe(true);
			expect(set.has('business.after_hours')).toBe(true);
		});

		it('shows an earlier client their old legal name, approver and hours again from the suggestions', () => {
			const old: SetupAnswers = {
				'business.public_name': have('Raad LTD'),
				'business.legal_name': have('Raad Trading Limited'),
				'business.approver_name': have('Sam Lee'),
				'business.hours': have('{"days":[]}')
			};
			const suggested = Object.fromEntries(
				Object.entries(followUpSuggestions(old, null)).flatMap(([key, value]) =>
					value ? [[key, have(value)]] : []
				)
			);
			const asked = shown({ ...old, ...suggested });
			for (const key of ['business.legal_name', 'business.approver_name', 'business.hours'])
				expect(asked.has(key), key).toBe(true);
		});
	});
});
