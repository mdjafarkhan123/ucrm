import { describe, expect, it } from 'vitest';
import {
	OPT_OUT_LANGUAGES,
	countryOptOutLanguages,
	englishOnlyLanguage,
	languageName,
	optOutKeywordKind
} from './sms-opt-out-words';

describe('countryOptOutLanguages', () => {
	it('gives the main language of a country that does not text in English', () => {
		expect(countryOptOutLanguages('MX')).toEqual(['es']);
		expect(countryOptOutLanguages('BD')).toEqual(['bn']);
		expect(countryOptOutLanguages('BR')).toEqual(['pt']);
		expect(countryOptOutLanguages('NO')).toEqual(['nb']);
	});

	it('needs nothing for English-speaking countries', () => {
		expect(countryOptOutLanguages('US')).toEqual([]);
		expect(countryOptOutLanguages('GB')).toEqual([]);
		expect(countryOptOutLanguages('AU')).toEqual([]);
	});

	it('adds the second official language of bilingual countries', () => {
		expect(countryOptOutLanguages('CA')).toEqual(['fr']);
		expect(countryOptOutLanguages('BE')).toEqual(['nl', 'fr']);
		expect(countryOptOutLanguages('CH')).toEqual(['de', 'fr', 'it']);
	});

	it('leaves languages Twilio cannot take to English', () => {
		expect(countryOptOutLanguages('TR')).toEqual([]);
		expect(englishOnlyLanguage('TR')).toBe('tr');
		expect(englishOnlyLanguage('MX')).toBeNull();
		expect(englishOnlyLanguage('GB')).toBeNull();
		expect(languageName('tr')).toBe('Turkish');
	});
});

describe('optOutKeywordKind', () => {
	it('reads a whole reply as a stop or start word in any listed language', () => {
		expect(optOutKeywordKind('ALTO')).toBe('opt_out');
		expect(optOutKeywordKind('  alto ')).toBe('opt_out');
		expect(optOutKeywordKind('Arrêt')).toBe('opt_out');
		expect(optOutKeywordKind('বন্ধ')).toBe('opt_out');
		expect(optOutKeywordKind('стоп')).toBe('opt_out');
		expect(optOutKeywordKind('Inicio')).toBe('opt_in');
	});

	it('ignores ordinary replies, even ones holding a stop word', () => {
		expect(optOutKeywordKind('alto, nos vemos el martes')).toBeNull();
		expect(optOutKeywordKind('gracias')).toBeNull();
	});

	it('never lists one word as both stop and start', () => {
		const kinds = new Map<string, Set<string>>();
		for (const language of Object.values(OPT_OUT_LANGUAGES)) {
			for (const [kind, words] of [
				['stop', language.stop],
				['start', language.start]
			] as const) {
				for (const word of words) {
					const key = word.toLocaleLowerCase();
					kinds.set(key, (kinds.get(key) ?? new Set()).add(kind));
				}
			}
		}
		const both = [...kinds].filter(([, set]) => set.size > 1).map(([word]) => word);
		expect(both).toEqual([]);
	});

	it('never overrides an English word Twilio already handles', () => {
		for (const word of ['stop', 'start', 'help', 'yes', 'cancel', 'end', 'quit', 'info']) {
			expect(optOutKeywordKind(word)).toBeNull();
		}
	});
});
