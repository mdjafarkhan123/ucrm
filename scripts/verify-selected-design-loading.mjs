/** Run after npm run build and a localhost Node server with DESIGN_LOADING_PROOF=1. */
import assert from 'node:assert/strict';
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
		['Shell', 'Surface'].flatMap((surface) =>
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
				['Shell', 'Surface'].map(async (surface) => {
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
			for (const id of styleIds[design]) assert.equal(await page.locator(`style#${id}`).count(), 1);
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
			results.push({
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
		`PASS: selected SSR shell, CSR surface, idle/hover/navigation isolation, hydration, focus and overflow at both widths. Evidence: ${output}`
	);
} finally {
	await browser.close();
}
