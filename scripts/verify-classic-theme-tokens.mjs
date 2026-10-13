/** Check the approved Classic tokens at runtime, including portalled overlays and Botanical isolation. */
import assert from 'node:assert/strict';
import { mkdir, readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const classicOrigin = process.env.CLASSIC_PROOF_ORIGIN ?? 'http://127.0.0.1:4192';
const botanicalOrigin = process.env.BOTANICAL_PROOF_ORIGIN ?? 'http://127.0.0.1:4193';
const output = process.env.PROOF_OUTPUT ?? '/tmp/classic-theme-b1';
await mkdir(output, { recursive: true });
const login = await readFile('Login.md', 'utf8');
const credentials = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);
assert(credentials, 'Existing owner test login missing');

const browser = await chromium.launch({ headless: true });
try {
	const auth = await browser.newContext();
	const signIn = await auth.newPage();
	await signIn.goto(`${classicOrigin}/login`);
	await signIn.locator('input[type=email]').fill(credentials[1]);
	await signIn.locator('input[type=password]').fill(credentials[2]);
	await signIn.getByRole('button', { name: /sign in/i }).click();
	await signIn.waitForURL('**/dashboard', { timeout: 60000 });
	const storageState = await auth.storageState();
	await auth.close();

	for (const width of [1440, 390]) {
		const context = await browser.newContext({ storageState, viewport: { width, height: 900 } });
		await context.addInitScript(() => localStorage.setItem('ucrm-theme', 'light'));
		const page = await context.newPage();
		await page.goto(`${classicOrigin}/dashboard`);
		await page.locator('[data-presentation="classic"]').waitFor();
		const light = await page.evaluate(() =>
			getComputedStyle(document.documentElement).getPropertyValue('--classic2-page').trim()
		);
		assert.equal(light.toUpperCase(), '#F3F4F7');
		await page.screenshot({ path: `${output}/classic-${width}-light.png` });
		await page.getByRole('button', { name: /Account menu for/ }).click();
		const menu = page.getByRole('menu').first();
		await menu.waitFor();
		assert.equal(
			(
				await menu.evaluate((node) =>
					getComputedStyle(node).getPropertyValue('--classic2-green').trim()
				)
			).toUpperCase(),
			'#037741'
		);
		await page.keyboard.press('Escape');
		await page.keyboard.press('Control+k');
		const dialog = page.getByRole('dialog', { name: 'Search', exact: true });
		await dialog.waitFor();
		assert.equal(
			(
				await dialog.evaluate((node) =>
					getComputedStyle(node).getPropertyValue('--classic2-ink').trim()
				)
			).toUpperCase(),
			'#101828'
		);
		await page.keyboard.press('Escape');
		await page.getByRole('button', { name: 'Switch to dark mode' }).click();
		assert.equal(
			(
				await page.evaluate(() =>
					getComputedStyle(document.documentElement).getPropertyValue('--classic2-page').trim()
				)
			).toUpperCase(),
			'#0B1410'
		);
		await page.screenshot({ path: `${output}/classic-${width}-dark.png` });
		await context.close();
	}

	const botanical = await browser.newContext({ storageState });
	const page = await botanical.newPage();
	await page.goto(`${botanicalOrigin}/dashboard`);
	await page.locator('[data-presentation="botanical"]').waitFor();
	assert.equal(
		await page.evaluate(() =>
			getComputedStyle(document.documentElement).getPropertyValue('--classic2-page').trim()
		),
		''
	);
	await page.screenshot({ path: `${output}/botanical-1440.png` });
	await botanical.close();
	console.log(
		'Classic tokens: light, dark, menu and dialog pass at 1440px and 390px; Botanical has no Classic tokens.'
	);
} finally {
	await browser.close();
}
