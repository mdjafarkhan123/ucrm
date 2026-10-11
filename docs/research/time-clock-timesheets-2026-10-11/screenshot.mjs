// Screenshot helper for the Timesheets screen check. Usage:
//   node docs/research/time-clock-timesheets-2026-10-11/screenshot.mjs <role> <path> <name> [--width=1440] [--open=first|all|none] [--mock=file.json] [--entries=file.json] [--dark]
// Logs in once per role (state cached in ./state-<role>.json) and saves <name>-<width>.png here.
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, writeFile, access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const origin = process.env.ORIGIN ?? 'http://localhost:5181';
const [role, path, name, ...rest] = process.argv.slice(2);
const flag = (key, fallback) =>
	rest.find((arg) => arg.startsWith(`--${key}=`))?.split('=')[1] ?? fallback;
const width = Number(flag('width', '1440'));
const open = flag('open', 'none');
const mock = flag('mock', null);
const entriesMock = flag('entries', null);
const dark = rest.includes('--dark');

const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const accounts = {
	owner: login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/),
	field: login.match(/Field member: `([^`]+)` \/\s*`([^`]+)`/),
	office: ['', 'dev.jafarkhan+office@gmail.com', login.match(/all `([^`]+)`/)?.[1]],
	sales: ['', 'dev.jafarkhan+sales@gmail.com', login.match(/all `([^`]+)`/)?.[1]]
};
const statePath = join(here, `state-${role}.json`);

const browser = await chromium.launch({ headless: true });
try {
	let storageState;
	try {
		await access(statePath);
		storageState = statePath;
	} catch {
		const context = await browser.newContext();
		const page = await context.newPage();
		await page.goto(`${origin}/login`);
		await page.waitForLoadState('networkidle');
		await page.waitForTimeout(1500);
		await page.locator('input[type=email]').fill(accounts[role][1]);
		await page.locator('input[type=password]').fill(accounts[role][2]);
		await page.getByRole('button', { name: /sign in/i }).click();
		await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 60000 });
		await writeFile(statePath, JSON.stringify(await context.storageState()));
		storageState = statePath;
		await context.close();
	}

	const context = await browser.newContext({
		storageState,
		viewport: { width, height: width < 640 ? 844 : 900 },
		deviceScaleFactor: 1,
		colorScheme: dark ? 'dark' : 'light'
	});
	const page = await context.newPage();
	const errors = [];
	page.on('pageerror', (error) => errors.push(error.message));
	page.on('console', (message) => {
		if (message.type() === 'error') errors.push(message.text());
	});
	if (mock) {
		const body = await readFile(mock, 'utf8');
		await page.route('**/api/time-clock/timesheets?*', (route) =>
			route.fulfill({ status: Number(flag('status', '200')), contentType: 'application/json', body })
		);
	}
	if (entriesMock) {
		const body = await readFile(entriesMock, 'utf8');
		await page.route('**/api/time-clock/timesheets/entries?*', (route) =>
			route.fulfill({ status: 200, contentType: 'application/json', body })
		);
	}
	await page.goto(`${origin}${path}`);
	await page.waitForLoadState('networkidle');
	await page.waitForTimeout(Number(flag('wait', '800')));
	if (open === 'first' || open === 'all') {
		const toggles = page.locator('.timesheet-person__toggle[aria-expanded=false]');
		const count = open === 'first' ? Math.min(1, await toggles.count()) : await toggles.count();
		for (let i = 0; i < count; i++) await toggles.first().click();
		await page.waitForLoadState('networkidle');
		await page.waitForTimeout(600);
	}
	if (rest.includes('--bottom')) {
		await page.evaluate(() => {
			for (const el of document.querySelectorAll('*')) {
				if (el.scrollHeight > el.clientHeight + 10 && getComputedStyle(el).overflowY !== 'visible') el.scrollTop = el.scrollHeight;
			}
		});
		await page.waitForTimeout(300);
	}
	if (rest.includes('--focus')) {
		await page.locator('.timesheet-person__toggle').nth(1).focus();
		await page.keyboard.press('Shift+Tab');
		await page.keyboard.press('Tab');
		await page.waitForTimeout(200);
	}
	const file = join(here, `${name}-${width}.png`);
	await page.screenshot({ path: file, fullPage: true });
	console.log(file);
	if (errors.length) console.log('ERRORS:', errors.join('\n'));
} finally {
	await browser.close();
}
