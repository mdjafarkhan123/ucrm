import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { mkdir, writeFile } from 'node:fs/promises';

const url = 'http://127.0.0.1:4192/src/routes/%28app%29/settings/appearance-prototype.html';
const out = '/tmp/ucrm-a2a-proof';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (error) => errors.push(error.message));
page.on('console', (message) => message.type() === 'error' && errors.push(message.text()));
await page.goto(url, { waitUntil: 'networkidle' });

async function shot(name) {
	for (const [width, height] of [
		[1440, 1000],
		[390, 844]
	]) {
		await page.setViewportSize({ width, height });
		await page.locator('.crm').screenshot({ path: `${out}/${name}-${width}.png` });
		const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
		if (overflow > 1) errors.push(`${name}-${width}: ${overflow}px horizontal overflow`);
	}
}
async function reset() {
	await page.locator('[data-action="reset"]').click();
}

await shot('owner-default');
await page.setViewportSize({ width: 1440, height: 1000 });
await page.locator('[name="theme"][value="botanical"]').check();
await page.locator('#organization [data-action="preview"]').click();
await page.waitForTimeout(20);
if (
	(await page.evaluate(() => document.activeElement?.getAttribute('aria-label'))) !==
	'Close preview'
)
	errors.push('preview focus');
await shot('preview');
await page.keyboard.press('Escape');
await page.waitForTimeout(20);
if ((await page.evaluate(() => document.activeElement?.dataset.action)) !== 'preview')
	errors.push('preview focus return');
await page.locator('#save').click();
await shot('saving');
await page.locator('.free [data-action="save-success"]').click();
await shot('saved-notice');

await reset();
await page.locator('[name="theme"][value="botanical"]').check();
await page.locator('#save').click();
await page.locator('.free [data-action="save-conflict"]').click();
await shot('conflict');
await page.locator('#save').click();
await page.locator('.free [data-action="save-fail"]').click();
await shot('save-failed');
await page.locator('#save').click();
await page.locator('.free [data-action="save-uncertain"]').click();
await shot('save-uncertain');

await reset();
await page.locator('.free [data-action="remote"]').click();
await page.locator('.free [data-action="draft"]').click();
await page.locator('#messages [data-action="apply"]').click();
await shot('apply-blocked');
await page.locator('.free [data-action="safe"]').click();
await page.locator('#messages [data-action="apply"]').click();
await page.locator('.free [data-action="prepare-fail"]').click();
await shot('prepare-failed');

await reset();
await page.locator('.free [data-action="staff"]').click();
await page.locator('[name="mode"][value="dark"]').check();
if (await page.locator('#organization').isVisible())
	errors.push('staff organization controls visible');
await shot('staff');

await reset();
await page.locator('.free [data-action="fresh-fail"]').click();
await shot('fresh-failed');
await page.locator('#recovery [data-action="fresh-retry"]').click();
await page.locator('.free [data-action="fresh-invalid"]').click();
await shot('fresh-invalid');

await page.reload({ waitUntil: 'networkidle' });
await page.setViewportSize({ width: 390, height: 844 });
await page.addStyleTag({ content: ':root{font-size:200%!important}' });
const enlargedOverflow = await page.evaluate(
	() => document.documentElement.scrollWidth - innerWidth
);
await page.locator('.crm').screenshot({ path: `${out}/enlarged-390.png` });
if (enlargedOverflow > 1) errors.push(`enlarged: ${enlargedOverflow}px horizontal overflow`);

await page.reload({ waitUntil: 'networkidle' });
const axe = await new AxeBuilder({ page }).analyze();
for (const violation of axe.violations.filter((item) =>
	['critical', 'serious'].includes(item.impact)
))
	errors.push(`axe ${violation.id}: ${violation.nodes.length}`);
const result = {
	errors,
	axe: axe.violations.map(({ id, impact, nodes }) => ({
		id,
		impact,
		nodes: nodes.map((node) => node.target)
	}))
};
await writeFile(`${out}/results.json`, JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
await browser.close();
if (errors.length) process.exitCode = 1;
