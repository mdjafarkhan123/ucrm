import { createClient } from '@supabase/supabase-js';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';

/**
 * E3: handing a call a visitor booked online to another host. Jafar makes the Sales teammate a host of the
 * Discovery call with all-day hours, a visitor books the latest open time, and a Busy block puts the teammate out
 * of reach: the handover is refused. With the block gone it is accepted, the call becomes the teammate's, and an
 * email to the visitor is queued. The meeting's hosts, the teammate's hours, the booking's Lead and the Busy block
 * are all put back or removed afterwards.
 *
 * Needs the owner login, the Supabase service key, and the Turnstile test keys the public booking check uses:
 * PUBLIC_TURNSTILE_SITE_KEY=1x00000000000000000000AA TURNSTILE_SECRET_KEY=1x0000000000000000000000000000000AA
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const turnstileSecret = process.env.TURNSTILE_SECRET_KEY;
const slug = process.env.JAFAR_TEST_BOOKING_SLUG ?? 'discovery-call';
const teammateEmail =
	process.env.JAFAR_TEST_TEAMMATE_EMAIL ?? 'dev.jafarkhan+uplift-sales@gmail.com';
// The test-only Sales teammate's password, as Login.md records it.
const teammatePassword = process.env.JAFAR_TEST_TEAMMATE_PASSWORD ?? 'PaidLaunch16!';
const visitorEmail = 'dev.jafarkhan+e2e-book-host@gmail.com';
const shots = process.env.E2E_SCREENSHOT_DIR;
const DAY = 24 * 60 * 60_000;

type Hours = { weekday: number; start: string; end: string };
type MeetingType = Record<string, unknown> & {
	id: string;
	slug: string;
	host_member_id: string | null;
	host_member_ids: (string | null)[];
};
type Settings = {
	meeting_types: MeetingType[];
	hours: (Hours & { member_id: string | null })[];
};

function database() {
	return createClient(supabaseUrl ?? '', serviceKey ?? '', {
		auth: { autoRefreshToken: false, persistSession: false }
	});
}

async function signIn(page: Page, email = ownerEmail, password = ownerPassword) {
	await page.goto('/jafar/login', { waitUntil: 'networkidle' });
	await page.getByLabel('Email').fill(email ?? '');
	await page.getByLabel('Password').fill(password ?? '');
	await page.getByRole('button', { name: /Sign in/ }).click();
	await page.waitForURL((url) => !url.pathname.endsWith('/login'));
}

/** The fields a meeting type's save takes, out of the settings' copy of it. */
function typeBody(type: MeetingType, hosts: (string | null)[]) {
	const keys = [
		'slug',
		'name',
		'description',
		'duration_minutes',
		'min_notice_minutes',
		'horizon_days',
		'buffer_minutes',
		'slot_interval_minutes',
		'requires_approval',
		'change_deadline_minutes',
		'is_active'
	];
	return {
		...Object.fromEntries(keys.map((key) => [key, type[key]])),
		host_member_id: type.host_member_id,
		host_member_ids: hosts
	};
}

async function removeTestBooking() {
	const db = database();
	const { data, error } = await db
		.from('platform_bookings')
		.select('relationship_id')
		.eq('visitor_email', visitorEmail);
	if (error) throw error;
	const leads = [...new Set(data.flatMap((row) => row.relationship_id ?? []))];
	if (leads.length) {
		const removed = await db.from('platform_business_relationships').delete().in('id', leads);
		if (removed.error) throw removed.error;
	}
}

async function hostState(request: APIRequestContext, entryId: string, memberId: string) {
	const response = await request.get(`/api/jafar/calendar/entries/${entryId}/host`);
	expect(response.ok()).toBe(true);
	const body = (await response.json()) as {
		choices: { member_id: string | null; state: string }[];
	};
	return body.choices.find((choice) => choice.member_id === memberId)?.state;
}

test.describe.serial('changing the host of a booked call', () => {
	test.skip(
		!ownerEmail ||
			!ownerPassword ||
			!supabaseUrl ||
			!serviceKey ||
			(Boolean(turnstileSecret) && !turnstileSecret?.startsWith('1x')),
		'Set the owner login, the Supabase service key and the Turnstile test keys to run the host check.'
	);

	let teammateId = '';
	let original: MeetingType | null = null;
	let originalHours: Hours[] = [];
	let busyId: string | null = null;
	let wasEnabled = true;
	let restore: ((request: APIRequestContext) => Promise<void>) | null = null;

	test.beforeAll(async () => {
		await removeTestBooking();
		const { data, error } = await database()
			.from('platform_team_members')
			.select('id')
			.eq('email', teammateEmail)
			.eq('status', 'active')
			.is('removed_at', null)
			.single();
		if (error) throw error;
		teammateId = data.id;
		const local = ['::1', '127.0.0.1', '::ffff:127.0.0.1'].map((ip) => `public-booking:${ip}`);
		const reset = await database()
			.from('platform_rate_limit_buckets')
			.delete()
			.in('bucket_key', local);
		if (reset.error) throw reset.error;
		const owner = await database()
			.from('platform_owner_settings')
			.select('booking_enabled')
			.single();
		if (owner.error) throw owner.error;
		wasEnabled = owner.data.booking_enabled;
		if (!wasEnabled)
			await database()
				.from('platform_owner_settings')
				.update({ booking_enabled: true })
				.eq('id', true);
	});

	test.afterAll(async ({ browser }) => {
		if (busyId) await database().from('platform_calendar_entries').delete().eq('id', busyId);
		await removeTestBooking();
		if (!wasEnabled)
			await database()
				.from('platform_owner_settings')
				.update({ booking_enabled: false })
				.eq('id', true);
		if (restore) {
			const page = await browser.newPage();
			await signIn(page);
			await restore(page.request);
			await page.close();
		}
	});

	test('a busy host is refused, a free one takes the call and the visitor is emailed', async ({
		page,
		browser
	}) => {
		// Emails from earlier runs stay in the outbox after their Lead is removed: count only this run's.
		const startedAt = new Date().toISOString();
		await signIn(page);
		const request = page.request;

		// Make the teammate a host of the meeting, free all day every day.
		const settings = (await (await request.get('/api/jafar/booking')).json()) as Settings;
		original = settings.meeting_types.find((type) => type.slug === slug) ?? null;
		expect(original, `the ${slug} meeting type`).not.toBeNull();
		const type = original!;
		originalHours = settings.hours
			.filter((range) => range.member_id === teammateId)
			.map(({ weekday, start, end }) => ({ weekday, start, end }));
		restore = async (owner) => {
			const hosts = await owner.patch(`/api/jafar/booking/types/${type.id}`, {
				data: typeBody(type, type.host_member_ids)
			});
			expect(hosts.ok()).toBe(true);
			const hours = await owner.patch(`/api/jafar/booking/hours/${teammateId}`, {
				data: { hours: originalHours }
			});
			expect(hours.ok()).toBe(true);
		};
		const allDay = [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({
			weekday,
			start: '00:00',
			end: '23:59'
		}));
		expect(
			(
				await request.patch(`/api/jafar/booking/hours/${teammateId}`, { data: { hours: allDay } })
			).ok()
		).toBe(true);
		const saved = await request.patch(`/api/jafar/booking/types/${type.id}`, {
			data: typeBody(type, [...new Set([...type.host_member_ids, teammateId])])
		});
		expect(saved.ok(), await saved.text()).toBe(true);

		// Put the hosts and hours back with this sign-in: a second one in afterAll can hit the login limit.
		try {
			// A visitor books the latest open time; the call is the default host's.
			const from = new Date(Date.now() + DAY).toISOString();
			const to = new Date(Date.now() + 44 * DAY).toISOString();
			const slots = await request.get(`/api/public/book/${slug}/slots`, { params: { from, to } });
			expect(slots.ok()).toBe(true);
			const starts = (await slots.json()) as string[];
			expect(starts.length).toBeGreaterThan(0);
			const startsAt = starts[starts.length - 1];
			const booked = await request.post(`/api/public/book/${slug}`, {
				data: {
					starts_at: startsAt,
					name: 'E2E Host Visitor',
					email: visitorEmail,
					phone: '+880 1711 000009',
					business_name: 'E2E Host Change Plumbing',
					country_code: 'BD',
					trade: 'Plumbing',
					note: null,
					time_zone: 'Asia/Dhaka',
					turnstile_token: 'XXXX.DUMMY.TOKEN.XXXX'
				}
			});
			expect(booked.ok(), await booked.text()).toBe(true);
			const { data: booking, error } = await database()
				.from('platform_bookings')
				.select(
					'id, entry_id, relationship_id, entry:platform_calendar_entries(starts_at, ends_at)'
				)
				.eq('visitor_email', visitorEmail)
				.single();
			if (error) throw error;
			const entryId = booking.entry_id as string;
			const entry = booking.entry as unknown as { starts_at: string; ends_at: string };

			// Busy then: refused, and the call keeps its host.
			// The teammate blocks the time on their own calendar, as they would in the app.
			const teammatePage = await browser.newPage();
			await signIn(teammatePage, teammateEmail, teammatePassword);
			const busy = await teammatePage.request.post('/api/jafar/calendar/entries', {
				data: {
					kind: 'busy',
					starts_at: entry.starts_at,
					ends_at: entry.ends_at,
					title: 'E2E busy'
				}
			});
			expect(busy.ok(), await busy.text()).toBe(true);
			busyId = ((await busy.json()) as { id: string }).id;
			await teammatePage.close();
			expect(await hostState(request, entryId, teammateId)).toBe('busy');
			const refused = await request.post(`/api/jafar/calendar/entries/${entryId}/host`, {
				data: { member_id: teammateId }
			});
			expect(refused.status()).toBe(409);

			// Free then: accepted, the call is theirs, and the visitor's email is queued.
			await database().from('platform_calendar_entries').delete().eq('id', busyId);
			busyId = null;
			expect(await hostState(request, entryId, teammateId)).toBe('free');
			if (shots) {
				// The call's window on its Lead, with Change host open.
				await page.goto(`/jafar/leads/${booking.relationship_id}`, { waitUntil: 'networkidle' });
				await page.locator('.lead-page__call').first().click();
				await page.getByRole('button', { name: 'Change host' }).click();
				await expect(page.getByText('Free then').first()).toBeVisible();
				for (const width of [1440, 390]) {
					await page.setViewportSize({ width, height: width === 390 ? 844 : 900 });
					await page.screenshot({ path: `${shots}/host-change-${width}.png` });
				}
				await page.keyboard.press('Escape');
			}
			const changed = await request.post(`/api/jafar/calendar/entries/${entryId}/host`, {
				data: { member_id: teammateId }
			});
			expect(changed.ok(), await changed.text()).toBe(true);
			const call = await database()
				.from('platform_calendar_entries')
				.select('owner_member_id')
				.eq('id', entryId)
				.single();
			expect(call.data?.owner_member_id).toBe(teammateId);
			const email = await database()
				.from('platform_outbox_deliveries')
				.select('id')
				.eq('template_key', 'booking_host_changed')
				.eq('recipient_email', visitorEmail)
				.gte('created_at', startedAt);
			expect(email.data).toHaveLength(1);
		} finally {
			await restore?.(request);
			restore = null;
		}
	});
});
