import { expect, test, type Page } from '@playwright/test';

/**
 * C1: the Business Management home. A test business is given a next step due three days ago; it shows first under
 * Overdue, and marking it Done from the home removes it. Runs against the real remote database on the test
 * business the Deals check uses, and always puts back the step it had before.
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const businessId = process.env.JAFAR_TEST_DEAL_LEAD_ID ?? '9762d6ac-4e05-49d0-9ca4-e1ba6157c4de';
const shots = process.env.E2E_SCREENSHOT_DIR;

function localDate(offsetDays: number) {
	const date = new Date();
	date.setDate(date.getDate() + offsetDays);
	const month = String(date.getMonth() + 1).padStart(2, '0');
	const day = String(date.getDate()).padStart(2, '0');
	return `${date.getFullYear()}-${month}-${day}`;
}

async function signIn(page: Page) {
	await page.goto('/jafar/login', { waitUntil: 'networkidle' });
	await page.getByLabel('Email').fill(ownerEmail ?? '');
	await page.getByLabel('Password').fill(ownerPassword ?? '');
	await page.getByRole('button', { name: /Sign in/ }).click();
	await page.waitForURL((url) => !url.pathname.endsWith('/login'));
}

async function setNextAction(page: Page, next: unknown) {
	const response = await page.request.patch(`/api/jafar/leads/${businessId}`, {
		data: { next_action: next }
	});
	expect(response.ok(), await response.text()).toBe(true);
}

test('an overdue step leads the home and Done removes it', async ({ browser }) => {
	test.skip(!ownerEmail || !ownerPassword, 'Set SUPER_ADMIN_* to run the home check.');
	test.setTimeout(120_000);
	const page = await (
		await browser.newContext({ viewport: { width: 1440, height: 1000 } })
	).newPage();
	await signIn(page);

	const before = await (await page.request.get(`/api/jafar/leads/${businessId}`)).json();
	const original = before.lead.next_action
		? { mode: 'set', text: before.lead.next_action, due_on: before.lead.next_action_due_on }
		: { mode: 'clear' };
	const step = `Chase the home check ${Date.now()}`;

	try {
		await setNextAction(page, { mode: 'set', text: step, due_on: localDate(-3) });
		await page.goto('/jafar');

		const overdue = page.getByRole('region', { name: /Overdue/ });
		await expect(overdue).toBeVisible();
		// Overdue is the first group, and the step is in it with how late it is.
		await expect(page.locator('.business-home__group').first()).toHaveClass(/--overdue/);
		const row = overdue.getByRole('listitem').filter({ hasText: step });
		await expect(row).toBeVisible();
		await expect(row.getByText('3 days late')).toBeVisible();
		await expect(page.getByRole('link', { name: /Leads to review/ })).toBeVisible();
		if (shots) await page.screenshot({ path: `${shots}/home-desktop.png`, fullPage: true });

		await row.getByRole('button', { name: /Done/ }).click();
		const dialog = page.getByRole('dialog', { name: 'Mark next action done' });
		await expect(dialog.getByText(step)).toBeVisible();
		await dialog.getByRole('button', { name: 'Mark done' }).click();
		// The dialog closes once the home has reloaded from the remote database, which can pass five seconds.
		await expect(dialog).toBeHidden({ timeout: 15_000 });
		await expect(page.getByText(step)).toHaveCount(0);

		await page.setViewportSize({ width: 390, height: 844 });
		if (shots) await page.screenshot({ path: `${shots}/home-phone.png`, fullPage: true });
	} finally {
		await setNextAction(page, original);
	}
});
