import { createClient } from '@supabase/supabase-js';
import { expect, test, type BrowserContextOptions, type Page } from '@playwright/test';

/**
 * B5: a Deal is Won only by a confirmed payment. On the test business, Jafar unlinks its paid Application, starts a
 * Deal (which offers no way to mark it Won by hand), and links the Application again: the Deal turns Won by itself,
 * the Client box appears with the account and its setup stage, and the business shows on the board's Won view and
 * under the Leads list's Clients. A Won Deal cannot be removed from the screen, so the test removes it with the
 * service key afterwards, leaving the Application linked as it found it.
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const businessId = process.env.JAFAR_TEST_DEAL_LEAD_ID ?? '9762d6ac-4e05-49d0-9ca4-e1ba6157c4de';
const businessName = process.env.JAFAR_TEST_DEAL_BUSINESS ?? 'A1 Test Roofing';
const shots = process.env.E2E_SCREENSHOT_DIR;

function database() {
	return createClient(supabaseUrl ?? '', serviceKey ?? '', {
		auth: { autoRefreshToken: false, persistSession: false }
	});
}

/** Hands setup back to Jafar and removes the test business's Deals. Its Application stays linked. */
async function resetBusiness() {
	const client = database();
	// Through the app's own call: it refuses (harmlessly) when the business has no Won Deal.
	const owner = await client.rpc('owner_business_set_setup_owner', {
		actor_email: ownerEmail ?? '',
		target_relationship_id: businessId,
		target_member_id: null as unknown as string
	});
	if (owner.error && owner.error.code !== '22023') throw owner.error;
	const deals = await client.from('platform_deals').delete().eq('relationship_id', businessId);
	if (deals.error) throw deals.error;
}

async function signIn(page: Page) {
	await page.goto('/jafar/login', { waitUntil: 'networkidle' });
	await page.getByLabel('Email').fill(ownerEmail ?? '');
	await page.getByLabel('Password').fill(ownerPassword ?? '');
	await page.getByRole('button', { name: /Sign in/ }).click();
	await page.waitForURL((url) => !url.pathname.endsWith('/login'));
}

async function openBusiness(page: Page) {
	await page.goto(`/jafar/leads/${businessId}`);
	await expect(page.getByRole('heading', { name: businessName, level: 1 })).toBeVisible();
}

test.describe.serial('Won and the Client box', () => {
	test.skip(
		!ownerEmail || !ownerPassword || !supabaseUrl || !serviceKey,
		'Set SUPER_ADMIN_* and the Supabase service key to run the Won check.'
	);

	let signedIn: BrowserContextOptions['storageState'];
	test.beforeAll(async ({ browser }) => {
		await resetBusiness();
		const context = await browser.newContext();
		await signIn(await context.newPage());
		signedIn = await context.storageState();
		await context.close();
	});

	test.afterAll(async () => {
		await resetBusiness();
	});

	test('a paid Application makes the Deal Won and the business a client', async ({ browser }) => {
		test.setTimeout(180_000);
		const page = await (
			await browser.newContext({ viewport: { width: 1600, height: 1000 }, storageState: signedIn })
		).newPage();
		await openBusiness(page);
		const deal = page.locator('.deal-panel');
		const applications = page
			.locator('.rail-card')
			.filter({ has: page.getByRole('heading', { name: /^Applications/ }) });

		// The paid Application is linked to start with; unlink it so a Deal can wait for payment.
		const unlink = page.getByRole('button', { name: /Unlink .* Application/ });
		if (await unlink.isVisible()) {
			await unlink.click();
			await page.getByRole('alertdialog').getByRole('button', { name: 'Unlink' }).click();
			await expect(unlink).toBeHidden();
		}
		await expect(page.locator('.client-panel')).toBeHidden();

		// Start a Deal. Nothing offers Won by hand.
		await deal.getByRole('button', { name: 'Start a Deal' }).click();
		const start = page.getByRole('dialog', { name: 'Start a Deal' });
		await start.getByRole('textbox').first().fill('Reply about the Starter package');
		await start.getByRole('button', { name: 'Tomorrow' }).click();
		await start.getByRole('button', { name: 'Start Deal' }).click();
		await expect(deal.getByText('Interested', { exact: true })).toBeVisible();
		await deal.getByRole('button', { name: "Change this Deal's stage" }).click();
		await expect(page.getByRole('menuitem', { name: /Won/ })).toHaveCount(0);
		await page.keyboard.press('Escape');

		// Link the paid Application again: the Deal is Won by itself.
		await applications.getByRole('button', { name: 'Link' }).click();
		const link = page.getByRole('dialog', { name: 'Link an Application' });
		await link.getByLabel('Search Applications').fill(businessName);
		await link
			.getByRole('listitem')
			.filter({ hasText: businessName })
			.getByRole('button', { name: 'Link' })
			.first()
			.click();
		await expect(link).toBeHidden();

		await expect(deal.getByText('Won', { exact: true })).toBeVisible();
		await expect(deal.getByText(/Payment confirmed/)).toBeVisible();
		await expect(deal.getByRole('button', { name: 'Remove Deal' })).toHaveCount(0);
		await expect(deal.getByRole('button', { name: "Change this Deal's stage" })).toHaveCount(0);
		await expect(deal.getByRole('button', { name: 'Start a new Deal' })).toBeVisible();
		await expect(page.locator('.lead-page__eyebrow')).toHaveText('Client');

		// The Client box: package, payment, account, setup stage, and Jafar looking after setup.
		const client = page.locator('.client-panel');
		await expect(client.getByRole('heading', { name: 'Client', exact: true })).toBeVisible();
		await expect(client.getByText('Starter Check')).toBeVisible();
		await expect(
			client.getByRole('region', { name: 'Payments' }).getByRole('listitem')
		).not.toHaveCount(0);
		await expect(client.getByRole('link', { name: 'Open setup' })).toBeVisible();
		await expect(client.getByText(/^Next: /)).toBeVisible();
		await expect(client.locator('.client-panel__owner')).toContainText('Jafar');

		// A paid Application stays with its business.
		await page.getByRole('button', { name: /Unlink .* Application/ }).click();
		await page.getByRole('alertdialog').getByRole('button', { name: 'Unlink' }).click();
		await expect(page.getByText(/stays linked to that business/)).toBeVisible();
		await page.getByRole('alertdialog').getByRole('button', { name: 'Cancel' }).click();

		// Only teammates with Onboarding access are offered; Sam is in Sales.
		await client.getByRole('button', { name: 'Change who looks after their setup' }).click();
		await expect(page.getByRole('menuitem', { name: 'Jafar (now)' })).toBeVisible();
		await expect(page.getByRole('menuitem', { name: /Sam Seller/ })).toHaveCount(0);
		await expect(
			page.getByRole('menuitem', { name: 'No teammate has Onboarding access' })
		).toBeVisible();
		await page.keyboard.press('Escape');

		// The history says so.
		await expect(page.getByText('Deal Won — payment confirmed')).toBeVisible();
		if (shots) await page.screenshot({ path: `${shots}/client-box.png`, fullPage: true });

		// The board keeps it behind "Won".
		await page.goto('/jafar/deals');
		await page.getByRole('button', { name: /^Won/ }).click();
		await expect(page.getByRole('heading', { name: 'Won Deals' })).toBeVisible();
		await expect(page.locator('.deal-card').filter({ hasText: businessName })).toContainText(
			'Starter Check paid'
		);
		if (shots) await page.screenshot({ path: `${shots}/won-deals.png`, fullPage: true });

		// The Leads list shows it under Clients.
		await page.goto('/jafar/leads?deal=clients');
		await expect(page.getByRole('link', { name: businessName })).toBeVisible();
	});

	test('the Client box fits a phone', async ({ browser }) => {
		const page = await (
			await browser.newContext({ viewport: { width: 390, height: 844 }, storageState: signedIn })
		).newPage();
		await openBusiness(page);
		const client = page.locator('.client-panel');
		await expect(client).toBeVisible();
		const overflow = await page.evaluate(
			() => document.documentElement.scrollWidth > document.documentElement.clientWidth
		);
		expect(overflow).toBe(false);
		if (shots) await client.screenshot({ path: `${shots}/client-box-phone.png` });
	});
});
