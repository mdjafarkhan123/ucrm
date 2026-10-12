// Part 6 live journey, signed in as the Field member (Login.md), who now has "Start and stop their own timers"
// only: start a timer on their Job #20 visit, stop it after a minute, then check that Job Labor and Timesheets
// show their hours with no way to add, edit or delete them, and that the /api routes refuse those changes.
// Usage: node docs/research/time-clock-timers-only-2026-10-12/journey.mjs [--width=390] [--timer]
// Without --timer the visit timer is not run again; the screens and refusals are still checked.
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, writeFile, access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const origin = process.env.ORIGIN ?? 'http://localhost:5174';
const args = process.argv.slice(2);
const flag = (key, fallback) =>
	args.find((arg) => arg.startsWith(`--${key}=`))?.split('=')[1] ?? fallback;
const width = Number(flag('width', '390'));
const runTimer = args.includes('--timer');
const statePath = join(here, 'state-field.json');
const jobId = '698bbe09-ce9f-4b92-87b2-57dfcd4f9b1e';

const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(/Field member: `([^`]+)` \/\s*`([^`]+)`/);

const browser = await chromium.launch({ headless: true });
const results = [];
let step = 0;

async function shot(page, name) {
	step += 1;
	await page.waitForTimeout(500);
	const file = join(here, `${step}-${name}-${width}.png`);
	await page.screenshot({ path: file, fullPage: false });
	console.log('shot', file);
}

function check(name, passed, detail = '') {
	results.push({ name, passed, detail });
	console.log(passed ? 'PASS' : 'FAIL', name, detail);
}

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
	page.on('pageerror', (error) => console.log('pageerror', error.message));

	// Job #20: the Labor section offers no way to type hours.
	await page.goto(`${origin}/jobs/${jobId}`);
	await page.getByRole('heading', { name: /labor/i }).first().waitFor({ timeout: 30000 });
	await page.waitForTimeout(1500);
	const labor = page.locator('section', { has: page.getByRole('heading', { name: /labor/i }) }).first();
	await labor.scrollIntoViewIfNeeded();
	check(
		'Job Labor has no Add hours',
		(await labor.getByRole('button', { name: /add (hours|time)/i }).count()) === 0
	);
	await shot(page, 'job-labor');

	if (runTimer) {
		await page.getByRole('button', { name: 'Start timer' }).first().click();
		await page.getByRole('button', { name: 'Stop timer' }).first().waitFor({ timeout: 15000 });
		check('Start timer works', true);
		await shot(page, 'timer-running');
		await page.waitForTimeout(62000);
		await page.getByRole('button', { name: 'Stop timer' }).first().click();
		await page.getByRole('button', { name: 'Start timer' }).first().waitFor({ timeout: 15000 });
		await page.waitForTimeout(1500);
		check('Stop timer works', true);
		await labor.scrollIntoViewIfNeeded();
		await shot(page, 'timer-stopped');
	}

	// Timesheets: their own row, entries without Edit or Delete, and no Add entry.
	await page.goto(`${origin}/timesheets`);
	await page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
	await page.waitForTimeout(2000);
	check(
		'Timesheets has no Add entry',
		(await page.getByRole('button', { name: /add entry/i }).count()) === 0
	);
	await shot(page, 'timesheets-week');
	// Someone who sees only themselves starts with their own row open.
	const ownRow = page.locator('button[aria-expanded]', { hasText: 'Field Tester' }).first();
	if ((await ownRow.getAttribute('aria-expanded')) !== 'true') await ownRow.click();
	const menus = page.getByRole('button', { name: 'Entry actions' });
	await menus.first().waitFor({ timeout: 15000 });
	check('Own entries are listed', (await menus.count()) > 0, `${await menus.count()} entries`);
	await menus.first().click();
	const items = page.getByRole('menuitem');
	await items.first().waitFor({ timeout: 5000 });
	const labels = await items.allInnerTexts();
	check(
		'Entry menu offers History only, no Edit, Stop or Delete',
		labels.map((label) => label.trim()).join(',') === 'History',
		labels.join(', ')
	);
	await shot(page, 'timesheets-entry-menu');
	await page.keyboard.press('Escape');

	// The /api routes refuse typed changes, whatever the screen shows.
	const me = await page.request.get(`${origin}/api/time-clock/timer`);
	const own = await me.json();
	console.log('timer state', JSON.stringify(own).slice(0, 200));
	const today = new Date().toISOString().slice(0, 10);
	const add = await page.request.post(`${origin}/api/time-clock/timesheets/entries`, {
		data: { user_id: own.user_id ?? '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', job_id: null, day: today, start_time: '06:00', end_time: '07:00' }
	});
	check('API refuses adding an entry', add.status() === 403, `${add.status()} ${await add.text()}`);
	const del = await page.request.delete(
		`${origin}/api/time-clock/timesheets/entries/fe1ae731-90e3-4b6d-95da-49924ea9a39a`
	);
	check('API refuses deleting an entry', del.status() === 403, `${del.status()}`);
	const labourAdd = await page.request.post(`${origin}/api/jobs/${jobId}/time-entries`, {
		data: {
			user_id: '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb',
			started_at: new Date(Date.now() - 3600000).toISOString(),
			minutes: 30
		}
	});
	// The Labor commands answer a refusal as not-found on purpose (src/lib/server/jobs/errors.ts).
	check(
		'Job Labor API refuses typed hours',
		labourAdd.status() === 404,
		`${labourAdd.status()} ${(await labourAdd.text()).slice(0, 160)}`
	);

	await context.close();
} finally {
	await browser.close();
	const failed = results.filter((result) => !result.passed);
	console.log(`${results.length - failed.length}/${results.length} checks passed`);
	if (failed.length) process.exitCode = 1;
}
