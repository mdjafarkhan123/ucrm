// Part 7 live journey on the branch dev app (Login.md logins). As the contractor owner: open Approve on the
// Field member's day, approve it, see "Approved" on Timesheets and Job #20 Labor, and open an approved entry's
// edit notice. As the Field member (given "Record and change their own hours" for this run only, so the lock
// rather than the timers-only rung is what refuses them): approved entries offer History only, today's
// unapproved entry can still be edited, and both /api routes refuse changing approved hours.
// Usage: node docs/research/time-clock-weekly-approval-2026-10-12/journey.mjs --as=owner|field [--width=1440]
//        [--approve] [--running] [--cutoff=2026-10-11]
// --approve clicks Approve (no undo). --running clocks the Field member in first to show the running warning,
// then clocks them out within a minute (discarded as an accidental tap).
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, writeFile, access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const origin = process.env.ORIGIN ?? 'http://localhost:5174';
const args = process.argv.slice(2);
const flag = (key, fallback) =>
	args.find((arg) => arg.startsWith(`--${key}=`))?.split('=')[1] ?? fallback;
const role = flag('as', 'owner');
const width = Number(flag('width', '1440'));
const cutoff = flag('cutoff', '2026-10-11');
const statePath = join(here, `state-${role}.json`);
const jobId = '698bbe09-ce9f-4b92-87b2-57dfcd4f9b1e';
const fieldId = '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb';

const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const pattern = role === 'owner' ? /Contractor owner: `([^`]+)` \/\s*`([^`]+)`/ : /Field member: `([^`]+)` \/\s*`([^`]+)`/;
const [, email, password] = login.match(pattern);

const browser = await chromium.launch({ headless: true });
const results = [];
const errors = [];

async function shot(page, name) {
	await page.waitForTimeout(500);
	const file = join(here, `${role}-${name}-${width}.png`);
	await page.screenshot({ path: file, fullPage: false });
	console.log('shot', file);
}

function check(name, passed, detail = '') {
	results.push({ name, passed, detail });
	console.log(passed ? 'PASS' : 'FAIL', name, detail);
}

async function openRow(page, name) {
	const row = page.locator('button[aria-expanded]', { hasText: name }).first();
	await row.waitFor({ timeout: 30000 });
	if ((await row.getAttribute('aria-expanded')) !== 'true') await row.click();
	await page.getByRole('button', { name: 'Entry actions' }).first().waitFor({ timeout: 15000 });
}

async function menuLabels(page, index) {
	await page.getByRole('button', { name: 'Entry actions' }).nth(index).click();
	const items = page.getByRole('menuitem');
	await items.first().waitFor({ timeout: 5000 });
	const labels = (await items.allInnerTexts()).map((label) => label.trim());
	await page.keyboard.press('Escape');
	return labels;
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
		viewport: { width, height: width < 800 ? 844 : 900 },
		deviceScaleFactor: width < 800 ? 2 : 1
	});
	const page = await context.newPage();
	page.on('pageerror', (error) => errors.push(error.message));
	page.on('console', (message) => {
		if (message.type() === 'error') errors.push(message.text());
	});

	if (role === 'owner') {
		const dayUrl = (day) => `${origin}/timesheets?view=day&date=${day}`;
		await page.goto(dayUrl(cutoff));
		await page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
		const approveButton = page.getByRole('button', { name: 'Approve', exact: true });
		await approveButton.waitFor({ timeout: 30000 });
		await page.waitForTimeout(1500);

		if (args.includes('--running')) {
			const clockIn = await page.request.post(
				`${origin}/api/time-clock/timesheets/running/${fieldId}/clock-in`,
				{ data: {} }
			);
			check('Owner clocks the Field member in', clockIn.ok(), `${clockIn.status()}`);
			const today = (await (await page.request.get(`${origin}/api/time-clock/timesheets?span=day`)).json())
				.today;
			await page.goto(dayUrl(today));
			await approveButton.waitFor({ timeout: 30000 });
			await page.waitForTimeout(1500);
		}

		// Pointing at Approve reads what is waiting, so the dialog usually opens with it.
		const preview = page.waitForRequest((request) => request.url().includes('/timesheets/approval'), {
			timeout: 5000
		});
		await approveButton.hover();
		check('Hovering Approve reads what is waiting', Boolean(await preview.catch(() => null)));
		await approveButton.click();
		const dialog = page.getByRole('dialog');
		await dialog.getByText(/Waiting for approval/).waitFor({ timeout: 15000 });
		await page.waitForTimeout(1500);
		const dialogText = await dialog.innerText();

		if (args.includes('--running')) {
			check(
				'Running timer is listed as not approved',
				/Still running, so not approved/.test(dialogText),
				dialogText.split('\n').filter((line) => /running|since/i.test(line)).join(' | ')
			);
			await shot(page, 'approve-running');
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			const out = await page.request.post(
				`${origin}/api/time-clock/timesheets/running/${fieldId}/stop`,
				{ data: {} }
			);
			check('Owner clocks the Field member out again', out.ok(), `${out.status()}`);
		} else if (args.includes('--approve')) {
			check('Dialog lists the Field member', /Field Tester|Jafar/i.test(dialogText), dialogText.replace(/\n+/g, ' | ').slice(0, 300));
			await shot(page, 'approve-dialog');
			await dialog.getByRole('button', { name: /^Approve \d/ }).click();
			await dialog.waitFor({ state: 'detached', timeout: 15000 });
			const toast = await page.getByText(/^Approved \d+ entr/).first().innerText();
			check('Approving shows what was approved', true, toast);
			await page.waitForTimeout(1500);
			await shot(page, 'approved');
		} else {
			check(
				'Nothing waiting once approved',
				/Nothing is waiting/.test(dialogText),
				dialogText.replace(/\n+/g, ' | ').slice(0, 200)
			);
			await shot(page, 'nothing-waiting');
			await dialog.getByRole('button', { name: 'Cancel' }).click();
		}

		if (!args.includes('--running')) {
			// The approved row and entries, and the notice on editing one.
			await page.goto(dayUrl(cutoff));
			await approveButton.waitFor({ timeout: 30000 });
			await page.waitForTimeout(1500);
			const badge = page.locator('.timesheet-person__marks', { hasText: 'Approved' });
			check('Person row shows Approved', (await badge.count()) === 1);
			await openRow(page, 'Field Tester');
			check(
				'Entries show Approved',
				(await page.locator('.timesheet-entry__approved').count()) > 0,
				`${await page.locator('.timesheet-entry__approved').count()} approved`
			);
			await shot(page, 'approved-entries');
			const labels = await menuLabels(page, 0);
			check('Manager can still edit an approved entry', labels.includes('Edit'), labels.join(', '));
			await page.getByRole('button', { name: 'Entry actions' }).first().click();
			await page.getByRole('menuitem', { name: 'Edit' }).click();
			const edit = page.getByRole('dialog');
			await edit.getByText(/These hours are approved/).waitFor({ timeout: 10000 });
			check('Edit shows the approved notice', true);
			await shot(page, 'edit-approved');
			await edit.getByRole('button', { name: 'Cancel' }).click();

			// Job #20 Labor marks the approved hours.
			await page.goto(`${origin}/jobs/${jobId}`);
			await page.getByRole('heading', { name: /labor/i }).first().waitFor({ timeout: 30000 });
			await page.waitForTimeout(2000);
			const labor = page.locator('section', { has: page.getByRole('heading', { name: /labor/i }) }).first();
			await labor.scrollIntoViewIfNeeded();
			const laborText = await labor.innerText();
			check('Job Labor marks approved hours', /Approved/.test(laborText));
			await shot(page, 'job-labor');
		}
	} else {
		// The Field member, limited to their own hours for this run.
		await page.goto(`${origin}/timesheets?view=day&date=${cutoff}`);
		await page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
		await page.waitForTimeout(2000);
		check('No Approve button for own-only', (await page.getByRole('button', { name: 'Approve', exact: true }).count()) === 0);
		await openRow(page, 'Field Tester');
		const approvedLabels = await menuLabels(page, 0);
		check('Approved entry offers History only', approvedLabels.join(',') === 'History', approvedLabels.join(', '));
		await shot(page, 'approved-own');

		const params = new URLSearchParams({ user_id: fieldId, from: cutoff, to: '2026-10-12' });
		const { entries } = await (await page.request.get(`${origin}/api/time-clock/timesheets/entries?${params}`)).json();
		const approved = entries.find((entry) => entry.approved && !entry.is_running && entry.job);
		const open = entries.find((entry) => !entry.approved && !entry.is_running);
		check('Approved entries are not editable by their owner', entries.filter((entry) => entry.approved).every((entry) => !entry.can_edit && !entry.can_delete));
		console.log('entries', entries.length, 'approved job entry', approved?.id, 'unapproved', open?.id);

		if (open) {
			await page.goto(`${origin}/timesheets?view=day&date=${open.started_on ?? '2026-10-12'}`);
			await page.waitForTimeout(2000);
			await openRow(page, 'Field Tester');
			const openLabels = await menuLabels(page, 0);
			check('Unapproved entry can still be edited', openLabels.includes('Edit'), openLabels.join(', '));
		}

		const patch = await page.request.patch(`${origin}/api/time-clock/timesheets/entries/${approved.id}`, {
			data: { user_id: fieldId, job_id: approved.job.id, visit_id: approved.visit_id ?? null, day: cutoff, start_time: '05:00', end_time: '05:30' }
		});
		check('Timesheets API refuses changing approved hours', patch.status() === 409, `${patch.status()} ${await patch.text()}`);
		const del = await page.request.delete(`${origin}/api/time-clock/timesheets/entries/${approved.id}`);
		check('Timesheets API refuses deleting approved hours', del.status() === 409, `${del.status()} ${await del.text()}`);
		const labor = await page.request.patch(`${origin}/api/jobs/${approved.job.id}/time-entries/${approved.id}`, {
			data: { started_at: approved.started_at, minutes: 5 }
		});
		check('Job Labor API refuses changing approved hours', labor.status() === 409, `${labor.status()} ${await labor.text()}`);

		await page.goto(`${origin}/jobs/${approved.job.id}`);
		await page.getByRole('heading', { name: /labor/i }).first().waitFor({ timeout: 30000 });
		await page.waitForTimeout(2000);
		const section = page.locator('section', { has: page.getByRole('heading', { name: /labor/i }) }).first();
		await section.scrollIntoViewIfNeeded();
		await shot(page, 'job-labor-own');
	}

	await context.close();
} finally {
	await browser.close();
	if (errors.length) console.log('page errors:', errors.join(' || ').slice(0, 800));
	const failed = results.filter((result) => !result.passed);
	console.log(`${results.length - failed.length}/${results.length} checks passed`);
	if (failed.length) process.exitCode = 1;
}
