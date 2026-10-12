// Part 6: the owner opens the Field member's Team access and finds the new lowest time rung ticked by the
// Field role. Usage: node docs/research/time-clock-timers-only-2026-10-12/team-access.mjs [--width=390]
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, writeFile, access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const origin = process.env.ORIGIN ?? 'http://localhost:5174';
const width = Number(process.argv.find((arg) => arg.startsWith('--width='))?.split('=')[1] ?? '390');
const statePath = join(here, 'state-owner.json');
const fieldMember = '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb';

const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);
const browser = await chromium.launch({ headless: true });
try {
	try {
		await access(statePath);
	} catch {
		const context = await browser.newContext();
		const page = await context.newPage();
		await page.goto(`${origin}/login`);
		await page.waitForLoadState('networkidle');
		await page.waitForTimeout(1500);
		await page.locator('input[type=email]').fill(email);
		await page.locator('input[type=password]').fill(password);
		await page.getByRole('button', { name: /sign in/i }).click();
		await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 60000 });
		await writeFile(statePath, JSON.stringify(await context.storageState()));
		await context.close();
	}
	const context = await browser.newContext({
		storageState: statePath,
		viewport: { width, height: width < 800 ? 844 : 900 },
		deviceScaleFactor: width < 800 ? 2 : 1
	});
	const page = await context.newPage();
	await page.goto(`${origin}/settings/team/${fieldMember}`);
	await page.getByRole('button', { name: 'Manage access' }).click();
	const timers = page.getByText('Start and stop their own timers').first();
	await timers.waitFor({ timeout: 30000 });
	await timers.scrollIntoViewIfNeeded();
	await page.evaluate(() => window.scrollBy(0, -120));
	await page.waitForTimeout(800);
	for (const label of [
		'Start and stop their own timers',
		'Record and change their own hours',
		'Record and change anyone’s hours'
	]) {
		const box = page.getByRole('checkbox', { name: label }).or(page.getByRole('switch', { name: label }));
		const checked = (await box.count()) ? await box.first().isChecked() : 'not found';
		console.log(label, '→', checked);
	}
	await page.screenshot({ path: join(here, `team-access-${width}.png`) });
	await context.close();
} finally {
	await browser.close();
}
