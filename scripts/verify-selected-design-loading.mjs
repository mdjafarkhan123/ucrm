/** Run after npm run build and a localhost Node server with DESIGN_LOADING_PROOF=1. */
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const origin = process.env.PROOF_ORIGIN ?? 'http://127.0.0.1:4175';
const output = process.env.PROOF_OUTPUT ?? '/tmp/selected-design-proof';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname));
await mkdir(output, { recursive: true });
const manifest = JSON.parse(
	await readFile('.svelte-kit/output/client/.vite/manifest.json', 'utf8')
);
function graph(key, visited = new Set()) {
	if (visited.has(key)) return [];
	visited.add(key);
	const entry = manifest[key];
	assert(entry, `Missing manifest entry: ${key}`);
	return [
		entry.file,
		...(entry.css ?? []),
		...(entry.assets ?? []),
		...(entry.imports ?? []).flatMap((key) => graph(key, visited))
	];
}
const graphs = Object.fromEntries(
	['Classic', 'Botanical'].map((design) => [
		design.toLowerCase(),
		['Shell', 'Surface', 'Overlay'].flatMap((surface) =>
			graph(`src/lib/design-loading-proof/${design}${surface}.svelte`)
		)
	])
);
const exclusive = Object.fromEntries(
	Object.entries(graphs).map(([design, files]) => [
		design,
		files.filter((file) => !graphs[design === 'classic' ? 'botanical' : 'classic'].includes(file))
	])
);
// Injected component styles travel inside their exclusive JS and selected SSR head.
// Keep checking external CSS too: a future dependency may reintroduce it.
assert(exclusive.classic.some((f) => f.endsWith('.js')));
assert(exclusive.botanical.some((f) => f.endsWith('.js')));
const styleIds = Object.fromEntries(
	await Promise.all(
		['classic', 'botanical'].map(async (design) => [
			design,
			await Promise.all(
				['Shell', 'Surface', 'Overlay'].map(async (surface) => {
					const name = design === 'classic' ? 'Classic' : 'Botanical';
					const entry = manifest[`src/lib/design-loading-proof/${name}${surface}.svelte`];
					const code = await readFile(`.svelte-kit/output/client/${entry.file}`, 'utf8');
					const hash = code.match(/hash:["'`](svelte-[\w-]+)["'`]/)?.[1];
					assert(hash, `Missing injected CSS identity: ${name}${surface}`);
					return hash;
				})
			)
		])
	)
);
// Parallel request selection must remain request-local, including opposite selections in flight.
const isolated = await Promise.all(
	['classic', 'botanical', 'classic', 'botanical'].map(async (design) => {
		const response = await fetch(`${origin}/demo/design-loading/${design}/overview`);
		assert.equal(response.status, 200);
		assert.equal(response.headers.get('set-cookie'), null);
		const html = await response.text();
		assert(html.includes(`data-proof-design="${design}"`));
		assert(!html.includes(`data-proof-design="${design === 'classic' ? 'botanical' : 'classic'}"`));
		return design;
	})
);
const publicHostStatus = await new Promise((resolve, reject) => {
	const request = http.get(
		`${origin}/demo/design-loading/classic/overview`,
		{
			headers: { host: 'public.example' }
		},
		(response) => {
			resolve(response.statusCode);
			response.resume();
		}
	);
	request.on('error', reject);
});
assert.equal(publicHostStatus, 404, 'Public host cannot enable the private fixture');
const browser = await chromium.launch({ headless: true });
const results = [];
const violations = [];
try {
	for (const design of ['classic', 'botanical']) {
		const url = `${origin}/demo/design-loading/${design}/overview`;
		const response = await fetch(url);
		assert.equal(response.status, 200);
		const html = await response.text();
		assert(html.includes(`data-proof-design="${design}"`), 'Selected shell must be SSR');
		assert(!html.includes('data-proof-surface='), 'Surface must remain CSR');
		const other = design === 'classic' ? 'botanical' : 'classic';
		assert(html.includes(`<style id="${styleIds[design][0]}"`), 'Selected shell CSS must be SSR');
		assert(
			!html.includes(`<style id="${styleIds[design][1]}"`),
			'CSR surface CSS must stay deferred'
		);
		for (const id of styleIds[other])
			if (html.includes(id)) violations.push(`${design}: inactive inline CSS ${id}`);
		for (const file of exclusive[other])
			if (html.includes(file)) violations.push(`${design}: inactive SSR stylesheet ${file}`);
		for (const width of [1440, 390]) {
			const context = await browser.newContext({ viewport: { width, height: 900 } });
			const page = await context.newPage();
			const errors = [],
				requests = [];
			page.on('pageerror', (error) => errors.push(error.message));
			page.on('console', (message) => {
				if (/hydration/i.test(message.text())) errors.push(message.text());
			});
			page.on('request', (request) => requests.push(new URL(request.url()).pathname));
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
				window.__proofMetrics = { lcp: 0, cls: 0, designs: [] };
				new PerformanceObserver((list) => {
					for (const entry of list.getEntries()) window.__proofMetrics.lcp = entry.startTime;
				}).observe({ type: 'largest-contentful-paint', buffered: true });
				new PerformanceObserver((list) => {
					for (const entry of list.getEntries())
						if (!entry.hadRecentInput) window.__proofMetrics.cls += entry.value;
				}).observe({ type: 'layout-shift', buffered: true });
				new MutationObserver(() => {
					const shell = document.querySelector('[data-proof-design]');
					if (shell) window.__proofMetrics.designs.push(shell.getAttribute('data-proof-design'));
				}).observe(document, {
					childList: true,
					subtree: true,
					attributes: true,
					attributeFilter: ['data-proof-design']
				});
			});
			await page.goto(url, { waitUntil: 'domcontentloaded' });
			await page.screenshot({ path: `${output}/${design}-${width}-first.png` });
			await page.locator(`[data-proof-surface="${design}"]`).waitFor();
			assert.equal(await page.locator(`style#${styleIds[design][0]}`).count(), 1);
			assert.equal(await page.locator(`style#${styleIds[design][1]}`).count(), 1);
			for (const id of styleIds[other]) assert.equal(await page.locator(`style#${id}`).count(), 0);
			await page.waitForTimeout(4000); // exercise the actual idle code warmer
			const beforeHover = [...requests];
			const overlayFile =
				manifest[
					`src/lib/design-loading-proof/${design === 'classic' ? 'Classic' : 'Botanical'}Overlay.svelte`
				].file;
			assert(
				!requests.some((path) => path.endsWith(overlayFile)),
				'Unrevealed overlay stays deferred'
			);
			assert.equal(await page.locator(`style#${styleIds[design][2]}`).count(), 0);
			await page.getByRole('link', { name: 'Open details' }).hover();
			await page.waitForTimeout(1500);
			const beforeNavigation = [...requests];
			await page.screenshot({ path: `${output}/${design}-${width}.png` });
			await page.keyboard.press('Tab');
			await page.getByRole('link', { name: 'Open details' }).focus();
			assert(
				await page
					.getByRole('link', { name: 'Open details' })
					.evaluate((el) => getComputedStyle(el).outlineStyle !== 'none')
			);
			const start = Date.now();
			await page.getByRole('link', { name: 'Open details' }).click();
			await page.getByRole('heading', { name: 'Job details' }).waitFor();
			const navigationMs = Date.now() - start;
			for (const id of styleIds[design].slice(0, 2))
				assert.equal(await page.locator(`style#${id}`).count(), 1);
			for (const id of styleIds[other]) assert.equal(await page.locator(`style#${id}`).count(), 0);
			assert.deepEqual(errors, []);
			for (const file of exclusive[other])
				if (requests.some((path) => path.endsWith(file)))
					violations.push(`${design}/${width}: inactive download ${file}`);
			const measurements = await page.evaluate(() => ({
				metrics: window.__proofMetrics,
				overflow: document.documentElement.scrollWidth > innerWidth,
				assets: performance
					.getEntriesByType('resource')
					.filter((entry) => /\.(css|js|woff2?)(\?|$)/.test(entry.name))
					.map((entry) => ({
						path: new URL(entry.name).pathname,
						encoded: entry.encodedBodySize,
						transfer: entry.transferSize
					}))
			}));
			assert(!measurements.overflow);
			assert(
				measurements.metrics.designs.every((seen) => seen === design),
				'Wrong-design DOM frame'
			);
			const ordinaryRequests = [...requests];
			const expected = {
				classic: { canvas: 'rgb(244, 246, 248)', accent: 'rgb(37, 99, 235)' },
				botanical: { canvas: 'rgb(245, 244, 239)', accent: 'rgb(40, 107, 73)' }
			};
			async function checkEffectiveStyles(applied) {
				await page.locator(`[data-proof-surface="${applied}"]`).waitFor();
				const actual = await page.locator('[data-proof-design]').evaluate((el) => ({
					canvas: getComputedStyle(el).backgroundColor,
					accent: getComputedStyle(el.querySelector('header')).borderBottomColor
				}));
				assert.deepEqual(actual, expected[applied]);
				const open = page.getByRole('button', { name: 'Open read-only example' });
				await open.focus(); // keyboard intent warms only this design's overlay
				await open.click();
				const overlay = page.locator(`[data-proof-overlay="${applied}"]`);
				await overlay.waitFor();
				assert.equal(
					await overlay.evaluate((el) => Boolean(el.closest('[data-proof-design]'))),
					false,
					'Portal is outside shell scope'
				);
				assert.equal(
					await overlay.evaluate((el) => getComputedStyle(el).borderTopColor),
					expected[applied].accent
				);
				assert(
					await page.getByRole('dialog').evaluate((el) => el.contains(document.activeElement))
				);
				await page.keyboard.press('Tab');
				assert(
					await page.getByRole('dialog').evaluate((el) => el.contains(document.activeElement))
				);
				await page.screenshot({ path: `${output}/${design}-${width}-${applied}-overlay.png` });
				await page.keyboard.press('Escape');
				await page.getByRole('dialog').waitFor({ state: 'hidden' });
				return actual;
			}
			const switches = [{ design, styles: await checkEffectiveStyles(design) }];
			for (const applied of [other, design, other, design]) {
				await page.getByRole('link', { name: 'Load other test presentation' }).click();
				switches.push({ design: applied, styles: await checkEffectiveStyles(applied) });
			}
			assert.equal(await context.cookies().then((cookies) => cookies.length), 0);
			assert.deepEqual(
				await page.evaluate(() => ({
					local: Object.keys(localStorage),
					session: Object.keys(sessionStorage)
				})),
				{ local: [], session: [] }
			);
			assert(
				!requests.some((path) => path.startsWith('/api/')),
				'Fixture cannot write public preferences or records'
			);
			assert.deepEqual(errors, []);
			await page.screenshot({ path: `${output}/${design}-${width}-switched.png` });
			await page.evaluate(() => (document.documentElement.style.fontSize = '200%'));
			assert(!(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)));
			await page.screenshot({ path: `${output}/${design}-${width}-enlarged.png` });
			results.push({
				ordinaryRequests,
				switches,
				explicitRequests: requests.slice(ordinaryRequests.length),
				design,
				width,
				navigationMs,
				beforeHover,
				beforeNavigation,
				requests,
				...measurements
			});
			await context.close();
		}
	}
	assert.equal((await fetch(`${origin}/demo/design-loading/unknown/overview`)).status, 404);
	await writeFile(
		`${output}/results.json`,
		JSON.stringify(
			{
				profile:
					'Chromium, 4x CPU, 150ms RTT, 1.6Mbps down, 750Kbps up; local adapter-node HTTP; one session',
				exclusive,
				isolated,
				styleIds,
				violations,
				results
			},
			null,
			2
		)
	);
	assert.deepEqual(violations, [], 'Selected-only delivery failed; see results.json');
	console.log(
		`PASS: selected SSR/CSR, ordinary/intent asset isolation, repeated-switch effective styles, portalled content, request-local selection, hydration, focus, overflow and text resizing at both widths. Evidence: ${output}`
	);
} finally {
	await browser.close();
}
