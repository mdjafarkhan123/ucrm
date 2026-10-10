import { createClient } from '@supabase/supabase-js';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';

/**
 * E4a: a Zoom meeting type in custom-link mode. Jafar turns the Discovery call into a Zoom call where he adds each
 * link; a visitor books the latest open time. Their confirmation says the joining link will follow, and Jafar's bell
 * asks for it. On the call's window he adds the link: the visitor is emailed it. The meeting type and the booking's
 * Lead are put back or removed afterwards.
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
const visitorEmail = 'dev.jafarkhan+e2e-book-video@gmail.com';
const joinUrl = 'https://us02web.zoom.us/j/81234567890?pwd=e2eTestLink';
const shots = process.env.E2E_SCREENSHOT_DIR;
const DAY = 24 * 60 * 60_000;

type MeetingType = Record<string, unknown> & { id: string; slug: string };

function database() {
	return createClient(supabaseUrl ?? '', serviceKey ?? '', {
		auth: { autoRefreshToken: false, persistSession: false }
	});
}

async function signIn(page: Page) {
	await page.goto('/jafar/login', { waitUntil: 'networkidle' });
	await page.getByLabel('Email').fill(ownerEmail ?? '');
	await page.getByLabel('Password').fill(ownerPassword ?? '');
	await page.getByRole('button', { name: /Sign in/ }).click();
	await page.waitForURL((url) => !url.pathname.endsWith('/login'));
}

/** The fields a meeting type's save takes, out of the settings' copy of it. */
function typeBody(type: MeetingType, change: Record<string, unknown> = {}) {
	const keys = [
		'slug',
		'name',
		'description',
		'duration_minutes',
		'location_kind',
		'video_link_mode',
		'min_notice_minutes',
		'horizon_days',
		'buffer_minutes',
		'slot_interval_minutes',
		'requires_approval',
		'change_deadline_minutes',
		'is_active',
		'visitor_reminder_minutes',
		'host_member_id',
		'host_member_ids'
	];
	return { ...Object.fromEntries(keys.map((key) => [key, type[key]])), ...change };
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

async function emailsSince(template: string, since: string) {
	const { data, error } = await database()
		.from('platform_outbox_deliveries')
		.select('payload')
		.eq('template_key', template)
		.eq('recipient_email', visitorEmail)
		.gte('created_at', since);
	if (error) throw error;
	return data.map((row) => JSON.stringify(row.payload));
}

test.describe.serial('a Zoom call with a link the host adds', () => {
	test.skip(
		!ownerEmail ||
			!ownerPassword ||
			!supabaseUrl ||
			!serviceKey ||
			(Boolean(turnstileSecret) && !turnstileSecret?.startsWith('1x')),
		'Set the owner login, the Supabase service key and the Turnstile test keys to run the video check.'
	);

	let wasEnabled = true;

	test.beforeAll(async () => {
		await removeTestBooking();
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

	test.afterAll(async () => {
		await removeTestBooking();
		if (!wasEnabled)
			await database()
				.from('platform_owner_settings')
				.update({ booking_enabled: false })
				.eq('id', true);
	});

	test('the visitor is told the link will follow, and gets it when Jafar adds it', async ({
		page
	}) => {
		const startedAt = new Date().toISOString();
		await signIn(page);
		const request: APIRequestContext = page.request;

		const settings = (await (await request.get('/api/jafar/booking')).json()) as {
			meeting_types: MeetingType[];
		};
		const original = settings.meeting_types.find((type) => type.slug === slug);
		expect(original, `the ${slug} meeting type`).toBeTruthy();
		const type = original!;
		const saved = await request.patch(`/api/jafar/booking/types/${type.id}`, {
			data: typeBody(type, { location_kind: 'zoom', video_link_mode: 'custom' })
		});
		expect(saved.ok(), await saved.text()).toBe(true);

		try {
			if (shots) {
				await page.goto(`/jafar/settings/booking/types/${type.id}`, { waitUntil: 'networkidle' });
				await expect(page.getByText('Joining link', { exact: true })).toBeVisible();
				for (const width of [1440, 390]) {
					await page.setViewportSize({ width, height: width === 390 ? 844 : 900 });
					await page.getByLabel('Where the call happens').scrollIntoViewIfNeeded();
					await page.screenshot({ path: `${shots}/video-type-${width}.png` });
				}
				await page.setViewportSize({ width: 1440, height: 900 });
			}

			const from = new Date(Date.now() + DAY).toISOString();
			const to = new Date(Date.now() + 44 * DAY).toISOString();
			const slots = await request.get(`/api/public/book/${slug}/slots`, { params: { from, to } });
			expect(slots.ok()).toBe(true);
			const starts = (await slots.json()) as string[];
			expect(starts.length).toBeGreaterThan(0);
			const booked = await request.post(`/api/public/book/${slug}`, {
				data: {
					starts_at: starts[starts.length - 1],
					name: 'E2E Video Visitor',
					email: visitorEmail,
					phone: '+880 1711 000010',
					business_name: 'E2E Video Plumbing',
					country_code: 'BD',
					trade: 'Plumbing',
					note: null,
					time_zone: 'Asia/Dhaka',
					turnstile_token: 'XXXX.DUMMY.TOKEN.XXXX'
				}
			});
			expect(booked.ok(), await booked.text()).toBe(true);
			const call = ((await booked.json()) as { call: Record<string, unknown> }).call;
			expect(call).toMatchObject({ location_kind: 'zoom', video_join_url: null });

			// The confirmation promises the link; the host is asked for it.
			const confirmation = await emailsSince('booking_booked', startedAt);
			expect(confirmation).toHaveLength(1);
			expect(confirmation[0]).toContain('We will email you the joining link before the call.');
			const { data: booking, error } = await database()
				.from('platform_bookings')
				.select('entry_id, relationship_id, location_kind')
				.eq('visitor_email', visitorEmail)
				.single();
			if (error) throw error;
			expect(booking.location_kind).toBe('zoom');
			const ask = await database()
				.from('platform_owner_notifications')
				.select('title')
				.eq('kind', 'sales_call_video_link_needed')
				.eq('target_id', booking.relationship_id);
			expect(ask.data?.[0]?.title).toBe("Add the Zoom link for E2E Video Plumbing's call");

			// Jafar adds the link on the call's window.
			await page.goto(`/jafar/leads/${booking.relationship_id}`, { waitUntil: 'networkidle' });
			await page.locator('.lead-page__call').first().click();
			await expect(page.getByText('No Zoom link yet')).toBeVisible();
			if (shots)
				for (const width of [1440, 390]) {
					await page.setViewportSize({ width, height: width === 390 ? 844 : 900 });
					await page.getByText('No Zoom link yet').scrollIntoViewIfNeeded();
					await page.screenshot({ path: `${shots}/video-pending-${width}.png` });
				}
			await page.getByRole('button', { name: 'Add link' }).click();
			await page.getByLabel('Zoom joining link').fill('zoom.us/j/1');
			await page.getByRole('button', { name: 'Add and email' }).click();
			await expect(page.getByText('Paste the full link, starting with https://.')).toBeVisible();
			await page.getByLabel('Zoom joining link').fill(joinUrl);
			await page.getByRole('button', { name: 'Add and email' }).click();
			await expect(page.getByRole('link', { name: joinUrl })).toBeVisible();
			if (shots)
				for (const width of [1440, 390]) {
					await page.setViewportSize({ width, height: width === 390 ? 844 : 900 });
					await page.getByRole('link', { name: joinUrl }).scrollIntoViewIfNeeded();
					await page.screenshot({ path: `${shots}/video-linked-${width}.png` });
				}

			const linkEmail = await emailsSince('booking_video_link', startedAt);
			expect(linkEmail).toHaveLength(1);
			expect(linkEmail[0]).toContain(joinUrl);
			const stored = await database()
				.from('platform_bookings')
				.select('video_join_url, video_link_source')
				.eq('entry_id', booking.entry_id)
				.single();
			expect(stored.data).toEqual({ video_join_url: joinUrl, video_link_source: 'custom' });
		} finally {
			const back = await request.patch(`/api/jafar/booking/types/${type.id}`, {
				data: typeBody(type)
			});
			expect(back.ok(), await back.text()).toBe(true);
		}
	});
});
