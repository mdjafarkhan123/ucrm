import { describe, expect, it } from 'vitest';
import sharp from 'sharp';
import {
	THUMBNAIL_MAX_EDGE_PIXELS,
	THUMBNAIL_SOURCE_MAX_BYTES,
	createThumbnail,
	wantsThumbnail
} from './derivatives';

async function image(width: number, height: number, format: 'jpeg' | 'png'): Promise<Uint8Array> {
	const created = sharp({
		create: { width, height, channels: 4, background: { r: 51, g: 102, b: 153, alpha: 0.5 } }
	});
	const buffer = await (format === 'png' ? created.png() : created.jpeg()).toBuffer();
	return new Uint8Array(buffer);
}

describe('wantsThumbnail', () => {
	it('accepts the image formats the allowlist previews', () => {
		for (const name of ['roof.jpg', 'roof.JPEG', 'plan.png', 'clip.gif', 'shot.webp'])
			expect(wantsThumbnail(name, 1_000_000)).toBe(true);
	});

	it('leaves documents to their typed icon', () => {
		for (const name of ['quote.pdf', 'sheet.xlsx', 'notes.txt', 'list.csv'])
			expect(wantsThumbnail(name, 1_000_000)).toBe(false);
	});

	it('refuses an image too large to hold in memory', () => {
		expect(wantsThumbnail('huge.jpg', THUMBNAIL_SOURCE_MAX_BYTES)).toBe(true);
		expect(wantsThumbnail('huge.jpg', THUMBNAIL_SOURCE_MAX_BYTES + 1)).toBe(false);
		expect(wantsThumbnail('empty.jpg', 0)).toBe(false);
	});
});

describe('createThumbnail', () => {
	it('shrinks a large photo to a small JPEG within the preview size', async () => {
		const thumbnail = await createThumbnail(await image(2400, 1600, 'jpeg'));
		expect(thumbnail).not.toBeNull();

		const meta = await sharp(thumbnail!).metadata();
		expect(meta.format).toBe('jpeg');
		expect(Math.max(meta.width ?? 0, meta.height ?? 0)).toBe(THUMBNAIL_MAX_EDGE_PIXELS);
		expect(meta.width).toBe(480);
		expect(meta.height).toBe(320);
	});

	it('never enlarges an image that is already small', async () => {
		const thumbnail = await createThumbnail(await image(120, 90, 'png'));
		const meta = await sharp(thumbnail!).metadata();
		expect(meta.width).toBe(120);
		expect(meta.height).toBe(90);
	});

	it('flattens transparency instead of leaving it black', async () => {
		const thumbnail = await createThumbnail(await image(200, 200, 'png'));
		const meta = await sharp(thumbnail!).metadata();
		expect(meta.format).toBe('jpeg');
		expect(meta.hasAlpha).toBe(false);
	});

	it('answers null rather than throwing when the bytes are not a readable image', async () => {
		expect(await createThumbnail(Uint8Array.from([0xff, 0xd8, 0xff, 0x00, 0x01]))).toBeNull();
	});
});
