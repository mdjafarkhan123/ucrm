import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, mkdir } from 'node:fs/promises';

const out = process.argv[2];
const theme = process.argv[3] ?? 'light';
const role = process.argv[4] ?? 'Contractor owner';
const origin = 'http://localhost:5191';
await mkdir(out, { recursive: true });
const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(new RegExp(`${role}: ` + '`([^`]+)` \\/\\s*`([^`]+)`'));
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
if (theme === 'dark') await page.emulateMedia({ colorScheme: 'dark' });
const errors = [];
page.on('pageerror', (error) => errors.push(String(error)));
await page.goto(`${origin}/login`);
await page.waitForLoadState('networkidle');
await page.locator('input[type=email]').fill(email);
await page.locator('input[type=password]').fill(password);
await page.locator('button[type=submit]').first().click();
await page
	.waitForURL((url) => !url.pathname.startsWith('/login'))
	.catch(async (error) => {
		console.log('login feedback', (await page.locator('body').innerText()).slice(-400));
		throw error;
	});
await page.goto(`${origin}/jobs`);
await page.locator('a[href^="/jobs/"]').first().waitFor();
const hrefs = await page
	.locator('a[href^="/jobs/"]')
	.evaluateAll((links) =>
		[...new Set(links.map((link) => link.getAttribute('href')))].filter((href) =>
			/\/[0-9a-f]{8}-[0-9a-f]{4}-/.test(href)
		)
	);
let found = false;
for (const href of ['/jobs/138844e5-a1cf-41e6-8f35-b09e3bd2bf86', ...hrefs]) {
	const job = await page.evaluate(async (path) => (await fetch(`/api${path}`)).json(), href);
	const record = job.job ?? job;
	console.log('candidate', href, record.job_type, record.price_basis);
	if (record.job_type !== 'recurring' || record.price_basis !== 'per_visit') continue;
	await page.goto(origin + href);
	const menu = page.getByRole('button', { name: 'Actions for this visit' }).first();
	await menu.waitFor({ timeout: 30000 }).catch(() => {});
	console.log(
		'visit menu count',
		await page.getByRole('button', { name: 'Actions for this visit' }).count()
	);
	if (!(await menu.isVisible().catch(() => false))) continue;
	await menu.click();
	const edit = page.getByRole('menuitem', { name: 'Edit', exact: true });
	if (!(await edit.isVisible().catch(() => false))) continue;
	await edit.click();
	const dialog = page.getByRole('dialog').last();
	const card = dialog.locator('section.section-block.pricing-block--concept');
	await card.waitFor({ timeout: 30000 });
	await card.scrollIntoViewIfNeeded();
	await card.screenshot({ path: `${out}/visit-${theme}.png` });
	console.log('shot visit', href);
	found = true;
	break;
}
if (!found) console.log('No editable per-visit job in the visible jobs list');
console.log('errors', JSON.stringify(errors));
await browser.close();
