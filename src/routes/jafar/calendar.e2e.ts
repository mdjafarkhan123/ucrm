import { createClient } from '@supabase/supabase-js';
import { expect, test, type Page } from '@playwright/test';

/**
 * C2: a call booked with two reminders is moved, and the reminders for the old time never arrive. On the test
 * business, Jafar books a call three days out with an email a day before and an alert 15 minutes before, then moves
 * it two days later. The waiting reminders are read straight from the database: exactly two, both for the new time.
 * The calendar shows the call on its new day. The call is cancelled and removed afterwards, and the business gets
 * back the next action it had.
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const businessId = process.env.JAFAR_TEST_DEAL_LEAD_ID ?? '9762d6ac-4e05-49d0-9ca4-e1ba6157c4de';
const shots = process.env.E2E_SCREENSHOT_DIR;
const zone = 'Asia/Dhaka';

const MINUTE = 60_000;

function database() {
	return createClient(supabaseUrl ?? '', serviceKey ?? '', {
		auth: { autoRefreshToken: false, persistSession: false }
	});
}

/** A day in Dhaka (UTC+6, no daylight saving) `offsetDays` from today, and an instant on it. */
function dhakaDay(offsetDays: number) {
	const shifted = new Date(Date.now() + 6 * 60 * MINUTE + offsetDays * 24 * 60 * MINUTE);
	return shifted.toISOString().slice(0, 10);
}

function dhakaInstant(day: string, time: string) {
	return new Date(`${day}T${time}:00+06:00`).toISOString();
}

async function signIn(page: Page) {
	await page.goto('/jafar/login', { waitUntil: 'networkidle' });
	await page.getByLabel('Email').fill(ownerEmail ?? '');
	await page.getByLabel('Password').fill(ownerPassword ?? '');
	await page.getByRole('button', { name: /Sign in/ }).click();
	await page.waitForURL((url) => !url.pathname.endsWith('/login'));
}

async function waitingReminders(entryId: string) {
	const { data, error } = await database()
		.from('platform_reminders')
		.select('channel, fire_at')
		.eq('entry_id', entryId)
		.is('sent_at', null)
		.order('fire_at');
	if (error) throw error;
	return data.map((row) => ({
		channel: row.channel,
		fire_at: new Date(row.fire_at).toISOString()
	}));
}

test('moving a call moves its reminders', async ({ browser }) => {
	test.skip(
		!ownerEmail || !ownerPassword || !supabaseUrl || !serviceKey,
		'Set SUPER_ADMIN_* and the Supabase service key to run the calendar check.'
	);
	test.setTimeout(120_000);
	const page = await (
		await browser.newContext({ viewport: { width: 1440, height: 1000 }, timezoneId: zone })
	).newPage();
	await signIn(page);

	const before = await (await page.request.get(`/api/jafar/leads/${businessId}`)).json();
	const original = before.lead.next_action
		? {
				mode: 'set',
				text: before.lead.next_action,
				due_on: before.lead.next_action_due_on,
				due_at: before.lead.next_action_at ?? null
			}
		: { mode: 'clear' };
	const title = `Calendar check ${Date.now()}`;
	let entryId: string | null = null;

	try {
		const oldDay = dhakaDay(3);
		const booked = await page.request.post('/api/jafar/calendar/entries', {
			data: {
				kind: 'call',
				relationship_id: businessId,
				starts_at: dhakaInstant(oldDay, '15:00'),
				ends_at: dhakaInstant(oldDay, '15:30'),
				title,
				reminders: [
					{ channel: 'email', minutes_before: 24 * 60 },
					{ channel: 'in_app', minutes_before: 15 }
				],
				time_zone: zone
			}
		});
		expect(booked.status(), await booked.text()).toBe(201);
		entryId = ((await booked.json()) as { id: string }).id;

		const oldStart = Date.parse(dhakaInstant(oldDay, '15:00'));
		expect(await waitingReminders(entryId)).toEqual([
			{ channel: 'email', fire_at: new Date(oldStart - 24 * 60 * MINUTE).toISOString() },
			{ channel: 'in_app', fire_at: new Date(oldStart - 15 * MINUTE).toISOString() }
		]);

		const newDay = dhakaDay(5);
		const moved = await page.request.patch(`/api/jafar/calendar/entries/${entryId}`, {
			data: {
				action: 'move',
				starts_at: dhakaInstant(newDay, '11:00'),
				ends_at: dhakaInstant(newDay, '11:45')
			}
		});
		expect(moved.ok(), await moved.text()).toBe(true);

		// Only the new time's two reminders wait; nothing is left for the old time.
		const newStart = Date.parse(dhakaInstant(newDay, '11:00'));
		expect(await waitingReminders(entryId)).toEqual([
			{ channel: 'email', fire_at: new Date(newStart - 24 * 60 * MINUTE).toISOString() },
			{ channel: 'in_app', fire_at: new Date(newStart - 15 * MINUTE).toISOString() }
		]);

		await page.goto(`/jafar/calendar?view=day&date=${newDay}`);
		await expect(page.getByRole('heading', { name: 'Calendar', level: 1 })).toBeVisible();
		await expect(page.locator('.sales-card', { hasText: title }).first()).toBeVisible();
		if (shots) await page.screenshot({ path: `${shots}/calendar-day-desktop.png` });

		await page.goto(`/jafar/calendar?view=day&date=${oldDay}`);
		await expect(page.getByRole('heading', { name: 'Calendar', level: 1 })).toBeVisible();
		await expect(page.locator('.sales-card', { hasText: title })).toHaveCount(0);
	} finally {
		if (entryId) {
			await page.request.patch(`/api/jafar/calendar/entries/${entryId}`, {
				data: { action: 'close', outcome: 'cancelled' }
			});
			const removed = await database().from('platform_calendar_entries').delete().eq('id', entryId);
			expect(removed.error).toBeNull();
		}
		const restored = await page.request.patch(`/api/jafar/leads/${businessId}`, {
			data: { next_action: original }
		});
		expect(restored.ok(), await restored.text()).toBe(true);
	}
});

/**
 * C2a: Done on a to-do item that stands for a call asks how the call went, and the date boxes follow the browser's
 * language — a UK browser types the day first. A call is booked tomorrow on the test business, the home's Done opens
 * "How did it go?", and choosing Held shows the next step's Due box in day/month/year order. The call is cancelled
 * and removed afterwards, and the business gets back the next action it had.
 */
test('Done on a call asks how it went, in the browser language', async ({ browser }) => {
	test.skip(
		!ownerEmail || !ownerPassword || !supabaseUrl || !serviceKey,
		'Set SUPER_ADMIN_* and the Supabase service key to run the calendar check.'
	);
	test.setTimeout(120_000);
	const page = await (
		await browser.newContext({
			viewport: { width: 390, height: 844 },
			timezoneId: zone,
			locale: 'en-GB'
		})
	).newPage();
	await signIn(page);

	const before = await (await page.request.get(`/api/jafar/leads/${businessId}`)).json();
	const original = before.lead.next_action
		? {
				mode: 'set',
				text: before.lead.next_action,
				due_on: before.lead.next_action_due_on,
				due_at: before.lead.next_action_at ?? null
			}
		: { mode: 'clear' };
	const title = `Outcome check ${Date.now()}`;
	let entryId: string | null = null;

	try {
		const day = dhakaDay(1);
		const booked = await page.request.post('/api/jafar/calendar/entries', {
			data: {
				kind: 'call',
				relationship_id: businessId,
				starts_at: dhakaInstant(day, '15:00'),
				ends_at: dhakaInstant(day, '15:30'),
				title,
				reminders: [],
				time_zone: zone
			}
		});
		expect(booked.status(), await booked.text()).toBe(201);
		entryId = ((await booked.json()) as { id: string }).id;

		await page.goto('/jafar');
		const row = page.locator('.business-home__item', { hasText: title });
		await row.getByRole('button', { name: /^Done/ }).click();
		const dialog = page.getByRole('dialog', { name: 'How did it go?' });
		await expect(dialog).toBeVisible();
		await dialog.getByText('Held', { exact: true }).click();

		const due = dialog.locator('#call-outcome-day');
		await expect(due).toBeVisible();
		const order = await due
			.locator('[data-segment]:not([data-segment="literal"])')
			.evaluateAll((parts) => parts.map((part) => part.getAttribute('data-segment')));
		expect(order).toEqual(['day', 'month', 'year']);
		if (shots) await page.screenshot({ path: `${shots}/home-call-outcome-phone.png` });
	} finally {
		if (entryId) {
			await page.request.patch(`/api/jafar/calendar/entries/${entryId}`, {
				data: { action: 'close', outcome: 'cancelled' }
			});
			const removed = await database().from('platform_calendar_entries').delete().eq('id', entryId);
			expect(removed.error).toBeNull();
		}
		const restored = await page.request.patch(`/api/jafar/leads/${businessId}`, {
			data: { next_action: original }
		});
		expect(restored.ok(), await restored.text()).toBe(true);
	}
});
