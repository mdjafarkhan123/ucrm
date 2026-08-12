import { expect, test } from '@playwright/test';

/**
 * Read-only smoke coverage for the platform-owner `/jafar` area. Deliberately does not
 * click any action that creates an organization, sends an email, or changes lifecycle/
 * payment state — this suite runs against the real remote database, not a disposable
 * test database, so mutating actions are left to manual verification instead.
 */

const protectedPaths = ['/jafar', '/jafar/prospects', '/jafar/packages', '/jafar/organizations'];

test.describe('platform owner area access control', () => {
	for (const path of protectedPaths) {
		test(`redirects an unauthenticated visitor from ${path} to the login page`, async ({
			page
		}) => {
			await page.goto(path);
			await expect(page).toHaveURL(/\/jafar\/login$/);
		});
	}

	test('redirects an unauthenticated visitor away from an organization detail page', async ({
		page
	}) => {
		await page.goto('/jafar/organizations/00000000-0000-0000-0000-000000000000');
		await expect(page).toHaveURL(/\/jafar\/login$/);
	});
});

test.describe('platform owner login page', () => {
	test('shows the sign-in form', async ({ page }) => {
		await page.goto('/jafar/login');
		await expect(page.getByRole('heading', { name: 'Sign in to the control room' })).toBeVisible();
		await expect(page.getByLabel('Email')).toBeVisible();
		await expect(page.getByLabel('Password')).toBeVisible();
		await expect(page.getByRole('button', { name: /Sign in/ })).toBeVisible();
	});

	test('shows an error and does not sign in with incorrect credentials', async ({ page }) => {
		await page.goto('/jafar/login');
		await page.getByLabel('Email').fill('not-the-real-owner@example.com');
		await page.getByLabel('Password').fill('definitely-the-wrong-password');
		await page.getByRole('button', { name: /Sign in/ }).click();

		await expect(page.getByRole('alert')).toBeVisible();
		await expect(page).toHaveURL(/\/jafar\/login$/);
	});
});

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;

test.describe('platform owner admin pages (authenticated, read-only)', () => {
	test.skip(
		!ownerEmail || !ownerPassword,
		'Set SUPER_ADMIN_EMAIL and SUPER_ADMIN_PASSWORD in .env to run authenticated checks.'
	);

	test.beforeEach(async ({ page }) => {
		await page.goto('/jafar/login');
		await page.getByLabel('Email').fill(ownerEmail ?? '');
		await page.getByLabel('Password').fill(ownerPassword ?? '');
		await page.getByRole('button', { name: /Sign in/ }).click();
		await expect(page).toHaveURL(/\/jafar$/);
	});

	test('dashboard shows the real owner overview', async ({ page }) => {
		await expect(page.getByRole('heading', { name: 'Good morning, Jafar' })).toBeVisible();
	});

	test('prospects page loads the review list', async ({ page }) => {
		await page.goto('/jafar/prospects');
		await expect(page.getByRole('main').getByRole('heading', { name: 'Prospects' })).toBeVisible();
	});

	test('packages page loads the package catalog', async ({ page }) => {
		await page.goto('/jafar/packages');
		await expect(page.getByRole('main').getByRole('heading', { name: 'Packages' })).toBeVisible();
	});

	test('organizations list loads and links into a real organization detail page', async ({
		page
	}) => {
		await page.goto('/jafar/organizations');
		await expect(
			page.getByRole('main').getByRole('heading', { name: 'Organizations' })
		).toBeVisible();

		const firstRowLink = page.locator('table tbody a').first();
		await expect(firstRowLink).toBeVisible();

		await firstRowLink.click();
		await expect(page.getByRole('main').locator('h1')).toBeVisible();
		await expect(page.getByText('Commercial access').first()).toBeVisible();
	});

	test('logs out and returns to a signed-out state', async ({ page }) => {
		await page.request.delete('/api/jafar/session');
		await page.goto('/jafar');
		await expect(page).toHaveURL(/\/jafar\/login$/);
	});
});
