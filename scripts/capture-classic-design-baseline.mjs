/** Cold authenticated Classic baseline; credentials stay in Login.md, never in artifacts. */
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';
const origin = process.env.PROOF_ORIGIN ?? 'http://127.0.0.1:4175';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname));
const output = process.env.PROOF_OUTPUT ?? '/tmp/classic-design-baseline';
await mkdir(output, { recursive: true });
const login = await readFile('Login.md', 'utf8');
const credentials = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);
assert(credentials, 'Contractor owner test login missing');
const browser = await chromium.launch({ headless: true });
try {
	const auth = await browser.newContext();
	const page = await auth.newPage();
	await page.goto(`${origin}/login`);
	await page.locator('input[type=email]').fill(credentials[1]);
	await page.locator('input[type=password]').fill(credentials[2]);
	await page.getByRole('button', { name: /sign in/i }).click();
	await page.waitForURL('**/dashboard', { timeout: 60000 });
	const storageState = await auth.storageState();
	await auth.close();
	const results = [];
	for (const width of [1440, 390]) {
		const context = await browser.newContext({ storageState, viewport: { width, height: 900 } });
		const page = await context.newPage();
		const errors = [];
		page.on('pageerror', (error) => errors.push(error.message));
		const cdp = await context.newCDPSession(page);
		await cdp.send('Network.enable');
		await cdp.send('Network.emulateNetworkConditions', {
			offline: false,
			latency: 150,
			downloadThroughput: 200000,
			uploadThroughput: 93750
		});
		await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
		await page.addInitScript(() => {
			window.__baseline = { lcp: 0, cls: 0 };
			new PerformanceObserver((list) => {
				for (const entry of list.getEntries()) window.__baseline.lcp = entry.startTime;
			}).observe({ type: 'largest-contentful-paint', buffered: true });
			new PerformanceObserver((list) => {
				for (const entry of list.getEntries())
					if (!entry.hadRecentInput) window.__baseline.cls += entry.value;
			}).observe({ type: 'layout-shift', buffered: true });
		});
		await page.goto(`${origin}/dashboard`, { waitUntil: 'domcontentloaded' });
		await page.waitForTimeout(15000);
		assert.equal(new URL(page.url()).pathname, '/dashboard');
		await page.screenshot({ path: `${output}/classic-${width}.png` });
		results.push({
			width,
			errors,
			...(await page.evaluate(() => ({
				metrics: window.__baseline,
				assets: performance
					.getEntriesByType('resource')
					.filter((e) => /\.(css|js|woff2?)(\?|$)/.test(e.name))
					.map((e) => ({
						path: new URL(e.name).pathname,
						encoded: e.encodedBodySize,
						transfer: e.transferSize
					}))
			})))
		});
		await context.close();
	}
	await writeFile(
		`${output}/results.json`,
		JSON.stringify(
			{
				profile:
					'Cold authenticated dashboard, fresh context per width, Chromium, 4x CPU, 150ms RTT, 1.6Mbps down, 750Kbps up, 15s idle warming; local adapter-node HTTP',
				results
			},
			null,
			2
		)
	);
	assert(
		results.every((r) => r.errors.length === 0),
		'Dashboard browser errors; inspect evidence'
	);
	console.log(`PASS: cold authenticated Classic baseline captured at both widths: ${output}`);
} finally {
	await browser.close();
}
