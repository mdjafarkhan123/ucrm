const { chromium } = require('playwright');
const assert = require('node:assert/strict');
(async () => {
	const browser = await chromium.launch({ headless: true });
	const page = await browser.newPage();
	const errors = [];
	page.on('pageerror', (e) => {
		errors.push(e.message);
		console.log('ERROR', e.stack);
	});
	for (const width of [1440, 390]) {
		await page.setViewportSize({ width, height: 1000 });
		await page.goto('http://127.0.0.1:4187');
		for (const s of [
			'populated',
			'empty',
			'loading',
			'error',
			'editing',
			'closed',
			'recurring',
			'period',
			'asneeded',
			'restricted',
			'changed',
			'final',
			'long'
		]) {
			await page.selectOption('#scenario', s);
			assert.equal(
				await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
				false,
				`${width} ${s} overflow`
			);
			await page.screenshot({ path: `/tmp/job-${s}-${width}.png`, fullPage: true });
		}
		await page.selectOption('#scenario', 'populated');
		const selectors = await page
			.locator('#job-surface [data-action]')
			.evaluateAll((es) => [
				...new Set(es.filter((e) => e.offsetWidth > 0).map((e) => e.dataset.action))
			]);
		for (const action of selectors) {
			await page.selectOption('#scenario', 'populated');
			await page.locator(`#job-surface [data-action="${action}"]`).first().click();
			assert.ok(
				(await page.locator('#preview').evaluate((e) => e.open)) ||
					(await page.locator('.edit-bar').isVisible()) ||
					['pin-note', 'download-file'].includes(action),
				`No response: ${action}`
			);
			if (await page.locator('#preview').evaluate((e) => e.open))
				await page.keyboard.press('Escape');
		}
		await page.selectOption('#scenario', 'populated');
		await page.getByRole('button', { name: 'Edit job', exact: true }).click();
		assert.equal(await page.locator('#save-draft').isEnabled(), false);
		await page.locator('#title-draft').fill('Updated sample title');
		assert.equal(await page.locator('#save-draft').isEnabled(), true);
		await page.locator('#save-draft').click();
		assert.equal(await page.locator('#job-title').innerText(), 'Updated sample title');
		await page.reload();
		assert.equal(await page.locator('#job-title').innerText(), 'Backyard transformation');
		if (width === 390) {
			await page.getByRole('button', { name: 'Open navigation' }).click();
			assert.equal(
				await page.getByRole('link', { name: 'Pipeline', exact: true }).isVisible(),
				true
			);
			await page.keyboard.press('Escape');
		}
		await page.locator('[data-action=signature]').click();
		await page.locator('#preview-outcome').selectOption('error');
		await page.locator('#preview [data-action=submit]').click();
		assert.equal(await page.locator('#preview-error').isVisible(), true);
		assert.equal(await page.locator('#preview input').first().inputValue(), 'Emma Wilson');
		await page.screenshot({ path: `/tmp/job-dialog-${width}.png` });
		await page.keyboard.press('Escape');
		console.log(
			`${width}: 13 scenarios, ${selectors.length} actions, draft save/reset, dialog checks passed`
		);
	}
	assert.deepEqual(errors, []);
	console.log('No browser errors');
	await browser.close();
})();
