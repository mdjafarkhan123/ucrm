import { expect, test, type Page } from '@playwright/test';

/**
 * Multi-industry foundation B3: one Application, reviewed by Uplift before payment. A business that fits no
 * listed type applies without a package; Uplift cannot ask it to pay, holds it with a message the business
 * reads on its status page, then confirms it as a Contractor business, chooses a Contractor package and asks
 * for payment. Runs against the real remote database; the Application is closed as Not proceeding at the end.
 *
 * Turnstile cannot be solved by a test browser, so run it with the check switched off for this server:
 *   PUBLIC_TURNSTILE_SITE_KEY= TURNSTILE_SECRET_KEY= npx playwright test src/routes/get-started/application-qualification.e2e.ts
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const shots = process.env.E2E_SCREENSHOT_DIR;
const businessName = `B3 Test Groomers ${Date.now()}`;

async function shot(page: Page, name: string) {
	if (shots) await page.screenshot({ path: `${shots}/${name}.png`, fullPage: true });
}

async function choose(page: Page, label: string, option: string) {
	await page.getByRole('button', { name: label, exact: true }).click();
	await page.getByRole('option', { name: option, exact: true }).click();
}

async function pick(page: Page, label: string, typed: string, option: RegExp) {
	await page.getByRole('combobox', { name: label, exact: true }).fill(typed);
	await page.getByRole('option', { name: option }).first().click();
}

test.skip(
	!ownerEmail || !ownerPassword || Boolean(process.env.PUBLIC_TURNSTILE_SITE_KEY),
	'Needs the owner login and the spam check switched off.'
);

test('an Application is held, confirmed and only then asked to pay', async ({ page }) => {
	test.setTimeout(240_000);
	await page.setViewportSize({ width: 1440, height: 1000 });

	// The buyer: a listed type shows Contractor packages; "Something else" skips the package.
	await page.goto('/get-started', { waitUntil: 'networkidle' });
	await page.getByLabel('Business name').fill(businessName);
	await choose(page, 'What kind of business do you run?', 'Roofing');
	await page.getByLabel('What work does your business do?').fill('Mobile dog grooming at homes.');
	await pick(page, 'Country', 'United States', /^United States/);
	await pick(page, 'City', 'Austin', /^Austin/);
	await pick(page, 'Time zone', 'Chicago', /Chicago/);
	await shot(page, '01-business-step');
	await page.getByRole('button', { name: /Continue/ }).click();
	await expect(page.getByRole('heading', { name: 'Choose a package' })).toBeVisible();
	await shot(page, '02-package-roofing');

	await page
		.getByRole('button', { name: /Business/ })
		.first()
		.click();
	await choose(page, 'What kind of business do you run?', 'Something else or not sure');
	await page.getByRole('button', { name: /Continue/ }).click();
	await expect(page.getByText('Uplift will recommend your package')).toBeVisible();
	await shot(page, '03-package-something-else');
	await page.getByRole('button', { name: /Continue/ }).click();

	await page.getByLabel('Contact name').fill('Bea Tester');
	await page.getByLabel('Contact email').fill(`b3-${Date.now()}@example.com`);
	await page.getByLabel('Contact phone').fill('+1 512 555 0142');
	await page.getByRole('button', { name: /Continue/ }).click();
	await page.getByText(/I agree to the privacy policy/).click();
	await shot(page, '04-review');
	await page.getByRole('button', { name: 'Submit application' }).click();
	await page.waitForURL(/\/get-started\/received\?app=/);
	const statusUrl = page.url();
	const applicationId = new URL(statusUrl).searchParams.get('app');
	await expect(page.getByText(/email you the package we recommend/)).toBeVisible();
	await shot(page, '05-status-recommend');

	// Uplift: cannot mark it reviewed before deciding; holds it with a message for the business.
	await page.goto('/jafar/login', { waitUntil: 'networkidle' });
	await page.getByLabel('Email').fill(ownerEmail ?? '');
	await page.getByLabel('Password').fill(ownerPassword ?? '');
	await page.getByRole('button', { name: /Sign in/ }).click();
	await page.waitForURL((url) => !url.pathname.endsWith('/login'));
	await page.goto(`/jafar/prospects?application=${applicationId}`, { waitUntil: 'networkidle' });
	const kind = page.getByRole('region', { name: 'Kind of business' });
	await expect(kind.getByText('Something else or not sure')).toBeVisible();
	await page.getByRole('button', { name: 'Mark reviewed' }).click();
	await expect(page.getByRole('alert')).toContainText(/kind of business/i);
	await shot(page, '06-uplift-refused');

	await kind.getByRole('button', { name: 'Hold for a missing fact' }).click();
	await kind
		.getByLabel('What you are checking (the business sees this)')
		.fill('We need to know whether you groom at homes or in a shop.');
	await kind.getByLabel('Private reason').fill('Grooming is not a Contractor trade yet.');
	await shot(page, '07-uplift-hold-form');
	await kind.getByRole('button', { name: 'Hold application' }).click();
	await expect(kind.getByText('Held while checking')).toBeVisible();

	await page.goto(statusUrl, { waitUntil: 'networkidle' });
	await expect(page.getByText(/groom at homes or in a shop/)).toBeVisible();
	await shot(page, '08-status-held');

	// Uplift confirms it as a Contractor business, chooses a package, then marks it reviewed.
	await page.goto(`/jafar/prospects?application=${applicationId}`, { waitUntil: 'networkidle' });
	await kind.getByRole('button', { name: 'Confirm kind of business' }).click();
	await choose(page, 'Industry experience', 'Contractor');
	await choose(page, 'Business type', 'Handyman services');
	await kind.getByLabel('The work you reviewed').fill('Home repairs and small fixes.');
	await kind.getByLabel('Private reason').fill('They confirmed they mostly do handyman work.');
	await shot(page, '09-uplift-confirm-form');
	await kind.getByRole('button', { name: 'Confirm', exact: true }).click();
	await expect(kind.getByText(/Confirmed as Contractor · Handyman services/).first()).toBeVisible();

	await page.getByRole('button', { name: 'Change package' }).click();
	const packageSelect = page.getByRole('button', { name: 'Package', exact: true });
	await packageSelect.click();
	await page.getByRole('option').first().click();
	await page.getByLabel('Private reason for this change').fill('Recommended after review.');
	await page.getByRole('button', { name: 'Change package' }).last().click();
	await expect(page.getByLabel('Private reason for this change')).toBeHidden();
	await page.getByRole('button', { name: 'Mark reviewed' }).click();
	await expect(page.getByRole('button', { name: 'Confirm payment' })).toBeVisible();
	await shot(page, '10-uplift-awaiting-payment');

	// Clean up: close the test Application.
	await page.getByRole('button', { name: 'Mark not proceeding' }).click();
	await page.getByRole('button', { name: 'Confirm not proceeding' }).click();
	await expect(page.getByRole('button', { name: 'Confirm payment' })).toBeHidden();
});
