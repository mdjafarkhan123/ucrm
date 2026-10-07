import { expect, test, type Page } from '@playwright/test';

/**
 * D2 (ADR 0008): Jafar narrows a test teammate's access in the Manage access panel, the teammate's direct
 * request is then refused by the server, and the access is put back. It changes only the test teammate's
 * access, against the real remote database, and always restores it.
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const teammateEmail = process.env.JAFAR_TEST_TEAMMATE_EMAIL;
const teammatePassword = process.env.JAFAR_TEST_TEAMMATE_PASSWORD;
const teammateName = process.env.JAFAR_TEST_TEAMMATE_NAME ?? 'Sam Seller';

async function signIn(page: Page, email: string, password: string) {
	await page.goto('/jafar/login');
	await page.getByLabel('Email').fill(email);
	await page.getByLabel('Password').fill(password);
	await page.getByRole('button', { name: /Sign in/ }).click();
	await expect(page).not.toHaveURL(/\/jafar\/login$/);
}

async function setLeads(page: Page, level: 'View' | 'Change') {
	await page.goto('/jafar/settings/team');
	await page.getByRole('button', { name: `Manage access for ${teammateName}` }).click();
	const panel = page.getByRole('dialog', { name: 'Manage access' });
	await expect(panel.getByRole('radiogroup', { name: 'Leads access' })).toBeVisible();
	await panel.getByRole('radiogroup', { name: 'Leads access' }).getByText(level).click();
	await panel.getByRole('button', { name: 'Save access' }).click();
	await expect(panel).toBeHidden();
	await expect(page.getByText(`Access saved for ${teammateName}.`)).toBeVisible();
}

test.describe.serial('teammate access', () => {
	test.skip(
		!ownerEmail || !ownerPassword || !teammateEmail || !teammatePassword,
		'Set SUPER_ADMIN_* and JAFAR_TEST_TEAMMATE_* to run the teammate access check.'
	);

	test('a narrowed area refuses the teammate’s direct change and shows in history', async ({
		browser
	}) => {
		const owner = await (await browser.newContext()).newPage();
		await signIn(owner, ownerEmail ?? '', ownerPassword ?? '');
		await setLeads(owner, 'View');

		const teammate = await (await browser.newContext()).newPage();
		try {
			await signIn(teammate, teammateEmail ?? '', teammatePassword ?? '');
			// Looking still works; a change is refused before the route runs, even with an empty body.
			expect((await teammate.request.get('/api/jafar/leads')).status()).toBe(200);
			expect((await teammate.request.post('/api/jafar/leads', { data: {} })).status()).toBe(403);
		} finally {
			await setLeads(owner, 'Change');
		}

		await owner.getByRole('button', { name: `Manage access for ${teammateName}` }).click();
		const panel = owner.getByRole('dialog', { name: 'Manage access' });
		await expect(panel.getByText('Leads: view only → can change')).toBeVisible();
		await expect(panel.getByText('Leads: can change → view only')).toBeVisible();
		await expect(panel.getByRole('button', { name: 'Save access' })).toBeDisabled();
	});

	test('the panel fits a phone screen', async ({ browser }) => {
		const page = await (
			await browser.newContext({ viewport: { width: 390, height: 844 } })
		).newPage();
		await signIn(page, ownerEmail ?? '', ownerPassword ?? '');
		await page.goto('/jafar/settings/team');
		await page.getByRole('button', { name: `Manage access for ${teammateName}` }).click();
		const panel = page.getByRole('dialog', { name: 'Manage access' });
		await expect(panel.getByRole('radiogroup', { name: 'Leads access' })).toBeVisible();
		const overflow = await panel.evaluate((element) => element.scrollWidth - element.clientWidth);
		expect(overflow).toBeLessThanOrEqual(0);
		if (process.env.E2E_SCREENSHOT_DIR) {
			await page.screenshot({ path: `${process.env.E2E_SCREENSHOT_DIR}/access-phone.png` });
			await panel.getByText('History').scrollIntoViewIfNeeded();
			await page.screenshot({ path: `${process.env.E2E_SCREENSHOT_DIR}/access-phone-2.png` });
		}
	});
});
