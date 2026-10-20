import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, mkdir } from 'node:fs/promises';

const origin = 'http://localhost:5191';
const out = process.argv[2];
const theme = process.argv[3] ?? 'light';
const only = process.argv[4];
const role = process.argv[5] ?? 'Contractor owner';
await mkdir(out, { recursive: true });
const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(new RegExp(`${role}: ` + '`([^`]+)` \\/\\s*`([^`]+)`'));

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
if (theme === 'dark') await page.emulateMedia({ colorScheme: 'dark' });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(`${origin}/login`);
await page.waitForLoadState('networkidle');
await page.locator('input[type=email]').fill(email);
await page.locator('input[type=password]').fill(password);
await page.locator('button[type=submit]').first().click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 });

const card = () =>
	page
		.locator('section.section-block.pricing-block--concept', {
			has: page.getByRole('heading', { name: 'Products and services', exact: true })
		})
		.first();
async function shot(name) {
	const c = card();
	await c.waitFor({ timeout: 30000 });
	await c.scrollIntoViewIfNeeded();
	await page.waitForTimeout(500);
	await c.screenshot({ path: `${out}/${name}-${theme}.png` });
	console.log('shot', name);
}
async function firstLink(list, prefix) {
	await page.goto(`${origin}/${list}`);
	const uuidLink = `a[href^="/${prefix}/"]`;
	await page.locator(uuidLink).first().waitFor({ timeout: 30000 });
	await page.waitForTimeout(1500);
	const hrefs = await page
		.locator(uuidLink)
		.evaluateAll((as) => as.map((a) => a.getAttribute('href')));
	const href = hrefs.find((h) => /\/[0-9a-f]{8}-[0-9a-f]{4}-/.test(h));
	return origin + href;
}
async function rewrite(pattern, edit) {
	await page.unrouteAll({ behavior: 'ignoreErrors' });
	if (!edit) return;
	await page.route(pattern, async (r) => {
		if (r.request().method() !== 'GET') return r.continue();
		const res = await r.fetch();
		const body = await res.json();
		edit(body);
		await r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
	});
}
const want = (n) => !only || only.split(',').includes(n);

// --- Job: real, empty, prices hidden ---------------------------------------------------------------
if (want('job')) {
	const jobUrl = await firstLink('jobs', 'jobs');
	const jobApi = jobUrl.replace(origin, `${origin}/api`);
	await rewrite(jobApi, null);
	await page.goto(jobUrl);
	await shot('job');
	await rewrite(jobApi, (b) => (b.lines = []));
	await page.goto(jobUrl);
	await shot('job-empty');
	await rewrite(jobApi, (b) => {
		b.can_see_price = false;
		b.lines = (b.lines ?? []).map((l) => ({
			...l,
			unit_price_minor: null,
			line_total_minor: null
		}));
	});
	await page.goto(jobUrl);
	await shot('job-crew');
	await rewrite(jobApi, null);
}

// --- Quote: groups, text, add-ons, locked ------------------------------------------------------------
if (want('quote')) {
	const quoteUrl = await firstLink('quotes', 'quotes');
	const quoteApi = quoteUrl.replace(origin, `${origin}/api`);
	const build = (b, locked) => {
		const t = b.lines?.[0];
		if (!t) return;
		const mk = (i, o) => ({
			...t,
			id: `00000000-0000-4000-8000-0000000000${10 + i}`,
			position: i,
			image_file_id: null,
			...o
		});
		b.lines = [
			mk(0, {
				line_kind: 'heading',
				name: 'Kitchen',
				description: null,
				selection_kind: 'required'
			}),
			mk(1, { line_kind: 'priced', selection_kind: 'required' }),
			mk(2, {
				line_kind: 'text',
				name: 'About the countertop',
				description: 'We template the countertop once the cabinets are in, so it is cut to fit.',
				selection_kind: 'required',
				image_file_id: null
			}),
			mk(3, {
				line_kind: 'heading',
				name: 'Extras you can add',
				description: null,
				selection_kind: 'required'
			}),
			mk(4, {
				line_kind: 'priced',
				name: 'Under-cabinet lights',
				description: 'Warm white strips under every wall cabinet',
				selection_kind: 'optional',
				is_recommended: true,
				category: 'product',
				image_file_id: null
			}),
			mk(5, {
				line_kind: 'priced',
				name: 'Soft-close drawer upgrade',
				description: 'Full-extension runners',
				selection_kind: 'optional',
				is_recommended: false,
				category: 'product',
				image_file_id: null
			})
		];
		if (locked && b.version) b.version.status = 'published';
	};
	await rewrite(quoteApi, (b) => build(b, true));
	await page.goto(quoteUrl);
	await shot('quote');
	await rewrite(quoteApi, null);
	await page.goto(quoteUrl);
	await shot('quote-real');
	// Line menu and the discard question, on the first quote that can be edited.
	await page.goto(`${origin}/quotes`);
	await page.waitForTimeout(2500);
	const quoteLinks = await page
		.locator('a[href^="/quotes/"]')
		.evaluateAll((as) =>
			[...new Set(as.map((a) => a.getAttribute('href')))]
				.filter((h) => /\/[0-9a-f]{8}-[0-9a-f]{4}-/.test(h))
				.slice(0, 15)
		);
	const pencil = page.getByRole('button', { name: 'Edit products and services' });
	let editable = false;
	for (const href of quoteLinks) {
		await page.goto(origin + href);
		await card()
			.waitFor({ timeout: 20000 })
			.catch(() => {});
		await page.waitForTimeout(800);
		if (await pencil.isVisible().catch(() => false)) {
			editable = true;
			break;
		}
	}
	if (editable) {
		await pencil.click();
		await page.getByRole('button', { name: 'Line actions' }).first().click();
		await page.waitForTimeout(400);
		const box = await card().boundingBox();
		await page.screenshot({
			path: `${out}/quote-menu-${theme}.png`,
			clip: { x: box.x, y: box.y, width: box.width, height: Math.min(box.height, 700) }
		});
		console.log('shot quote-menu');
		await page.keyboard.press('Escape');
		await page.locator('[id^="pricing-qty-"]').first().fill('7');
		await card().getByRole('button', { name: 'Cancel' }).click();
		const dialog = page.getByRole('alertdialog').or(page.getByRole('dialog')).last();
		await dialog.waitFor({ timeout: 5000 });
		await page.waitForTimeout(300);
		await dialog.screenshot({ path: `${out}/quote-discard-${theme}.png` });
		console.log('shot quote-discard');
		await page.getByRole('button', { name: 'Throw them away' }).click();
	} else console.log('quote not editable');
	await rewrite(quoteApi, null);
}

// --- Invoices: progress, service date on a line ------------------------------------------------------
if (want('invoice')) {
	await page.goto(`${origin}/invoices/e2171d67-d2d3-4a30-b26b-3899cbff0db8`);
	await shot('invoice-progress').catch((e) =>
		console.log('progress invoice not visible', e.message)
	);
	const ids = [
		'8b560f3e-e1f7-41cb-a316-8cf3c91f71af',
		'b326b539-797f-46ba-a4d2-fe115faf4d38',
		'cd5ad6f6-4285-40ec-8dd9-a6510b9298b6'
	];
	for (const id of ids) {
		await rewrite(`${origin}/api/invoices/${id}`, (body) => {
			body.lines = (body.lines ?? []).map((l) => ({ ...l, service_date: '2026-10-14' }));
		});
		await page.goto(`${origin}/invoices/${id}`);
		await card()
			.waitFor({ timeout: 20000 })
			.catch(() => {});
		await page.waitForTimeout(1000);
		const pencil = page.getByRole('button', { name: 'Edit products and services' });
		if (!(await pencil.isVisible().catch(() => false))) continue;
		await shot('invoice');
		await pencil.click();
		await page.locator('.pricing-card__date').first().waitFor({ timeout: 5000 });
		await shot('invoice-edit');
		break;
	}
	await rewrite('x', null);
}

// --- Request pricing: loading and couldn't load ------------------------------------------------------
if (want('request')) {
	const requestUrl = await firstLink('requests', 'requests');
	await page.unrouteAll({ behavior: 'ignoreErrors' });
	await page.route('**/api/requests/*/pricing', () => new Promise(() => {}));
	await page.goto(requestUrl);
	await page.waitForTimeout(1500);
	await shot('request-loading');
	await page.unrouteAll({ behavior: 'ignoreErrors' });
	await page.route('**/api/requests/*/pricing', (r) =>
		r.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"x"}' })
	);
	await page.goto(requestUrl);
	await page.getByText("Couldn't load the pricing").waitFor({ timeout: 40000 });
	await shot('request-error');
	await page.unrouteAll({ behavior: 'ignoreErrors' });
	await page.goto(requestUrl);
	await page.waitForTimeout(1500);
	await shot('request');
}

if (want('forms')) {
	for (const kind of ['quotes', 'requests', 'invoices', 'jobs']) {
		await page.goto(`${origin}/${kind}/new`);
		await page.waitForTimeout(2500);
		await shot(`new-${kind}`).catch((e) =>
			console.log('no block on', kind, e.message.split('\n')[0])
		);
		if (kind === 'quotes') {
			await page.setViewportSize({ width: 390, height: 844 });
			await shot('new-quotes-mobile');
			await card().getByRole('button', { name: 'Add a line item' }).click();
			await card().locator('[id^="pricing-name-"]').first().waitFor();
			await shot('new-quotes-line-mobile');
			await page.setViewportSize({ width: 1440, height: 1000 });
		}
	}
}

console.log('errors', JSON.stringify(errors));
await browser.close();
