import { describe, expect, it } from 'vitest';
import {
	MAX_FILE_SIZE_BYTES,
	checkUploadClaim,
	checkUploadedContent,
	detectSignature
} from './upload-policy';

const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
const PNG = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PDF = Uint8Array.from([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]);
const ZIP = Uint8Array.from([0x50, 0x4b, 0x03, 0x04]);

describe('checkUploadClaim', () => {
	it('accepts a photo a contractor would actually send', () => {
		expect(
			checkUploadClaim({ fileName: 'roof.jpg', mimeType: 'image/jpeg', sizeBytes: 2_000_000 })
		).toEqual({ allowed: true, signature: 'jpeg' });
	});

	it('refuses a file type that is not on the allowlist', () => {
		const verdict = checkUploadClaim({
			fileName: 'invoice.exe',
			mimeType: 'application/octet-stream',
			sizeBytes: 1000
		});
		expect(verdict).toMatchObject({ allowed: false, field: 'file_name' });
	});

	it('refuses a dangerous file wearing an allowed extension in its declared type', () => {
		const verdict = checkUploadClaim({
			fileName: 'photo.jpg',
			mimeType: 'application/x-msdownload',
			sizeBytes: 1000
		});
		expect(verdict).toMatchObject({ allowed: false, field: 'mime_type' });
	});

	it('refuses a file over the approved 100 MB ceiling', () => {
		const verdict = checkUploadClaim({
			fileName: 'site.pdf',
			mimeType: 'application/pdf',
			sizeBytes: MAX_FILE_SIZE_BYTES + 1
		});
		expect(verdict).toMatchObject({ allowed: false, field: 'size_bytes' });
	});

	it('refuses an empty file', () => {
		expect(
			checkUploadClaim({ fileName: 'site.pdf', mimeType: 'application/pdf', sizeBytes: 0 })
		).toMatchObject({ allowed: false, field: 'size_bytes' });
	});

	it('has no video type yet, because its limits are not measured', () => {
		expect(
			checkUploadClaim({ fileName: 'walkthrough.mp4', mimeType: 'video/mp4', sizeBytes: 5_000_000 })
		).toMatchObject({ allowed: false });
	});
});

describe('detectSignature', () => {
	it('reads the families the allowlist relies on', () => {
		expect(detectSignature(JPEG)).toBe('jpeg');
		expect(detectSignature(PNG)).toBe('png');
		expect(detectSignature(PDF)).toBe('pdf');
		expect(detectSignature(ZIP)).toBe('zip');
	});

	it('fails closed on content it does not recognise', () => {
		expect(detectSignature(Uint8Array.from([0x00, 0x01, 0x02, 0x03]))).toBeNull();
	});
});

describe('checkUploadedContent', () => {
	it('accepts bytes that match the name they were registered under', () => {
		expect(checkUploadedContent('roof.jpg', JPEG, 1234, 1234)).toEqual({ ok: true });
	});

	it('refuses a program renamed to look like a photo', () => {
		const verdict = checkUploadedContent(
			'roof.jpg',
			Uint8Array.from([0x4d, 0x5a, 0x90, 0x00]),
			1234,
			1234
		);
		expect(verdict).toMatchObject({ ok: false });
	});

	it('refuses an object whose stored size is not the size that was approved', () => {
		expect(checkUploadedContent('roof.jpg', JPEG, 9_000_000, 1234)).toMatchObject({ ok: false });
	});

	it('accepts plain text, which has no signature to check', () => {
		expect(
			checkUploadedContent('clients.csv', Uint8Array.from([0x6e, 0x61, 0x6d, 0x65]), 4, 4)
		).toEqual({ ok: true });
	});
});
