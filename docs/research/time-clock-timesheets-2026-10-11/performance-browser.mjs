// Browser performance check for Timesheets (performance-review § Svelte and browser delivery). Usage:
//   node docs/research/time-clock-timesheets-2026-10-11/performance-browser.mjs <mock-summary.json> [runs]
// Run against a production build (`npm run build && npm run preview -- --port 5181`). The summary API is
// mocked with a 15-person week and a person's entries with a busy week (84 entries), so the numbers are the
// page's own: delivery, rendering and the row-open interaction. Database time is measured separately in
// performance-proof.sql. Phone: 390x844, CPU slowed 4x, network ~4G (150 ms, 1.6 Mbps down).
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile } from 'node:fs/promises';

const origin = process.env.ORIGIN ?? 'http://localhost:5181';
const [summaryPath, runsArg] = process.argv.slice(2);
const runs = Number(runsArg ?? 3);
const summary = JSON.parse(await readFile(summaryPath, 'utf8'));
const target = summary.people[2];

// A busy week for one person: 12 entries a day, 7 days.
const entries = [];
for (const day of ['04', '05', '06', '07', '08', '09', '10']) {
	for (let slot = 0; slot < 12; slot++) {
		const start = new Date(`2026-10-${day}T13:00:00Z`).getTime() + slot * 40 * 60000;
		entries.push({
			id: `e-${day}-${slot}`,
			kind: slot % 3 === 2 ? 'general' : 'job',
			is_running: false,
			source: slot % 4 === 0 ? 'manual' : 'timer',
			started_at: new Date(start).toISOString(),
			ended_at: new Date(start + 35 * 60000).toISOString(),
			started_on: `2026-10-${day}`,
			minutes: 35,
			notes: slot === 5 ? 'Customer asked us to come back Thursday for the side fence' : null,
			overlaps: false,
			long_running: false,
			job:
				slot % 3 === 2
					? null
					: {
							id: `10000000-0000-4000-8000-${String(1000 + slot).padStart(12, '0')}`,
							number: 1000 + slot,
							visible: true,
							title: 'Spring cleanup and full mulch refresh for the back garden beds',
							client_name: 'Alejandra Montgomery-Fitzgerald'
						},
			visit_date: slot % 3 === 2 ? null : `2026-10-${day}`
		});
	}
}
const entriesBody = JSON.stringify({
	user_id: target.user_id,
	from: summary.from,
	to: summary.to,
	timezone: summary.timezone,
	server_now: summary.server_now,
	entries,
	truncated: false
});

const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);

// Records when the rows and the opened entries appear, LCP, CLS, long tasks and slow interactions.
const observe = () => {
	const marks = { rows: null, entries: null, lcp: 0, cls: 0, longTasks: 0, longTaskMs: 0, events: [] };
	window.__perf = marks;
	new PerformanceObserver((list) => {
		for (const entry of list.getEntries()) marks.lcp = entry.startTime;
	}).observe({ type: 'largest-contentful-paint', buffered: true });
	new PerformanceObserver((list) => {
		for (const entry of list.getEntries()) if (!entry.hadRecentInput) marks.cls += entry.value;
	}).observe({ type: 'layout-shift', buffered: true });
	new PerformanceObserver((list) => {
		for (const entry of list.getEntries()) {
			marks.longTasks += 1;
			marks.longTaskMs += entry.duration;
		}
	}).observe({ type: 'longtask', buffered: true });
	new PerformanceObserver((list) => {
		for (const entry of list.getEntries())
			if (entry.interactionId) marks.events.push({ name: entry.name, duration: entry.duration });
	}).observe({ type: 'event', durationThreshold: 16, buffered: true });
	new MutationObserver(() => {
		if (marks.rows === null && document.querySelectorAll('.timesheet-person').length >= 15)
			marks.rows = performance.now();
		if (marks.entries === null && document.querySelectorAll('.timesheet-entry').length >= 84)
			marks.entries = performance.now();
	}).observe(document, { childList: true, subtree: true });
};

async function slowDown(page) {
	const cdp = await page.context().newCDPSession(page);
	await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
	await cdp.send('Network.enable');
	await cdp.send('Network.emulateNetworkConditions', {
		offline: false,
		latency: 150,
		downloadThroughput: (1.6 * 1024 * 1024) / 8,
		uploadThroughput: (750 * 1024) / 8
	});
}

async function mockApi(page) {
	await page.route('**/api/time-clock/timesheets?*', (route) =>
		route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(summary) })
	);
	await page.route('**/api/time-clock/timesheets/entries?*', (route) =>
		route.fulfill({ status: 200, contentType: 'application/json', body: entriesBody })
	);
}

const median = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const round = (value) => (value === null ? null : Math.round(value));

const browser = await chromium.launch({ headless: true });
try {
	const setup = await browser.newContext();
	const signIn = await setup.newPage();
	await signIn.goto(`${origin}/login`);
	await signIn.waitForLoadState('networkidle');
	await signIn.locator('input[type=email]').fill(email);
	await signIn.locator('input[type=password]').fill(password);
	await signIn.getByRole('button', { name: /sign in/i }).click();
	await signIn.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 60000 });
	const storageState = await setup.storageState();
	await setup.close();

	const cold = [];
	for (let run = 0; run < runs; run++) {
		const context = await browser.newContext({
			storageState,
			viewport: { width: 390, height: 844 },
			deviceScaleFactor: 3,
			isMobile: true,
			hasTouch: true
		});
		const page = await context.newPage();
		const errors = [];
		page.on('pageerror', (error) => errors.push(error.message));
		await context.addInitScript(observe);
		await mockApi(page);
		await slowDown(page);
		await page.goto(`${origin}/timesheets?date=${summary.from}`);
		await page.waitForFunction(() => window.__perf?.rows !== null, null, { timeout: 60000 });
		await page.waitForLoadState('networkidle');
		await page.waitForTimeout(500);

		// Open a row: the entries are fetched (mocked) and rendered beneath it.
		const before = await page.evaluate(() => performance.now());
		await page.locator('.timesheet-person__toggle').nth(2).click();
		await page.waitForFunction(() => window.__perf?.entries !== null, null, { timeout: 30000 });
		await page.waitForTimeout(300);

		const result = await page.evaluate((clickAt) => {
			const resources = performance.getEntriesByType('resource');
			const sum = (filter) =>
				resources.filter(filter).reduce((total, entry) => total + (entry.transferSize || 0), 0);
			const navigation = performance.getEntriesByType('navigation')[0];
			const marks = window.__perf;
			return {
				ttfb: navigation.responseStart,
				rows: marks.rows,
				lcp: marks.lcp,
				cls: marks.cls,
				longTasks: marks.longTasks,
				longTaskMs: marks.longTaskMs,
				openToEntries: marks.entries - clickAt,
				slowestInteraction: Math.max(0, ...marks.events.map((event) => event.duration)),
				requests: resources.length + 1,
				scriptBytes: sum((entry) => entry.initiatorType === 'script' || entry.name.endsWith('.js')),
				cssBytes: sum((entry) => entry.name.endsWith('.css')),
				htmlBytes: navigation.transferSize,
				domNodes: document.getElementsByTagName('*').length
			};
		}, before);
		cold.push(result);
		if (errors.length) console.log('page errors:', errors);
		await context.close();
	}

	const keys = Object.keys(cold[0]);
	const report = Object.fromEntries(
		keys.map((key) => [key, key === 'cls' ? median(cold.map((r) => r[key])).toFixed(3) : round(median(cold.map((r) => r[key])))])
	);
	console.log(`Phone, cold load of /timesheets, median of ${runs} runs (ms and bytes):`);
	console.table(report);
	console.log('every run:', JSON.stringify(cold.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, k === 'cls' ? Number(v.toFixed(3)) : round(v)])))));
} finally {
	await browser.close();
}
