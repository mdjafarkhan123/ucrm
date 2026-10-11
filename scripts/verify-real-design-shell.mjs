/** Verify the private real shell against Classic; both local release servers use the same build. */
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';
const output = process.env.PROOF_OUTPUT ?? '/tmp/real-design-shell';
await mkdir(output, { recursive: true });
const origins = { classic: 'http://127.0.0.1:4175', botanical: 'http://127.0.0.1:4176' };
const login = await readFile('Login.md', 'utf8');
const credentials = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);
assert(credentials, 'Existing owner test login missing');
const manifest = JSON.parse(
	await readFile('.svelte-kit/output/client/.vite/manifest.json', 'utf8')
);
const frameEntries = Object.fromEntries(
	['classic', 'botanical'].map((design) => {
		const name = `${design[0].toUpperCase() + design.slice(1)}Frame`;
		const found = Object.entries(manifest).find(
			([key, entry]) => key.endsWith(`/${name}.svelte`) || entry.name === name
		);
		assert(found, `Missing frame entry ${name}`);
		return [design, found];
	})
);
const exclusiveFiles = Object.fromEntries(
	Object.entries(frameEntries).map(([design, [, entry]]) => [
		design,
		[entry.file, ...(entry.css ?? []), ...(entry.assets ?? [])]
	])
);
const styleIds = Object.fromEntries(
	await Promise.all(
		Object.entries(frameEntries).map(async ([design, [, entry]]) => {
			const code = await readFile(`.svelte-kit/output/client/${entry.file}`, 'utf8');
			const ids = [...code.matchAll(/hash:["'`](svelte-[\w-]+)["'`]/g)].map((m) => m[1]);
			assert(ids.length, `No injected styles for ${design}`);
			return [design, ids];
		})
	)
);
const browser = await chromium.launch({ headless: true });
const results = [];
try {
	const auth = await browser.newContext();
	const authPage = await auth.newPage();
	await authPage.goto(`${origins.classic}/login`);
	await authPage.locator('input[type=email]').fill(credentials[1]);
	await authPage.locator('input[type=password]').fill(credentials[2]);
	await authPage.getByRole('button', { name: /sign in/i }).click();
	await authPage.waitForURL('**/dashboard', { timeout: 60000 });
	const storageState = await auth.storageState();
	await auth.close();
	for (const design of ['classic', 'botanical'])
		for (const width of [1440, 390]) {
			const context = await browser.newContext({ storageState, viewport: { width, height: 900 } });
			const page = await context.newPage();
			await page.addInitScript(() => {
				window.__shellDesigns = [];
				new MutationObserver(() => {
					const shell = document.querySelector('[data-presentation]');
					if (shell) window.__shellDesigns.push(shell.getAttribute('data-presentation'));
				}).observe(document, {
					childList: true,
					subtree: true,
					attributes: true,
					attributeFilter: ['data-presentation']
				});
			});
			const errors = [],
				requests = [];
			page.on('pageerror', (e) => errors.push(e.message));
			page.on('console', (m) => {
				if (/hydration/i.test(m.text())) errors.push(m.text());
			});
			page.on('request', (r) => requests.push(new URL(r.url()).pathname));
			const response = await page.goto(`${origins[design]}/dashboard`);
			assert.equal(response.status(), 200);
			const html = await response.text();

			assert(
				new RegExp(`data-presentation=["']?${design}`).test(html),
				'Selected frame must be SSR'
			);
			assert(
				styleIds[design].some((id) => html.includes(`<style id="${id}"`)),
				'Selected CSS must be SSR'
			);
			const other = design === 'classic' ? 'botanical' : 'classic';
			for (const file of exclusiveFiles[other])
				assert(!html.includes(file), `Inactive SSR asset ${file}`);
			for (const id of styleIds[other])
				assert(!html.includes(`<style id="${id}"`), `Inactive SSR style ${id}`);
			await page.waitForTimeout(15000);
			assert.equal(
				await page.locator('[data-presentation]').getAttribute('data-presentation'),
				design
			);
			await page.screenshot({ path: `${output}/${design}-${width}.png` });
			const navigation = page.locator(design === 'classic' ? '.sidebar' : '.botanical-nav').first();
			let menuFocusReturned = true;
			if (width === 390) {
				const opener = page.getByRole('button', { name: 'Open navigation' });
				await opener.click();
				const dialog = page.getByRole('dialog', { name: 'Navigation', exact: true });
				await dialog.waitFor();
				await page.screenshot({ path: `${output}/${design}-${width}-navigation.png` });
				await page.keyboard.press('Tab');
				assert(
					await dialog.evaluate((el) => el.contains(document.activeElement)),
					'Phone focus must stay in drawer'
				);
				await page.keyboard.press('Escape');
				await dialog.waitFor({ state: 'hidden' });
				menuFocusReturned = await opener.evaluate((el) => el === document.activeElement);
				assert(menuFocusReturned, 'Phone focus must return to opener');
				await opener.click();
				await page
					.getByRole('dialog', { name: 'Navigation', exact: true })
					.getByRole('link', { name: 'Clients', exact: true })
					.click();
			} else {
				await navigation.getByRole('button', { name: 'Collapse navigation' }).click();
				await page.screenshot({ path: `${output}/${design}-${width}-collapsed.png` });
				await navigation.getByRole('button', { name: 'Expand navigation' }).click();
				await navigation.getByRole('link', { name: 'Clients', exact: true }).hover();
				await navigation.getByRole('link', { name: 'Clients', exact: true }).click();
			}
			await page.waitForURL('**/clients');
			await page.waitForTimeout(1000);
			await page.getByRole('button', { name: /Account menu for/ }).click();
			await page.getByText('Password and security', { exact: true }).waitFor();
			await page.screenshot({ path: `${output}/${design}-${width}-account.png` });
			await page.getByRole('menuitem', { name: 'Profile photo' }).click();
			await page.getByRole('dialog', { name: 'Profile photo', exact: true }).waitFor();
			await page.keyboard.press('Escape');
			await page.keyboard.press('Control+k');
			await page.getByRole('dialog', { name: 'Search', exact: true }).waitFor();
			await page.keyboard.press('Escape');
			await page.getByRole('button', { name: /Notifications,/ }).click();
			await page.getByRole('heading', { name: 'Notifications', exact: true }).waitFor();
			await page.keyboard.press('Escape');
			if (design === 'classic') {
				await page.getByRole('button', { name: 'Switch to dark mode' }).click();
				await page.screenshot({ path: `${output}/${design}-${width}-dark.png` });
				await page.getByRole('button', { name: 'Switch to light mode' }).click();
			} else
				assert(
					await page.getByRole('button', { name: 'Switch to dark mode' }).isVisible(),
					'Personal appearance control remains reachable'
				);
			await page.goto(`${origins[design]}/clients/new`);
			const bar = page.locator('.sticky-action-bar');
			await bar.waitFor();
			const geometry = await page.evaluate(() => {
				const bar = document.querySelector('.sticky-action-bar').getBoundingClientRect();
				const shell = document.querySelector('[data-presentation]');
				const css = getComputedStyle(shell);
				return {
					left: bar.left,
					right: innerWidth - bar.right,
					expectedLeft: parseFloat(css.getPropertyValue('--shell-content-left')),
					width: document.documentElement.scrollWidth,
					viewport: innerWidth
				};
			});
			assert.equal(geometry.width, geometry.viewport, 'No document overflow');
			assert(geometry.left >= 0 && geometry.right >= 0, 'Save actions stay on screen');
			await page.screenshot({ path: `${output}/${design}-${width}-save-bar.png` });
			if (width === 1440) {
				const leftBefore = (await bar.boundingBox()).x;
				await page.getByRole('button', { name: 'Collapse navigation' }).click();
				await page.waitForTimeout(400);
				const leftAfter = (await bar.boundingBox()).x;
				assert(leftAfter < leftBefore, 'Pinned bar follows sidebar collapse');
			}
			// Text resizing exercises the real header/navigation without changing personal appearance settings.
			await page.evaluate(() => (document.documentElement.style.fontSize = '200%'));
			await page.waitForTimeout(400);
			await page.screenshot({ path: `${output}/${design}-${width}-text-200.png` });
			if (design === 'botanical' && width === 1440) {
				const clipping = await page
					.locator('.botanical-shell__sidebar')
					.evaluate((el) => ({ scroll: el.scrollWidth, client: el.clientWidth }));
				assert(clipping.scroll <= clipping.client, 'Enlarged collapsed sidebar must fit icons');
				await page.getByRole('button', { name: 'Expand navigation' }).click();
				await page.waitForTimeout(400);
				await page
					.locator('.botanical-nav__business strong')
					.evaluate(
						(el) =>
							(el.textContent = 'Northwestern Coastal Restoration and Property Maintenance Company')
					);
				await page.screenshot({ path: `${output}/${design}-${width}-long-name.png` });
			}

			const inactiveRequests = requests.filter((path) =>
				exclusiveFiles[other].some((file) => path.endsWith(file))
			);
			assert.deepEqual(inactiveRequests, [], 'Inactive frame requests after warming/navigation');
			assert.deepEqual(errors, [], 'Browser/hydration errors');
			assert(
				(await page.evaluate(() => window.__shellDesigns)).every((value) => value === design),
				'No wrong-presentation DOM observed'
			);
			results.push({
				design,
				width,
				menuFocusReturned,
				geometry,
				errors,
				inactiveRequests,
				requests
			});
			await context.close();
		}
	const fieldCredentials = login.match(/Field member: `([^`]+)` \/\s*`([^`]+)`/);
	assert(fieldCredentials, 'Existing field-member test login missing');
	const fieldAuth = await browser.newContext();
	const fieldPage = await fieldAuth.newPage();
	await fieldPage.goto(`${origins.classic}/login`);
	await fieldPage.locator('input[type=email]').fill(fieldCredentials[1]);
	await fieldPage.locator('input[type=password]').fill(fieldCredentials[2]);
	await fieldPage.getByRole('button', { name: /sign in/i }).click();
	await fieldPage.waitForURL('**/dashboard', { timeout: 60000 });
	const fieldState = await fieldAuth.storageState();
	await fieldAuth.close();
	const fieldMenus = {};
	for (const design of ['classic', 'botanical']) {
		const context = await browser.newContext({
			storageState: fieldState,
			viewport: { width: 1440, height: 900 }
		});
		const page = await context.newPage();
		await page.goto(`${origins[design]}/dashboard`);
		const nav = page.locator(design === 'classic' ? '.sidebar' : '.botanical-nav');
		fieldMenus[design] = await nav
			.locator('nav')
			.getByRole('link')
			.evaluateAll((links) =>
				links.map((link) => ({
					href: link.getAttribute('href'),
					label: link.getAttribute('aria-label') ?? link.textContent.trim()
				}))
			);
		await page.screenshot({ path: `${output}/${design}-field-member.png` });
		await context.close();
	}
	assert.deepEqual(
		fieldMenus.botanical,
		fieldMenus.classic,
		'Presentation must preserve staff navigation permissions'
	);

	// Check the existing Control Room caller retains Classic even on the Botanical-preview server.
	// The test-only Uplift teammate, not Jafar's own login, so a changed personal password never breaks this check.
	const ownerCredentials = login.match(/`\/jafar` teammate[^`]*`([^`]+)` \/\s*`([^`]+)`/);
	assert(ownerCredentials, 'Control Room teammate test login missing');
	const ownerContext = await browser.newContext({ viewport: { width: 1440, height: 900 } });
	const ownerPage = await ownerContext.newPage();
	await ownerPage.goto(`${origins.botanical}/jafar`);
	await ownerPage.locator('input[type=email]').fill(ownerCredentials[1]);
	await ownerPage.locator('input[type=password]').fill(ownerCredentials[2]);
	await ownerPage.getByRole('button', { name: /sign in/i }).click();
	await ownerPage.waitForURL('**/jafar', { timeout: 60000 });
	assert.equal(
		await ownerPage.locator('[data-presentation]').getAttribute('data-presentation'),
		'classic'
	);
	await ownerPage.screenshot({ path: `${output}/control-room-classic.png` });
	await ownerPage.setViewportSize({ width: 390, height: 900 });
	await ownerPage.getByRole('button', { name: 'Open navigation' }).click();
	await ownerPage.getByRole('dialog', { name: 'Navigation', exact: true }).waitFor();
	await ownerPage.screenshot({ path: `${output}/control-room-classic-phone.png` });
	await ownerContext.close();

	await writeFile(
		`${output}/results.json`,
		JSON.stringify(
			{
				scope:
					'Real shell, existing owner account, SSR, idle/hover warming, client navigation, account menu, drawer, pinned create-form bar; no records saved',
				frameEntries,
				styleIds,
				fieldMenus,
				results
			},
			null,
			2
		)
	);
	console.log(`PASS: real shells at both widths; evidence ${output}`);
} finally {
	await browser.close();
}
