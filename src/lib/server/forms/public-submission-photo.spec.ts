import { describe, expect, it } from 'vitest';
import { PUBLIC_FORM_PHOTO_MAX_BYTES, decodePublicFormPhoto } from './public-submission-photo';

function dataUrl(mimeInUrl: string, bytes: number[]) {
	return `data:${mimeInUrl};base64,${Buffer.from(bytes).toString('base64')}`;
}

const PNG_BYTES = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0];
const JPEG_BYTES = [0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0];
const WEBP_BYTES = [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0, 0, 0, 0];

describe('decodePublicFormPhoto', () => {
	it('accepts a real PNG', () => {
		const result = decodePublicFormPhoto(dataUrl('image/png', PNG_BYTES));
		expect(result?.mimeType).toBe('image/png');
	});

	it('accepts a real JPEG', () => {
		const result = decodePublicFormPhoto(dataUrl('image/jpeg', JPEG_BYTES));
		expect(result?.mimeType).toBe('image/jpeg');
	});

	it('accepts a real WebP', () => {
		const result = decodePublicFormPhoto(dataUrl('image/webp', WEBP_BYTES));
		expect(result?.mimeType).toBe('image/webp');
	});

	it('trusts the file’s real bytes over the data URL’s claimed mime type', () => {
		const result = decodePublicFormPhoto(dataUrl('image/png', JPEG_BYTES));
		expect(result?.mimeType).toBe('image/jpeg');
	});

	it('rejects bytes that are not a real PNG, JPEG, or WebP', () => {
		expect(decodePublicFormPhoto(dataUrl('image/png', [0, 1, 2, 3, 4, 5, 6, 7]))).toBeNull();
	});

	it('rejects something that is not a data URL at all', () => {
		expect(decodePublicFormPhoto('not-a-data-url')).toBeNull();
	});

	it('rejects a data URL for a disallowed mime type', () => {
		expect(decodePublicFormPhoto(dataUrl('image/gif', PNG_BYTES))).toBeNull();
	});

	it('rejects an empty body', () => {
		expect(decodePublicFormPhoto('data:image/png;base64,')).toBeNull();
	});

	it('rejects a photo over the byte cap', () => {
		const big = new Array(PUBLIC_FORM_PHOTO_MAX_BYTES + 1024).fill(0);
		[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].forEach((byte, i) => (big[i] = byte));
		expect(decodePublicFormPhoto(dataUrl('image/png', big))).toBeNull();
	});
});
