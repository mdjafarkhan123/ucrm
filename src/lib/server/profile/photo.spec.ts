import { describe, expect, it } from 'vitest';
import sharp from 'sharp';
import {
	PROFILE_PHOTO_EDGE_PIXELS,
	processProfilePhoto,
	profilePhotoObjectKey,
	profilePhotoUrl
} from './photo';

const USER = '0b7f6c1e-2a4d-4f8e-9c3b-5d6e7f8a9b0c';
const PHOTO = '1c2d3e4f-5a6b-4c7d-8e9f-0a1b2c3d4e5f';

describe('processProfilePhoto', () => {
	it('turns a wide phone photo into a small WEBP square', async () => {
		const source = await sharp({
			create: { width: 3000, height: 2000, channels: 3, background: { r: 200, g: 120, b: 40 } }
		})
			.jpeg()
			.toBuffer();

		const photo = await processProfilePhoto(new Uint8Array(source));
		expect(photo).not.toBeNull();
		const meta = await sharp(photo!).metadata();
		expect(meta.format).toBe('webp');
		expect(meta.width).toBe(PROFILE_PHOTO_EDGE_PIXELS);
		expect(meta.height).toBe(PROFILE_PHOTO_EDGE_PIXELS);
	});

	it('drops the location and camera details a phone writes into a photo', async () => {
		const source = await sharp({
			create: { width: 800, height: 800, channels: 3, background: { r: 10, g: 20, b: 30 } }
		})
			.jpeg()
			.withExif({ IFD0: { Make: 'PhoneMaker', Model: 'Phone 15' }, IFD3: { GPSLatitudeRef: 'N' } })
			.toBuffer();
		expect((await sharp(source).metadata()).exif).toBeDefined();

		const photo = await processProfilePhoto(new Uint8Array(source));
		const meta = await sharp(photo!).metadata();
		expect(meta.exif).toBeUndefined();
	});

	it('stands a sideways photo upright before cropping', async () => {
		// Stored 400 wide by 200 tall, with orientation 6: the camera says "turn me a quarter clockwise".
		const source = await sharp({
			create: { width: 400, height: 200, channels: 3, background: { r: 0, g: 0, b: 0 } }
		})
			.composite([
				{
					input: await sharp({
						create: { width: 200, height: 200, channels: 3, background: { r: 255, g: 0, b: 0 } }
					})
						.png()
						.toBuffer(),
					left: 0,
					top: 0
				}
			])
			.jpeg()
			.withMetadata({ orientation: 6 })
			.toBuffer();

		const photo = await processProfilePhoto(new Uint8Array(source));
		// Upright it is 200 wide by 400 tall with red on top; the centre crop is the boundary, so the top
		// row is red and the bottom row black. Without the rotation the square would be split left/right.
		const { data, info } = await sharp(photo!).raw().toBuffer({ resolveWithObject: true });
		const pixel = (x: number, y: number) => data[(y * info.width + x) * info.channels];
		expect(pixel(128, 5)).toBeGreaterThan(200);
		expect(pixel(128, 250)).toBeLessThan(50);
	});

	it('refuses bytes that are not an image', async () => {
		expect(
			await processProfilePhoto(new TextEncoder().encode('<svg onload="alert(1)"/>'))
		).toBeNull();
	});
});

describe('profile photo addresses', () => {
	// The profiles table only accepts these exact shapes, so they must not drift from the migration.
	it('matches the shapes the database enforces', () => {
		expect(profilePhotoObjectKey(USER, PHOTO)).toMatch(
			/^profile-photos\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.webp$/
		);
		expect(profilePhotoUrl(USER, PHOTO)).toMatch(
			/^\/api\/profile-photos\/[0-9a-f-]{36}\?v=[0-9a-f-]{36}$/
		);
	});
});
