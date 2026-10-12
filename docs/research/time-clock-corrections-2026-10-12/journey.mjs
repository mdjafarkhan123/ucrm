// Part 5 live journey on the dev app, signed in as the contractor owner (Login.md): add hours for the field
// member on a Job, edit them, read the edit history, delete them; then clock the member in, move the running
// timer's start back, and clock them out at a set time. Screenshots at the given width land here.
// Usage: node docs/research/time-clock-corrections-2026-10-12/journey.mjs [--width=1440] [--state=dir]
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, writeFile, access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const origin = process.env.ORIGIN ?? 'http://localhost:5173';
const args = process.argv.slice(2);
const flag = (key, fallback) =>
	args.find((arg) => arg.startsWith(`--${key}=`))?.split('=')[1] ?? fallback;
const width = Number(flag('width', '1440'));
const stateDir = flag('state', here);
const statePath = join(stateDir, 'state-owner.json');

const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const [, email, password] = login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/);
const [, fieldEmail] = login.match(/Field member: `([^`]+)`/);

const browser = await chromium.launch({ headless: true });
const errors = [];
let step = 0;

async function shot(page, name) {
	step += 1;
	await page.waitForTimeout(400);
	const file = join(here, `${step}-${name}-${width}.png`);
	await page.screenshot({ path: file, fullPage: false });
	console.log('shot', file);
}

function clock(instant, timezone) {
	const parts = new Intl.DateTimeFormat('en-US', {
		timeZone: timezone,
		hour: 'numeric',
		minute: '2-digit',
		hour12: true
	}).format(new Date(instant));
	return parts.replace(' ', ' ');
}

try {
	try {
		await access(statePath);
	} catch {
		const context = await browser.newContext();
		const page = await context.newPage();
		await page.goto(`${origin}/login`);
		await page.waitForLoadState('networkidle');
		await page.waitForTimeout(1500);
		await page.locator('input[type=email]').fill(email);
		await page.locator('input[type=password]').fill(password);
		await page.getByRole('button', { name: /sign in/i }).click();
		await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 60000 });
		await writeFile(statePath, JSON.stringify(await context.storageState()));
		await context.close();
	}

	const context = await browser.newContext({
		storageState: statePath,
		viewport: { width, height: width < 640 ? 844 : 900 },
		deviceScaleFactor: 1
	});
	const page = await context.newPage();
	page.on('pageerror', (error) => errors.push(error.message));
	page.on('console', (message) => {
		if (message.type() === 'error') errors.push(message.text());
	});

	// The business's today and clock, and who the field member is on this team.
	await page.goto(`${origin}/timesheets`);
	const summary = await page.evaluate(async () =>
		(await fetch('/api/time-clock/timesheets?span=day')).json()
	);
	const timezone = summary.timezone;
	const yesterday = new Date(Date.parse(`${summary.today}T12:00:00Z`) - 86_400_000)
		.toISOString()
		.slice(0, 10);
	console.log('business', timezone, 'today', summary.today, 'now', summary.server_now);
	const field = summary.people.find((person) => !person.is_me && person.status === 'active' && /jafar/i.test(person.name ?? ''));
	if (!field) throw new Error(`No field member found for ${fieldEmail}: ${summary.people.map((p) => p.name)}`);
	// Clocked in already (a run that stopped part-way): go straight to the clock out.
	const resume = Boolean(field.running);
	if (resume) step = 11;
	console.log('field member', field.name, field.user_id);

	if (!resume) {
	// A rerun starts clean: proof entries left by an earlier run are deleted through the same route.
	const leftovers = await page.evaluate(
		async ({ userId, from, to }) => {
			const params = new URLSearchParams({ user_id: userId, from, to });
			const { entries } = await (await fetch(`/api/time-clock/timesheets/entries?${params}`)).json();
			const stale = entries.filter((entry) => entry.notes?.includes('proof entry'));
			for (const entry of stale)
				await fetch(`/api/time-clock/timesheets/entries/${entry.id}`, { method: 'DELETE' });
			return stale.length;
		},
			{ userId: field.user_id, from: yesterday, to: summary.today }
		);
	console.log('removed leftovers', leftovers);

	// 1. Add an entry for the field member, yesterday 8:00–12:00 on a Job.
	await page.goto(`${origin}/timesheets?view=day&date=${yesterday}`);
	await page.waitForLoadState('networkidle');
	await shot(page, 'day-with-add');
	await page.getByRole('button', { name: 'Add entry', exact: true }).click();
	const dialog = page.getByRole('dialog');
	await dialog.waitFor();
	await page.locator('#entry-person').click();
	await page.getByRole('option', { name: field.name }).click();
	await page.locator('#entry-job').click();
	await page.waitForTimeout(800);
	await page.getByRole('option').first().click();
	await page.locator('#entry-start').fill('8:00 AM');
	await page.locator('#entry-start').press('Tab');
	await page.locator('#entry-end').fill('12:00 PM');
	await page.locator('#entry-end').press('Tab');
	await page.locator('#entry-notes').fill('Fence posts — proof entry');
	await shot(page, 'add-filled');
	await dialog.getByRole('button', { name: 'Add hours' }).click();
	await dialog.waitFor({ state: 'detached' });
	await page.waitForLoadState('networkidle');

	// 2. Open the member's row and see the entry.
	const row = page.locator('.timesheet-person', { hasText: field.name });
	const toggle = row.locator('.timesheet-person__toggle');
	if ((await toggle.getAttribute('aria-expanded')) === 'false') await toggle.click();
	await page.waitForLoadState('networkidle');
	const entry = page.locator('.timesheet-entry', { hasText: 'Fence posts — proof entry' });
	await entry.waitFor();
	await shot(page, 'added');

	// 3. Edit: start 7:30 instead of 8:00.
	await entry.getByRole('button', { name: 'Entry actions' }).click();
	await page.getByRole('menuitem', { name: 'Edit' }).click();
	await dialog.waitFor();
	await page.locator('#entry-start').fill('7:30 AM');
	await page.locator('#entry-start').press('Tab');
	await shot(page, 'edit-filled');
	await dialog.getByRole('button', { name: 'Save changes' }).click();
	await dialog.waitFor({ state: 'detached' });
	await page.waitForLoadState('networkidle');
	await entry.filter({ hasText: '4h 30m' }).waitFor();
	await shot(page, 'edited');

	// 4. History: added, then changed.
	await entry.getByRole('button', { name: 'Entry actions' }).click();
	await page.getByRole('menuitem', { name: 'History' }).click();
	await dialog.waitFor();
	await dialog.getByText('Changed by you').waitFor();
	await shot(page, 'history');
	console.log('history:', (await dialog.innerText()).replace(/\n+/g, ' | '));
	await dialog.getByText('Close', { exact: true }).click();
	await dialog.waitFor({ state: 'detached' });

	// 5. Delete.
	await entry.getByRole('button', { name: 'Entry actions' }).click();
	await page.getByRole('menuitem', { name: 'Delete' }).click();
	const confirm = page.getByRole('alertdialog');
	await confirm.waitFor();
	await shot(page, 'delete-confirm');
	await confirm.getByRole('button', { name: 'Delete entry' }).click();
	await confirm.waitFor({ state: 'detached' });
	await entry.waitFor({ state: 'detached' });
	await shot(page, 'deleted');

	// 6. Manager clock in, today.
	await page.goto(`${origin}/timesheets?view=day`);
	await page.waitForLoadState('networkidle');
	const dayRow = page.locator('.timesheet-person', { hasText: field.name });
	await dayRow.getByRole('button', { name: `Actions for ${field.name}` }).click();
	await shot(page, 'person-menu');
	await page.getByRole('menuitem', { name: 'Clock in' }).click();
	await dayRow.locator('.timesheet-person__running').waitFor();
	await shot(page, 'clocked-in');

	// 7. The running timer's start moves back 90 minutes (only start and notes can change while it runs).
	const now = Date.parse(summary.server_now) + (Date.now() - Date.parse(summary.server_now));
	const startAt = now - 90 * 60_000;
	const todayToggle = dayRow.locator('.timesheet-person__toggle');
	if ((await todayToggle.getAttribute('aria-expanded')) === 'false') await todayToggle.click();
	const running = page.locator('.timesheet-entry--running').first();
	await running.waitFor();
	await running.getByRole('button', { name: 'Entry actions' }).click();
	await page.getByRole('menuitem', { name: 'Edit start or notes' }).click();
	await dialog.waitFor();
	await page.locator('#entry-start').fill(clock(startAt, timezone));
	await page.locator('#entry-start').press('Tab');
	await shot(page, 'running-edit');
	await dialog.getByRole('button', { name: 'Save changes' }).click();
	await dialog.waitFor({ state: 'detached' });
	await page.waitForLoadState('networkidle');

	}

	// 8. Clock out at a set time, 30 minutes ago: one hour of General recorded.
	if (resume) {
		await page.goto(`${origin}/timesheets?view=day`);
		await page.waitForLoadState('networkidle');
	}
	const endAt = Date.now() - 30 * 60_000;
	const dialog = page.getByRole('dialog');
	const todayRow = page.locator('.timesheet-person', { hasText: field.name });
	await todayRow.getByRole('button', { name: `Actions for ${field.name}` }).click();
	await page.getByRole('menuitem', { name: /Clock out|Stop timer|Set end time/ }).click();
	await dialog.waitFor();
	await dialog.getByText('At a set time', { exact: true }).click();
	await page.locator('#stop-time').fill(clock(endAt, timezone));
	await page.locator('#stop-time').press('Tab');
	await shot(page, 'stop-at-set-time');
	await dialog.getByRole('button', { name: 'Clock out' }).click();
	await dialog.waitFor({ state: 'detached' });
	await page.waitForLoadState('networkidle');
	await todayRow.locator('.timesheet-person__running').waitFor({ state: 'detached' });
	await shot(page, 'clocked-out');
	const rowToggle = todayRow.locator('.timesheet-person__toggle');
	if ((await rowToggle.getAttribute('aria-expanded')) === 'false') await rowToggle.click();
	console.log('entries after clock out:', (await page.locator(`#timesheet-entries-${field.user_id}`).innerText()).replace(/\n+/g, ' | '));
} finally {
	if (errors.length) console.log('PAGE ERRORS:\n' + errors.join('\n'));
	await browser.close();
}
