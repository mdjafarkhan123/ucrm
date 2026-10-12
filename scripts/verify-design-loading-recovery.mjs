import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';
// Private release-build recovery checks; no account or organization preference is written.
const origin = process.env.PROOF_ORIGIN ?? 'http://127.0.0.1:4175';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname));
const root = process.cwd();
const output = process.env.PROOF_OUTPUT ?? '/tmp/selected-design-proof';
await mkdir(output, { recursive: true });
const manifest = JSON.parse(
	await readFile(`${root}/.svelte-kit/output/client/.vite/manifest.json`)
);
const browser = await chromium.launch({ headless: true });
const results = [];
try {
	for (const design of ['classic', 'botanical'])
		for (const width of [1440, 390]) {
			const name = design === 'classic' ? 'Classic' : 'Botanical';
			const context = await browser.newContext({ viewport: { width, height: 900 } });
			const page = await context.newPage();
			const surface = manifest[`src/lib/design-loading-proof/${name}Surface.svelte`].file;
			const overlay = manifest[`src/lib/design-loading-proof/${name}Overlay.svelte`].file;
			await page.route(`**/${surface}`, (route) => route.abort());
			await page.goto(`${origin}/demo/design-loading/${design}/overview`);
			await page
				.getByRole('alert')
				.filter({ hasText: 'Could not load the proof surface' })
				.waitFor();
			assert.equal(
				await page.locator('[data-proof-design]').getAttribute('data-proof-design'),
				design
			);
			await page.screenshot({ path: `${output}/${design}-${width}-surface-error.png` });
			await page.unroute(`**/${surface}`);
			await page.reload();
			await page.locator(`[data-proof-surface=${design}]`).waitFor();
			await page.route(`**/${overlay}`, (route) => route.abort());
			await page.getByRole('button', { name: 'Open read-only example' }).click();
			await page.getByRole('alert').filter({ hasText: 'Could not load the example' }).waitFor();
			await page.screenshot({ path: `${output}/${design}-${width}-overlay-error.png` });
			await page.unroute(`**/${overlay}`);
			await page.getByRole('link', { name: 'Reload to retry' }).click();
			await page.locator(`[data-proof-surface=${design}]`).waitFor();
			await page.getByRole('button', { name: 'Open read-only example' }).click();
			await page.getByRole('dialog').waitFor();
			await page.keyboard.press('Escape');
			await page.getByRole('dialog').waitFor({ state: 'hidden' });
			assert.equal(
				await page.evaluate(() => document.activeElement?.textContent?.trim()),
				'Open read-only example'
			);
			results.push({
				design,
				width,
				surfaceFailure: 'kept shell; reload recovered',
				overlayFailure: 'kept page; explicit reload recovered',
				focusReturn: true
			});
			await context.close();
		}
	await writeFile(`${output}/failure-results.json`, JSON.stringify(results, null, 2) + '\n');
	console.log(
		'PASS: failed page/overlay loading preserves selected shell, recovery and modal focus return at both widths'
	);
} finally {
	await browser.close();
}
