import { createClient } from '@supabase/supabase-js';
import { expect, test } from '@playwright/test';

/**
 * E1: two visitors ask for the same time at once and only one gets it; a visitor books through the page and the
 * call lands on Jafar's calendar and on the Lead's history. Both bookings use the latest open times, far from
 * real calls. Everything the test made -- Leads, calls, bookings, history -- is removed afterwards, and the link
 * is switched back off if the test had to switch it on.
 *
 * The preview server checks Turnstile, so run with Cloudflare's always-pass test keys:
 * PUBLIC_TURNSTILE_SITE_KEY=1x00000000000000000000AA TURNSTILE_SECRET_KEY=1x0000000000000000000000000000000AA
 */

const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const turnstileSecret = process.env.TURNSTILE_SECRET_KEY;
const slug = process.env.JAFAR_TEST_BOOKING_SLUG ?? 'discovery-call';
const emails = ['a', 'b', 'page'].map((who) => `dev.jafarkhan+e2e-book-${who}@gmail.com`);
const DAY = 24 * 60 * 60_000;

function database() {
	return createClient(supabaseUrl ?? '', serviceKey ?? '', {
		auth: { autoRefreshToken: false, persistSession: false }
	});
}

function visitor(who: number, startsAt: string) {
	return {
		starts_at: startsAt,
		name: `E2E Visitor ${who}`,
		email: emails[who],
		phone: `+880 1711 00000${who}`,
		business_name: `E2E Booking Plumbing ${who}`,
		country_code: 'BD',
		trade: 'Plumbing',
		note: null,
		time_zone: 'Asia/Dhaka',
		turnstile_token: 'XXXX.DUMMY.TOKEN.XXXX'
	};
}

async function removeTestBookings() {
	const db = database();
	const { data: bookings, error } = await db
		.from('platform_bookings')
		.select('entry:platform_calendar_entries(relationship_id)')
		.in('visitor_email', emails);
	if (error) throw error;
	const leads = bookings.flatMap((row) => {
		const entry = row.entry as { relationship_id: string | null } | null;
		return entry?.relationship_id ? [entry.relationship_id] : [];
	});
	// A Lead's calls, bookings and history go with it.
	if (leads.length) {
		const removed = await db.from('platform_business_relationships').delete().in('id', leads);
		if (removed.error) throw removed.error;
	}
}

test.describe.serial('public booking', () => {
	test.skip(
		!supabaseUrl || !serviceKey || (Boolean(turnstileSecret) && !turnstileSecret?.startsWith('1x')),
		'Set the Supabase service key and the Turnstile test keys to run the booking check.'
	);

	let wasEnabled = true;

	test.beforeAll(async () => {
		await removeTestBookings();
		// The test books from this machine more often than one visitor may; start its count again.
		const local = ['::1', '127.0.0.1', '::ffff:127.0.0.1'].map((ip) => `public-booking:${ip}`);
		const reset = await database()
			.from('platform_rate_limit_buckets')
			.delete()
			.in('bucket_key', local);
		if (reset.error) throw reset.error;
		const { data, error } = await database()
			.from('platform_owner_settings')
			.select('booking_enabled')
			.maybeSingle();
		if (error) throw error;
		wasEnabled = Boolean(data?.booking_enabled);
		if (!wasEnabled)
			await database()
				.from('platform_owner_settings')
				.update({ booking_enabled: true })
				.eq('id', true);
	});

	test.afterAll(async () => {
		await removeTestBookings();
		if (!wasEnabled)
			await database()
				.from('platform_owner_settings')
				.update({ booking_enabled: false })
				.eq('id', true);
	});

	async function latestOpenTimes(request: import('@playwright/test').APIRequestContext) {
		const from = new Date(Date.now() + DAY).toISOString();
		const to = new Date(Date.now() + 44 * DAY).toISOString();
		const response = await request.get(`/api/public/book/${slug}/slots`, { params: { from, to } });
		expect(response.ok()).toBe(true);
		const starts = (await response.json()) as string[];
		expect(starts.length).toBeGreaterThan(1);
		return starts.slice(-2);
	}

	test('two visitors ask for the same time at once and only one gets it', async ({ request }) => {
		const [, last] = await latestOpenTimes(request);
		const responses = await Promise.all(
			[0, 1].map((who) => request.post(`/api/public/book/${slug}`, { data: visitor(who, last) }))
		);
		expect(responses.map((response) => response.status()).sort()).toEqual([200, 409]);

		const { data, error } = await database()
			.from('platform_bookings')
			.select('visitor_email, entry:platform_calendar_entries(kind, starts_at, relationship_id)')
			.in('visitor_email', emails.slice(0, 2));
		if (error) throw error;
		expect(data).toHaveLength(1);
		const entry = data[0].entry as { kind: string; starts_at: string; relationship_id: string };
		expect(entry.kind).toBe('call');
		expect(new Date(entry.starts_at).toISOString()).toBe(new Date(last).toISOString());
	});

	test('a visitor books through the page and the call joins the Lead history', async ({
		page,
		request
	}) => {
		const [open] = await latestOpenTimes(request);
		const response = await request.post(`/api/public/book/${slug}`, {
			data: { ...visitor(2, open), name: '' }
		});
		expect(response.status()).toBe(422);
		expect((await response.json()).field_errors.name).toBe('Enter your name.');

		await page.goto(`/book/${slug}`, { waitUntil: 'networkidle' });
		await expect(page.getByRole('heading', { name: 'Choose a day and time' })).toBeVisible();
		await page
			.getByRole('button', { name: /^\d{1,2}:\d{2}/ })
			.first()
			.click();
		await page.getByLabel('Your name').fill('E2E Visitor 2');
		await page.getByLabel('Email').fill(emails[2]);
		await page.getByLabel('Phone, with country code').fill('+880 1711 000002');
		await page.getByLabel('Business name').fill('E2E Booking Plumbing 2');
		await page.getByRole('combobox', { name: /countr/i }).fill('Bangladesh');
		await page.getByRole('option', { name: /Bangladesh/ }).click();
		await page.getByLabel('Your trade').fill('Plumbing');
		await page.getByRole('button', { name: 'Book the call' }).click();
		await expect(page.getByRole('heading', { name: "You're booked" })).toBeVisible();

		const { data, error } = await database()
			.from('platform_bookings')
			.select('entry:platform_calendar_entries(relationship_id)')
			.eq('visitor_email', emails[2])
			.single();
		if (error) throw error;
		const lead = (data.entry as { relationship_id: string }).relationship_id;
		const history = await database()
			.from('platform_business_history')
			.select('kind, details')
			.eq('relationship_id', lead)
			.eq('kind', 'call_booked');
		if (history.error) throw history.error;
		expect(history.data).toHaveLength(1);
		expect((history.data[0].details as { booked_online?: boolean }).booked_online).toBe(true);
	});
});
