import { createHmac } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { expect, test } from '@playwright/test';

/**
 * E1: two visitors ask for the same time at once and only one gets it; a visitor books through the page and the
 * call lands on Jafar's calendar and on the Lead's history. Both bookings use the latest open times, far from
 * real calls. E2: a visitor moves a booking through their link, freeing the old time and moving its reminders with
 * it; in approval mode a request holds no time, and approving it checks the time again. Everything the test made -- Leads, calls, bookings, history -- is removed afterwards, and the link
 * is switched back off if the test had to switch it on.
 *
 * The preview server checks Turnstile, so run with Cloudflare's always-pass test keys:
 * PUBLIC_TURNSTILE_SITE_KEY=1x00000000000000000000AA TURNSTILE_SECRET_KEY=1x0000000000000000000000000000000AA
 * The visitor's link is signed with the server's SESSION_SECRET, which the shell needs too.
 */

const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const turnstileSecret = process.env.TURNSTILE_SECRET_KEY;
const slug = process.env.JAFAR_TEST_BOOKING_SLUG ?? 'discovery-call';
const sessionSecret = process.env.SESSION_SECRET;
const emails = ['a', 'b', 'page', 'move', 'ask-a', 'ask-b'].map(
	(who) => `dev.jafarkhan+e2e-book-${who}@gmail.com`
);
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
		.select('relationship_id')
		.in('visitor_email', emails);
	if (error) throw error;
	const leads = [...new Set(bookings.flatMap((row) => row.relationship_id ?? []))];
	// A Lead's calls, bookings and history go with it.
	if (leads.length) {
		const removed = await db.from('platform_business_relationships').delete().in('id', leads);
		if (removed.error) throw removed.error;
	}
}

test.describe.serial('public booking', () => {
	test.skip(
		!supabaseUrl ||
			!serviceKey ||
			!sessionSecret ||
			(Boolean(turnstileSecret) && !turnstileSecret?.startsWith('1x')),
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
		const entry = data[0].entry as unknown as {
			kind: string;
			starts_at: string;
			relationship_id: string;
		};
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
		const lead = (data.entry as unknown as { relationship_id: string }).relationship_id;
		const history = await database()
			.from('platform_business_history')
			.select('kind, details')
			.eq('relationship_id', lead)
			.eq('kind', 'call_booked');
		if (history.error) throw history.error;
		expect(history.data).toHaveLength(1);
		expect((history.data[0].details as { booked_online?: boolean }).booked_online).toBe(true);
	});

	/** The visitor's link, as the confirmation email carries it (booking-links.ts). */
	function manageToken(bookingId: string) {
		const signature = createHmac('sha256', sessionSecret ?? '')
			.update(`uplift-booking-link:${bookingId}`)
			.digest('base64url');
		return `${bookingId}.${signature}`;
	}

	async function openStarts(request: import('@playwright/test').APIRequestContext) {
		const response = await request.get(`/api/public/book/${slug}/slots`, {
			params: {
				from: new Date(Date.now() + DAY).toISOString(),
				to: new Date(Date.now() + 44 * DAY).toISOString()
			}
		});
		expect(response.ok()).toBe(true);
		return ((await response.json()) as string[]).map((start) => Date.parse(start));
	}

	test('a visitor moves their booking: the old time frees and the reminders follow', async ({
		request
	}) => {
		const [first, second] = await latestOpenTimes(request);
		const booked = await request.post(`/api/public/book/${slug}`, { data: visitor(3, first) });
		expect(booked.status()).toBe(200);

		const db = database();
		const booking = await db
			.from('platform_bookings')
			.select('id, entry_id')
			.eq('visitor_email', emails[3])
			.single();
		if (booking.error) throw booking.error;
		const entryId = booking.data.entry_id as string;
		const before = await db.from('platform_reminders').select('fire_at').eq('entry_id', entryId);
		if (before.error) throw before.error;
		expect(before.data.length).toBeGreaterThan(0);
		expect(await openStarts(request)).not.toContain(Date.parse(first));

		const moved = await request.post(`/api/public/book/manage/${manageToken(booking.data.id)}`, {
			data: { action: 'move', starts_at: second }
		});
		expect(moved.status()).toBe(200);

		const entry = await db
			.from('platform_calendar_entries')
			.select('starts_at')
			.eq('id', entryId)
			.single();
		if (entry.error) throw entry.error;
		expect(Date.parse(entry.data.starts_at)).toBe(Date.parse(second));
		const open = await openStarts(request);
		expect(open).toContain(Date.parse(first));
		expect(open).not.toContain(Date.parse(second));

		// Each reminder keeps its distance from the call: the old time's are replaced, none are left behind.
		const after = await db.from('platform_reminders').select('fire_at').eq('entry_id', entryId);
		if (after.error) throw after.error;
		const lead = (rows: { fire_at: string }[], start: string) =>
			rows.map((row) => Date.parse(start) - Date.parse(row.fire_at)).sort((a, b) => a - b);
		expect(lead(after.data, second)).toEqual(lead(before.data, first));
	});

	test('in approval mode a request holds no time, and approving checks it again', async ({
		request
	}) => {
		const db = database();
		const type = await db
			.from('platform_meeting_types')
			.select('id, requires_approval')
			.eq('slug', slug)
			.single();
		if (type.error) throw type.error;
		const switched = !type.data.requires_approval;
		if (switched) {
			const on = await db
				.from('platform_meeting_types')
				.update({ requires_approval: true })
				.eq('id', type.data.id);
			if (on.error) throw on.error;
		}
		try {
			const [, last] = await latestOpenTimes(request);
			// Two visitors ask for the same time: both are requests, and the time stays open.
			for (const who of [4, 5]) {
				const asked = await request.post(`/api/public/book/${slug}`, { data: visitor(who, last) });
				expect(asked.status()).toBe(200);
				expect((await asked.json()).requested).toBe(true);
			}
			const requests = await db
				.from('platform_bookings')
				.select('id, status, entry_id, visitor_email')
				.in('visitor_email', emails.slice(4, 6));
			if (requests.error) throw requests.error;
			expect(requests.data.map((row) => [row.status, row.entry_id])).toEqual([
				['requested', null],
				['requested', null]
			]);
			expect(await openStarts(request)).toContain(Date.parse(last));

			// Approving the first books the time; the second finds it taken and must be offered another.
			const byEmail = new Map(requests.data.map((row) => [row.visitor_email, row.id]));
			const approve = (bookingId: string) =>
				db.rpc('owner_booking_decide', {
					actor_email: 'e2e-booking@uplift.test',
					target_booking_id: bookingId,
					decision: 'approve'
				});
			const firstAnswer = await approve(byEmail.get(emails[4])!);
			if (firstAnswer.error) throw firstAnswer.error;
			expect((firstAnswer.data as { outcome: string }).outcome).toBe('approved');
			const secondAnswer = await approve(byEmail.get(emails[5])!);
			if (secondAnswer.error) throw secondAnswer.error;
			expect((secondAnswer.data as { outcome: string }).outcome).toBe('taken');
			expect(await openStarts(request)).not.toContain(Date.parse(last));
		} finally {
			if (switched)
				await db
					.from('platform_meeting_types')
					.update({ requires_approval: false })
					.eq('id', type.data.id);
		}
	});
});
