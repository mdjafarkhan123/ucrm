import { chromium } from 'playwright';

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1 });

for (const [name, url] of [
	['demo', 'http://localhost:5173/demo/jafar-prospects'],
	['live', 'http://localhost:5173/jafar/prospects']
]) {
	await page.goto(url, { waitUntil: 'networkidle' });
	await page.screenshot({ path: `tmp/prospects-${name}.png`, fullPage: true });
	console.log(`${name}: ${await page.title()} | ${await page.locator('body').innerText().then((text) => text.slice(0, 500).replace(/\s+/g, ' '))}`);
}

await browser.close();
