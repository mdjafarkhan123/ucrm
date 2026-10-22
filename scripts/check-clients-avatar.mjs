/** Check the clients list avatar shape after removing the rounded-square override. */
import { chromium } from 'playwright';
import { readFile, mkdir } from 'node:fs/promises';

const out = '/tmp/opencode/clients-avatar';
await mkdir(out, { recursive: true });
const login = await readFile('Login.md', 'utf8');
const credentials = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);
const base = process.env.ORIGIN ?? 'http://localhost:5173';

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
page.on('console', (m) => console.log('console:', m.type(), m.text()));
page.on('requestfailed', (r) => console.log('failed:', r.url(), r.failure()?.errorText));
page.on('response', (r) => {
	if (r.url().includes('/api/')) console.log('api:', r.status(), r.url());
});
await page.goto(`${base}/login`);
await page.locator('input[type=email]').fill(credentials[1]);
await page.locator('input[type=password]').fill(credentials[2]);
let signedIn = false;
for (let attempt = 1; attempt <= 4 && !signedIn; attempt += 1) {
	await page.getByRole('button', { name: /sign in/i }).click();
	try {
		await page.waitForURL(/dashboard|\/jafar/, { timeout: 12000 });
		signedIn = true;
	} catch {
		console.log(`attempt ${attempt} stayed on`, page.url());
		await page.waitForTimeout(1500);
	}
}
if (!signedIn) {
	console.log('body:', (await page.locator('body').innerText()).slice(0, 800));
	throw new Error('sign in failed');
}

await page.goto(`${base}/clients`, { waitUntil: 'networkidle' });
await page.locator('.clients-table__avatar, table tbody tr').first().waitFor();
await page.waitForTimeout(800);

const shapes = await page.$$eval('.avatar', (nodes) =>
	nodes.slice(0, 5).map((n) => {
		const style = getComputedStyle(n);
		return {
			width: style.width,
			height: style.height,
			borderRadius: style.borderRadius,
			borderTopLeftRadius: style.borderTopLeftRadius,
			text: n.textContent?.trim()
		};
	})
);
console.log('avatars', JSON.stringify(shapes, null, 2));

await page.screenshot({ path: `${out}/clients-1440.png`, fullPage: false });
const cell = page.locator('.clients-table__name').first();
if (await cell.count()) await cell.screenshot({ path: `${out}/clients-name-1440.png` });

await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/clients-390.png`, fullPage: false });

await browser.close();
