import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, mkdir } from 'node:fs/promises';

const origin = 'http://localhost:5191';
const out = process.argv[2];
await mkdir(out, { recursive: true });
const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(`${origin}/login`);
await page.waitForLoadState('networkidle');
await page.locator('input[type=email]').fill(email);
await page.locator('input[type=password]').fill(password);
await page.locator('button[type=submit]').first().click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 });

await page.goto(`${origin}/jobs`);
const jobLink = page.locator('a[href^="/jobs/"]').filter({ hasNotText: 'New' }).first();
await jobLink.waitFor({ timeout: 30000 });
const jobUrl = origin + (await jobLink.getAttribute('href'));
console.log('job', jobUrl);

const card = () => page.locator('.notes-panel--compact').first().locator('xpath=ancestor::section[1]');
async function shot(name) {
	const c = card();
	await c.scrollIntoViewIfNeeded();
	await page.waitForTimeout(300);
	await c.screenshot({ path: `${out}/${name}.png` });
	console.log('shot', name);
}

const now = Date.now();
const iso = (h) => new Date(now - h * 3600_000).toISOString();
const fixture = [
	{ body: 'Gate code 4412. Dog is friendly — keep the side gate shut.', pinned: true, at: 30, edited: false },
	{ body: 'Gutter on the north side is cracked. Bring the 10 ft ladder.', pinned: false, at: 2, edited: true },
	{ body: 'Prefers a text after 5 pm, not a call.', pinned: false, at: 20, edited: false }
];

async function openJob(mode) {
	await page.unroute('**/api/notes?**').catch(() => {});
	if (mode === 'loading')
		await page.route('**/api/notes?**', () => new Promise(() => {}));
	if (mode === 'error')
		await page.route('**/api/notes?**', (r) =>
			r.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"x"}' })
		);
	if (mode === 'empty')
		await page.route('**/api/notes?**', (r) =>
			r.fulfill({ status: 200, contentType: 'application/json', body: '{"notes":[]}' })
		);
	if (mode === 'fixture')
		await page.route('**/api/notes?**', async (r) => {
			const res = await r.fetch();
			const real = (await res.json()).notes ?? [];
			const author = real[0]?.created_by ?? null;
			const notes = fixture.map((n, i) => ({
				id: `00000000-0000-4000-8000-00000000000${i}`,
				body: n.body,
				pinned: n.pinned,
				created_at: iso(n.at),
				created_by: author,
				edited_at: n.edited ? iso(1) : null,
				edited_by: n.edited ? author : null,
				links: [],
				files: [],
				mention_user_ids: []
			}));
			await r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ notes }) });
		});
	await page.goto(jobUrl);
	await page.locator('.notes-panel--compact').first().waitFor({ timeout: 30000 });
	if (mode === 'error') await page.locator('.notes-panel__state[role=alert]').waitFor({ timeout: 40000 });
	await page.waitForTimeout(mode === 'loading' ? 800 : 1500);
}

const theme = process.argv[3] ?? 'light';
if (theme === 'dark') {
	await page.emulateMedia({ colorScheme: 'dark' });
}

await openJob('real');
await shot(`real-${theme}`);
await openJob('loading');
await shot(`loading-${theme}`);
await openJob('error');
await shot(`error-${theme}`);
await openJob('empty');
await shot(`empty-${theme}`);
await openJob('fixture');
await shot(`notes-${theme}`);

// Menu open while typing.
const field = page.locator('.notes-panel__field-input').first();
await field.fill("Ladder's in the van.");
await page.getByRole('button', { name: 'Note actions' }).nth(1).click();
await page.waitForTimeout(300);
const box = await card().boundingBox();
await page.screenshot({ path: `${out}/menu-${theme}.png`, clip: { ...box, height: box.height + 60 } });
console.log('shot menu');
await page.keyboard.press('Escape');

// Waiting for Save: add the typed note, edit the second, delete the third.
await page.getByRole('button', { name: 'Add note' }).click();
await page.getByRole('button', { name: 'Note actions' }).nth(1).click();
await page.getByRole('menuitem', { name: 'Edit' }).click();
await page.locator('.notes-panel__edit-input').fill('Gutter on the north side is cracked. Bring the 10 ft ladder and sealant.');
await shot(`editing-${theme}`);
await page.getByRole('button', { name: 'Done' }).click();
await page.getByRole('button', { name: 'Note actions' }).nth(2).click();
await page.getByRole('menuitem', { name: 'Delete' }).click();
await page.waitForTimeout(300);
await shot(`waiting-${theme}`);

console.log('errors', JSON.stringify(errors));
await browser.close();
