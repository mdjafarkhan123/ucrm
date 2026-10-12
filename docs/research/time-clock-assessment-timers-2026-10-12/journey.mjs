// Part 8 live journey on the branch dev app (Login.md Field member). On a Request whose Assessment is today
// and assigned to them: Start on the Request page, header shows Assessment, Stop, Timesheets day shows it.
// Tomorrow's Assessment offers no Start. Usage: node journey.mjs [--width=1440] [--request=<id>] [--tomorrow=<id>]
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, writeFile, access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const origin = process.env.ORIGIN ?? 'http://localhost:5180';
const args = process.argv.slice(2);
const flag = (key, fallback) => args.find((a) => a.startsWith(`--${key}=`))?.split('=')[1] ?? fallback;
const width = Number(flag('width', '1440'));
const today = flag('request', 'd82d9ea4-343c-4d80-bff4-89d987e528da');
const tomorrow = flag('tomorrow', 'f190927c-ed35-4637-b86d-366bcc26905c');
const statePath = join(here, 'state-field.json');
const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(/Field member: `([^`]+)` \/\s*`([^`]+)`/);

const browser = await chromium.launch({ headless: true });
const errors = [];
let failed = 0;
const check = (name, ok, detail = '') => {
	if (!ok) failed++;
	console.log(ok ? 'PASS' : 'FAIL', name, detail);
};
const shot = async (page, name) => {
	await page.waitForTimeout(600);
	await page.screenshot({ path: join(here, `field-${name}-${width}.png`) });
};

try {
	try {
		await access(statePath);
	} catch {
		const c = await browser.newContext();
		const p = await c.newPage();
		await p.goto(`${origin}/login`);
		await p.waitForLoadState('networkidle');
		await p.waitForTimeout(1500);
		await p.locator('input[type=email]').fill(email);
		await p.locator('input[type=password]').fill(password);
		await p.getByRole('button', { name: /sign in/i }).click();
		await p.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 60000 });
		await writeFile(statePath, JSON.stringify(await c.storageState()));
		await c.close();
	}
	const context = await browser.newContext({
		storageState: statePath,
		viewport: { width, height: width < 800 ? 844 : 900 },
		deviceScaleFactor: width < 800 ? 2 : 1
	});
	const page = await context.newPage();
	page.on('pageerror', (e) => errors.push(e.message));
	page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

	// Tomorrow's Assessment: no Start.
	await page.goto(`${origin}/requests/${tomorrow}`);
	await page.getByText('Assessment complete').first().waitFor({ timeout: 30000 });
	await page.waitForTimeout(1500);
	check('Tomorrow offers no Start', (await page.getByRole('button', { name: 'Start timer', exact: true }).count()) === 0);
	await shot(page, 'tomorrow-request');

	// Today's: Start.
	await page.goto(`${origin}/requests/${today}`);
	const start = page.getByRole('button', { name: 'Start timer', exact: true });
	const stopBtn = page.getByRole('button', { name: 'Stop timer', exact: true });
	await start.or(stopBtn).waitFor({ timeout: 30000 });
	if (await start.count()) {
		await shot(page, 'today-request-before');
		await start.click();
	}
	await stopBtn.waitFor({ timeout: 15000 });
	check('Start works on today', true);
	await page.waitForTimeout(1000);
	const header = await page.locator('body').innerText();
	check('Header names Assessment', /Assessment/.test(header));
	await shot(page, 'today-request-running');

	await page.waitForTimeout(62000);
	await stopBtn.click();
	await start.waitFor({ timeout: 15000 });
	check('Stop works', true);

	await page.goto(`${origin}/timesheets?view=day`);
	await page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
	await page.waitForTimeout(2500);
	const row = page.locator('button[aria-expanded]').first();
	if ((await row.count()) && (await row.getAttribute('aria-expanded')) !== 'true') await row.click();
	await page.waitForTimeout(1000);
	const text = await page.locator('body').innerText();
	check('Timesheets shows Assessment entry', /Assessment/.test(text) && /Live check today/.test(text));
	await shot(page, 'timesheets');
} finally {
	console.log('errors', JSON.stringify(errors.slice(0, 5)));
	console.log(failed ? `${failed} FAILED` : 'ALL PASSED');
	await browser.close();
}
