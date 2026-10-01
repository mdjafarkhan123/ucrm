import { describe, expect, it } from 'vitest';
import {
	SETUP_FACTS,
	SETUP_SECTIONS,
	missingRequiredFacts,
	sectionFacts,
	sectionStatus,
	setupValueError,
	type SetupAnswers
} from './catalogue';

const business = SETUP_SECTIONS.find((section) => section.key === 'business')!;
const have = (value: string) => ({ availability: 'have' as const, value, note: null });

function allRequiredAnswered(): SetupAnswers {
	return Object.fromEntries(
		sectionFacts(business)
			.filter((fact) => fact.required)
			.map((fact) => [fact.key, have('x')])
	);
}

describe('setup catalogue', () => {
	it('asks each fact once across every section', () => {
		const keys = SETUP_SECTIONS.flatMap((section) => sectionFacts(section).map((fact) => fact.key));
		expect(new Set(keys).size).toBe(keys.length);
		expect(SETUP_FACTS.size).toBe(keys.length);
	});

	it('uses keys the database accepts', () => {
		for (const key of SETUP_FACTS.keys())
			expect(key).toMatch(/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/);
	});

	it('never asks for a password or provider credential', () => {
		for (const fact of SETUP_FACTS.values())
			expect(`${fact.key} ${fact.label}`.toLowerCase()).not.toMatch(/password|secret|token/);
	});
});

describe('setupValueError', () => {
	const email = SETUP_FACTS.get('business.contact_email')!;
	const phone = SETUP_FACTS.get('business.public_phone')!;
	const type = SETUP_FACTS.get('business.type')!;
	const name = SETUP_FACTS.get('business.public_name')!;

	it('accepts an empty value, because clearing an answer is allowed', () => {
		expect(setupValueError(email, '  ')).toBeNull();
	});

	it('refuses a half-typed email and accepts a whole one', () => {
		expect(setupValueError(email, 'sam@')).not.toBeNull();
		expect(setupValueError(email, 'sam@brightspark.co.uk')).toBeNull();
	});

	it('accepts phone numbers as people write them and refuses words', () => {
		expect(setupValueError(phone, '+44 20 7946 0958')).toBeNull();
		expect(setupValueError(phone, '(555) 010-2299')).toBeNull();
		expect(setupValueError(phone, 'call me')).not.toBeNull();
		expect(setupValueError(phone, '12345')).not.toBeNull();
	});

	it('only accepts a listed choice', () => {
		expect(setupValueError(type, 'company')).toBeNull();
		expect(setupValueError(type, 'charity')).not.toBeNull();
	});

	it('holds text to its length', () => {
		expect(setupValueError(name, 'a'.repeat(120))).toBeNull();
		expect(setupValueError(name, 'a'.repeat(121))).not.toBeNull();
	});
});

describe('section status', () => {
	it('is not started until something is answered', () => {
		expect(sectionStatus(business, {}, false)).toBe('not_started');
	});

	it('is in progress once anything is answered', () => {
		expect(sectionStatus(business, { 'business.public_name': have('Bright Spark') }, false)).toBe(
			'in_progress'
		);
	});

	it('is done only when marked done and every required fact has an answer', () => {
		const answers = allRequiredAnswered();
		expect(sectionStatus(business, answers, false)).toBe('in_progress');
		expect(sectionStatus(business, answers, true)).toBe('done');
	});

	it('reopens by itself when a required answer is cleared after being marked done', () => {
		const answers = allRequiredAnswered();
		delete answers['business.contact_name'];
		expect(sectionStatus(business, answers, true)).toBe('in_progress');
		expect(missingRequiredFacts(business, answers).map((fact) => fact.key)).toEqual([
			'business.contact_name'
		]);
	});

	it('counts "need help" and "not yet" as answers, without a value', () => {
		const answers = allRequiredAnswered();
		answers['business.public_phone'] = { availability: 'need_help', value: null, note: null };
		answers['business.public_email'] = { availability: 'not_yet', value: null, note: 'Soon' };
		expect(missingRequiredFacts(business, answers)).toEqual([]);
		expect(sectionStatus(business, answers, true)).toBe('done');
	});
});
