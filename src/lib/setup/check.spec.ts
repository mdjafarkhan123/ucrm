import { describe, expect, it } from 'vitest';
import { buildSetupCheck, setupConfirmations, setupSnapshotFactKeys } from '$lib/setup/check';
import type { SetupAnswers, SetupCatalogue, SetupFact } from '$lib/setup/catalogue';
import { setupReuseValue } from '$lib/setup/reuse';

const fact = (key: string, label: string, rules: Partial<SetupFact> = {}): SetupFact => ({
	key,
	label,
	kind: 'text',
	required: false,
	builtIn: false,
	...rules
});

const catalogue: SetupCatalogue = {
	versionId: 'version-1',
	sections: [
		{
			key: 'business',
			title: 'Your business',
			description: '',
			serviceKey: null,
			groups: [
				{
					title: '',
					hint: '',
					facts: [
						fact('business.name', 'Business name', { required: true }),
						fact('business.phone', 'Public phone', { required: true, canDefer: true }),
						fact('business.has_logo', 'Do you have a logo?', {
							kind: 'choice',
							options: [
								{ value: 'yes', label: 'Yes' },
								{ value: 'no', label: 'No' }
							]
						}),
						fact('business.logo', 'Logo', {
							kind: 'file',
							fileKinds: ['photo'],
							showIf: [{ factKey: 'business.has_logo', values: ['yes'] }]
						})
					]
				}
			]
		},
		{
			key: 'website',
			title: 'Website',
			description: '',
			serviceKey: 'website',
			groups: [
				{
					title: '',
					hint: '',
					facts: [
						fact('website.phone', 'Phone on the website', {
							kind: 'text',
							reuseFrom: 'business.phone',
							reuseLabel: 'Public phone'
						}),
						fact('website.notes', 'Anything else?', { kind: 'longtext' })
					]
				}
			]
		}
	]
};

const have = (value: string) => ({ availability: 'have' as const, value, note: null });
const LOGO_ID = '6f1c2f0e-8a4b-4c1d-9e2f-0a1b2c3d4e5f';

const answers: SetupAnswers = {
	'business.name': have('Raad Plumbing'),
	'business.phone': have('+44 20 7946 0000'),
	'business.has_logo': have('yes'),
	'business.logo': have(JSON.stringify([LOGO_ID])),
	'website.phone': have(setupReuseValue('business.phone'))
};
const allDone = new Set(['business', 'website']);

describe('setupConfirmations', () => {
	it('asks about only the services the package includes', () => {
		const keys = (services: string[]) => setupConfirmations(new Set(services)).map((c) => c.key);
		expect(keys([])).toEqual([
			'accurate',
			'use_materials',
			'permission',
			'build_and_launch',
			'imports'
		]);
		expect(keys(['website', 'google_profile', 'calls_texting', 'reviews', 'marketing'])).toEqual([
			'accurate',
			'use_materials',
			'permission',
			'build_and_launch',
			'ownership',
			'phone_registration',
			'imports',
			'marketing_drafts'
		]);
	});

	it('names only what the client owns among the services bought', () => {
		const ownership = (services: string[]) =>
			setupConfirmations(new Set(services)).find((c) => c.key === 'ownership')?.wording;
		expect(ownership(['google_profile'])).toContain('our Google Business Profile.');
		expect(ownership(['website'])).toContain('our domain.');
		expect(ownership(['website', 'google_profile'])).toContain(
			'our domain and Google Business Profile.'
		);
	});

	it('mentions DNS only with a website', () => {
		const launch = (services: string[]) =>
			setupConfirmations(new Set(services)).find((c) => c.key === 'build_and_launch')?.wording;
		expect(launch(['website'])).toContain('DNS');
		expect(launch(['reviews'])).not.toContain('DNS');
	});
});

describe('buildSetupCheck', () => {
	it('can send once every task is done, and reads each answer back in words', () => {
		const check = buildSetupCheck(catalogue, answers, allDone, null);
		expect(check.can_send).toBe(true);
		const business = check.sections[0];
		expect(business.items.find((item) => item.key === 'business.logo')?.lines).toEqual([
			'1 photo added'
		]);
		expect(business.items.find((item) => item.key === 'business.has_logo')?.lines).toEqual(['Yes']);
		const reuse = check.sections[1].items.find((item) => item.key === 'website.phone');
		expect(reuse).toMatchObject({ same_as: 'Public phone', lines: ['+44 20 7946 0000'] });
		expect(check.sections[1].status).toBe('optional_skipped');
	});

	it('stops the send while a task is not marked done, and says why', () => {
		const check = buildSetupCheck(catalogue, answers, new Set(['business']), null);
		expect(check.can_send).toBe(false);
		expect(check.sections[1]).toMatchObject({
			status: 'unfinished',
			problem: 'Not marked as done yet.'
		});
	});

	it('counts a missing required answer even on a task marked done', () => {
		const { 'business.name': _, ...rest } = answers;
		const check = buildSetupCheck(catalogue, rest, allDone, null);
		expect(check.sections[0]).toMatchObject({
			status: 'unfinished',
			problem: '1 required question still needs an answer.'
		});
	});

	it('keeps "need help" and "not yet" as follow-ups that do not stop the send', () => {
		const help = buildSetupCheck(
			catalogue,
			{
				...answers,
				'business.phone': { availability: 'need_help', value: null, note: 'No number yet' }
			},
			allDone,
			null
		);
		expect(help.sections[0].status).toBe('needs_help');
		expect(help.sections[0].items[1]).toMatchObject({ state: 'need_help', note: 'No number yet' });
		expect(help.can_send).toBe(true);

		const waiting = buildSetupCheck(
			catalogue,
			{ ...answers, 'business.phone': { availability: 'not_yet', value: null, note: null } },
			allDone,
			null
		);
		expect(waiting.sections[0].status).toBe('waiting');
	});

	it('leaves a question an earlier answer hides out of the check and the snapshot', () => {
		const noLogo = { ...answers, 'business.has_logo': have('no') };
		const check = buildSetupCheck(catalogue, noLogo, allDone, null);
		expect(check.sections[0].items.map((item) => item.key)).not.toContain('business.logo');
		// Still stored in the draft, but not sent.
		expect(setupSnapshotFactKeys(catalogue, noLogo)).not.toContain('business.logo');
		expect(setupSnapshotFactKeys(catalogue, answers)).toContain('business.logo');
	});

	describe('after a send', () => {
		it('has nothing to send until an answer changes', () => {
			const check = buildSetupCheck(catalogue, answers, allDone, answers);
			expect(check.changed_count).toBe(0);
			expect(check.can_send).toBe(false);
		});

		it('marks a changed answer and allows sending the change', () => {
			const changed = { ...answers, 'business.name': have('Raad Plumbing Ltd') };
			const check = buildSetupCheck(catalogue, changed, allDone, answers);
			expect(check.changed_count).toBe(1);
			expect(check.can_send).toBe(true);
			expect(check.sections[0].items[0]).toMatchObject({ key: 'business.name', changed: true });
			expect(check.sections[0].items[1].changed).toBe(false);
		});

		it('names an answer that a change has since hidden', () => {
			const changed = { ...answers, 'business.has_logo': have('no') };
			const check = buildSetupCheck(catalogue, changed, allDone, answers);
			expect(check.sections[0].no_longer_asked).toEqual([{ key: 'business.logo', label: 'Logo' }]);
			expect(check.changed_count).toBe(2);
		});

		it('counts a newly given answer as a change', () => {
			const changed = { ...answers, 'website.notes': have('Gas Safe registered') };
			expect(buildSetupCheck(catalogue, changed, allDone, answers).changed_count).toBe(1);
		});
	});
});
