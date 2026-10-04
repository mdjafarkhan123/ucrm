import { describe, expect, it } from 'vitest';
import {
	parseSetupFileIds,
	setupFileAccept,
	setupFileIds,
	setupFileKindsPhrase,
	setupFileType
} from './files';

const A = '4af3850c-35a6-4015-82f3-2e8911ae9abf';
const B = '9c1d2e3f-4a5b-4c6d-8e7f-0a1b2c3d4e5f';

describe('parseSetupFileIds', () => {
	it('keeps the files in the order the client added them', () => {
		expect(parseSetupFileIds(JSON.stringify([A, B]), 5)).toEqual({ value: [A, B], error: null });
	});

	it('treats the same file in capitals as the same file', () => {
		expect(parseSetupFileIds(JSON.stringify([A.toUpperCase()]), 1)).toEqual({
			value: [A],
			error: null
		});
	});

	it('asks for a file when the answer holds none, or holds something that is not a file', () => {
		for (const raw of [
			'',
			'not json',
			'[]',
			'{}',
			JSON.stringify([42]),
			JSON.stringify(['logo.png'])
		])
			expect(parseSetupFileIds(raw, 5)).toEqual({ value: null, error: 'Add a file.' });
	});

	it('refuses the same file added twice', () => {
		expect(parseSetupFileIds(JSON.stringify([A, A.toUpperCase()]), 5)).toEqual({
			value: null,
			error: 'A file is added twice.'
		});
	});

	it('refuses more files than the question takes, in words that fit the limit', () => {
		expect(parseSetupFileIds(JSON.stringify([A, B]), 1).error).toBe('Add one file only.');
		const six = Array.from({ length: 6 }, (_, i) => `${A.slice(0, -1)}${i}`);
		expect(parseSetupFileIds(JSON.stringify(six), 5).error).toBe('Add up to 5 files.');
	});
});

describe('setupFileIds', () => {
	it('reads the files of a stored answer and skips anything else', () => {
		expect(setupFileIds(JSON.stringify([A, 'junk', 7, B]))).toEqual([A, B]);
	});

	it('gives an empty list for an answer that is not a file list', () => {
		for (const raw of [null, undefined, '', 'Plumbing', '[broken'])
			expect(setupFileIds(raw)).toEqual([]);
	});
});

describe('setupFileType', () => {
	it('takes only the kinds the question ticks', () => {
		expect(setupFileType('van.jpg', ['photo'])?.signature).toBe('jpeg');
		expect(setupFileType('licence.pdf', ['photo'])).toBeNull();
		expect(setupFileType('licence.pdf', ['photo', 'document'])?.signature).toBe('pdf');
	});

	it('takes voice recordings only on a question that asks for them', () => {
		expect(setupFileType('greeting.m4a', ['photo', 'document'])).toBeNull();
		expect(setupFileType('greeting.m4a', ['audio'])?.signature).toBe('m4a');
		expect(setupFileType('greeting.MP3', ['audio'])?.signature).toBe('mp3');
		expect(setupFileType('van.jpg', ['audio'])).toBeNull();
	});

	it('refuses SVG even on a photo question, because some pages show images straight on the page', () => {
		expect(setupFileType('logo.svg', ['photo', 'document'])).toBeNull();
	});
});

describe('question wording', () => {
	it('names the ticked kinds in a sentence', () => {
		expect(setupFileKindsPhrase(['photo'])).toBe('photos');
		expect(setupFileKindsPhrase(['audio', 'photo'])).toBe('photos or voice recordings');
		expect(setupFileKindsPhrase(['photo', 'document', 'audio'])).toBe(
			'photos, documents or voice recordings'
		);
		expect(setupFileKindsPhrase([])).toBe('files');
	});

	it('lets the file picker show only what the question takes', () => {
		const accept = setupFileAccept(['photo']);
		expect(accept).toContain('.jpg');
		expect(accept).toContain('image/png');
		expect(accept).not.toContain('.pdf');
		expect(accept).not.toContain('audio/');
	});
});
