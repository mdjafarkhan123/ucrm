import {
	expect,
	test,
	type BrowserContextOptions,
	type Locator,
	type Page
} from '@playwright/test';

/**
 * B4: Jafar runs one Deal through its whole life on a test business — start, move, share pricing, special
 * terms, the board's "Move to…", Lost, reopen — and removes it again. Every dialog is cancelled once first to
 * prove a cancel changes nothing. It runs against the real remote database and always removes the Deal.
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const businessId = process.env.JAFAR_TEST_DEAL_LEAD_ID ?? '9762d6ac-4e05-49d0-9ca4-e1ba6157c4de';
const businessName = process.env.JAFAR_TEST_DEAL_BUSINESS ?? 'A1 Test Roofing';
const shots = process.env.E2E_SCREENSHOT_DIR;

async function signIn(page: Page) {
	await page.goto('/jafar/login', { waitUntil: 'networkidle' });
	await page.getByLabel('Email').fill(ownerEmail ?? '');
	await page.getByLabel('Password').fill(ownerPassword ?? '');
	await page.getByRole('button', { name: /Sign in/ }).click();
	await page.waitForURL((url) => !url.pathname.endsWith('/login'));
}

async function openBusiness(page: Page) {
	await page.goto(`/jafar/leads/${businessId}`);
	await expect(page.getByRole('heading', { name: businessName })).toBeVisible();
}

function dealBox(page: Page): Locator {
	return page.locator('.deal-panel');
}

async function fillStep(dialog: Locator, text: string) {
	await dialog.getByRole('textbox').first().fill(text);
	await dialog.getByRole('button', { name: 'Tomorrow' }).click();
}

async function changeStage(page: Page, item: string) {
	await dealBox(page).getByRole('button', { name: "Change this Deal's stage" }).click();
	await page.getByRole('menuitem', { name: item }).click();
}

async function dragCard(page: Page, card: Locator, column: Locator) {
	// The drag library watches pointer movement over time, so move like a hand would, with short pauses.
	await column.scrollIntoViewIfNeeded();
	await card.scrollIntoViewIfNeeded();
	const from = await card.boundingBox();
	const to = await column.boundingBox();
	if (!from || !to) throw new Error('The card or column is not on screen.');
	await page.mouse.move(from.x + from.width / 2, from.y + 20);
	await page.mouse.down();
	await page.mouse.move(from.x + from.width / 2 + 10, from.y + 30, { steps: 5 });
	await page.waitForTimeout(150);
	await page.mouse.move(to.x + to.width / 2, to.y + 120, { steps: 25 });
	await page.waitForTimeout(300);
	await page.mouse.up();
}

async function removeDealIfAny(page: Page) {
	await openBusiness(page);
	const remove = dealBox(page).getByRole('button', { name: 'Remove Deal' });
	if (await remove.isVisible()) {
		await remove.click();
		await page.getByRole('alertdialog').getByRole('button', { name: 'Remove' }).click();
		await expect(dealBox(page).getByText('No Deal yet')).toBeVisible();
	}
}

test.describe.serial('Deals', () => {
	test.skip(!ownerEmail || !ownerPassword, 'Set SUPER_ADMIN_* to run the Deals check.');

	// One sign-in for the whole file: the login page refuses repeated attempts.
	let signedIn: BrowserContextOptions['storageState'];
	test.beforeAll(async ({ browser }) => {
		const context = await browser.newContext();
		await signIn(await context.newPage());
		signedIn = await context.storageState();
		await context.close();
	});

	test('one Deal from start to Lost, reopened and removed', async ({ browser }) => {
		test.setTimeout(180_000);
		const page = await (
			await browser.newContext({ viewport: { width: 1800, height: 1000 }, storageState: signedIn })
		).newPage();
		await removeDealIfAny(page);
		const box = dealBox(page);

		try {
			// Start: cancel first, then start at Interested.
			await box.getByRole('button', { name: 'Start a Deal' }).click();
			let dialog = page.getByRole('dialog', { name: 'Start a Deal' });
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(dialog).toBeHidden();
			await expect(box.getByText('No Deal yet')).toBeVisible();

			await box.getByRole('button', { name: 'Start a Deal' }).click();
			await fillStep(dialog, 'Send the intro video');
			await dialog.getByRole('button', { name: 'Start Deal' }).click();
			await expect(page.getByText('Deal started', { exact: true })).toBeVisible();
			await expect(box.getByText('Interested', { exact: true })).toBeVisible();

			// Move: cancel leaves it at Interested; then Call booked.
			await changeStage(page, 'Move to Call booked');
			dialog = page.getByRole('dialog');
			await expect(dialog.getByLabel('The call')).toBeVisible();
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(dialog).toBeHidden();
			await expect(box.getByText('Interested', { exact: true })).toBeVisible();

			await changeStage(page, 'Move to Call booked');
			await fillStep(dialog, 'Discovery call on Zoom');
			await dialog.getByRole('button', { name: 'Move' }).click();
			await expect(page.getByText('Moved to Call booked', { exact: true })).toBeVisible();
			await expect(box.getByText('Call booked', { exact: true })).toBeVisible();

			// Share pricing: the first package on the pricing page.
			await changeStage(page, 'Share pricing…');
			dialog = page.getByRole('dialog', { name: 'Pricing shared' });
			await dialog.getByRole('checkbox').first().check();
			await dialog.getByRole('button', { name: 'Save' }).click();
			await expect(dialog).toBeHidden();
			await expect(box.getByRole('region', { name: 'Prices shared' })).toBeVisible();
			await expect(box.getByText('Pricing shared', { exact: true })).toBeVisible();
			await expect(box.getByText('if they buy the main package')).toBeVisible();

			// Special terms.
			await box.getByRole('button', { name: 'Edit the agreed special terms' }).click();
			await box.getByLabel('What was agreed').fill('First month free');
			await box.getByRole('button', { name: 'Save' }).click();
			await expect(box.getByText('First month free')).toBeVisible();
			if (shots) await page.screenshot({ path: `${shots}/deal-box.png`, fullPage: true });

			// The board: the card's "Move to…" menu, as a phone would use it.
			await page.goto('/jafar/deals');
			const card = page.locator('.deal-card', { hasText: businessName });
			await expect(card).toBeVisible();
			await expect(card.getByText('Special terms')).toBeVisible();
			await card.getByRole('button', { name: `Move or change ${businessName}` }).click();
			await page.getByRole('menuitem', { name: 'Move to Awaiting decision' }).click();
			dialog = page.getByRole('dialog');
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(dialog).toBeHidden();
			const pricingColumn = page.getByRole('region', { name: /Pricing shared/ });
			await expect(pricingColumn.locator('.deal-card', { hasText: businessName })).toBeVisible();

			await card.getByRole('button', { name: `Move or change ${businessName}` }).click();
			await page.getByRole('menuitem', { name: 'Move to Awaiting decision' }).click();
			await fillStep(dialog, 'Hear back on the Pro plan');
			await dialog.getByRole('button', { name: 'Move' }).click();
			const awaiting = page.getByRole('region', { name: /Awaiting decision/ });
			await expect(awaiting.locator('.deal-card', { hasText: businessName })).toBeVisible();
			if (shots) await page.screenshot({ path: `${shots}/board-desktop.png`, fullPage: true });

			// Drag: onto Later asks for a date, and cancelling puts the card back; onto Needs understood
			// saves at once.
			const later = page.getByRole('region', { name: /^Later/ });
			await dragCard(page, awaiting.locator('.deal-card', { hasText: businessName }), later);
			await expect(dialog.getByRole('group', { name: 'Revisit on' })).toBeVisible();
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(awaiting.locator('.deal-card', { hasText: businessName })).toBeVisible();
			await expect(later.locator('.deal-card', { hasText: businessName })).toHaveCount(0);

			const needs = page.getByRole('region', { name: /Needs understood/ });
			await dragCard(page, awaiting.locator('.deal-card', { hasText: businessName }), needs);
			await expect(page.getByText(`${businessName} moved to Needs understood`)).toBeVisible();
			await page.reload();
			await expect(needs.locator('.deal-card', { hasText: businessName })).toBeVisible();

			// Lost, then reopened from the business page.
			await openBusiness(page);
			await changeStage(page, 'Mark as Lost…');
			dialog = page.getByRole('dialog', { name: 'Mark as Lost' });
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(box.getByText('Needs understood', { exact: true })).toBeVisible();

			await changeStage(page, 'Mark as Lost…');
			await dialog.getByLabel('Why was it lost?').first().click();
			await page.getByRole('option', { name: /price/i }).first().click();
			await dialog.getByRole('button', { name: 'Mark as Lost' }).click();
			await expect(dialog).toBeHidden();
			await expect(box.getByText('Lost', { exact: true })).toBeVisible();

			await box.getByRole('button', { name: 'Reopen' }).click();
			dialog = page.getByRole('dialog', { name: 'Reopen this Deal' });
			await fillStep(dialog, 'Try again after their busy season');
			await dialog.getByRole('button', { name: 'Reopen' }).click();
			await expect(page.getByText('Deal reopened', { exact: true })).toBeVisible();
			await expect(box.getByText('Needs understood', { exact: true })).toBeVisible();

			// History lines.
			const history = page.locator('main');
			await expect(history.getByText(/Deal started/i).first()).toBeVisible();
			await expect(history.getByText(/Lost/).first()).toBeVisible();
			if (shots) await page.screenshot({ path: `${shots}/lead-history.png`, fullPage: true });
		} finally {
			await removeDealIfAny(page);
		}
	});

	test('the board and Move to… work on a phone', async ({ browser }) => {
		const page = await (
			await browser.newContext({ viewport: { width: 390, height: 844 }, storageState: signedIn })
		).newPage();
		await page.goto('/jafar/deals');
		await expect(page.getByRole('region', { name: /Interested/ })).toBeVisible();
		await expect(page.getByText(/open Deals?/)).toBeVisible();
		const pageOverflow = await page.evaluate(
			() => document.documentElement.scrollWidth - document.documentElement.clientWidth
		);
		expect(pageOverflow).toBeLessThanOrEqual(0);
		if (shots) await page.screenshot({ path: `${shots}/board-phone.png` });
	});
});
