import { createServer, type Server } from 'node:http';
import { createClient } from '@supabase/supabase-js';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';

/**
 * E4b: Jafar connects Zoom and a Zoom meeting type in automatic mode makes one meeting per booking. A stand-in Zoom
 * (started here) answers the sign-in and the meetings API, so the whole path runs without Jafar's Zoom app: connect,
 * book (the confirmation carries the meeting's link), move the call (the meeting moves), a Zoom outage (the booking
 * stands and the link follows), cancel (the meeting is deleted). The meeting type is put back, the connection and the
 * booking's Lead removed afterwards.
 *
 * Needs the owner login, the Supabase service key, the Turnstile test keys, and the app started with the stand-in:
 * ZOOM_OAUTH_BASE_URL=http://127.0.0.1:4599 ZOOM_API_BASE_URL=http://127.0.0.1:4599/v2 ZOOM_CLIENT_ID=e2e
 * ZOOM_CLIENT_SECRET=e2e ZOOM_CREDENTIAL_KEYRING='{"activeKeyId":"v1","keys":{"v1":"<openssl rand -base64 32>"}}'
 * PUBLIC_TURNSTILE_SITE_KEY=1x00000000000000000000AA TURNSTILE_SECRET_KEY=1x0000000000000000000000000000000AA
 */

const ownerEmail = process.env.SUPER_ADMIN_EMAIL;
const ownerPassword = process.env.SUPER_ADMIN_PASSWORD;
const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const turnstileSecret = process.env.TURNSTILE_SECRET_KEY;
const slug = process.env.JAFAR_TEST_BOOKING_SLUG ?? 'discovery-call';
const visitorEmail = 'dev.jafarkhan+e2e-book-zoom@gmail.com';
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

const FAKE_PORT = 4599;
type Meeting = { topic: string; start_time: string; duration: number };
const meetings = new Map<string, Meeting>();
const calls: string[] = [];
let failCreates = false;
let nextId = 81000000001;

/** A stand-in for Zoom: sign-in, the user, and the three meeting calls. */
function startFakeZoom(): Promise<Server> {
	const server = createServer((req, res) => {
		const url = new URL(req.url ?? '/', `http://127.0.0.1:${FAKE_PORT}`);
		let raw = '';
		req.on('data', (chunk) => (raw += chunk));
		req.on('end', () => {
			const send = (status: number, data?: unknown) => {
				res.writeHead(status, { 'content-type': 'application/json' });
				res.end(data === undefined ? undefined : JSON.stringify(data));
			};
			if (url.pathname === '/oauth/authorize') {
				const back = new URL(url.searchParams.get('redirect_uri') ?? '');
				back.searchParams.set('code', 'fake-code');
				back.searchParams.set('state', url.searchParams.get('state') ?? '');
				res.writeHead(302, { location: back.toString() });
				return res.end();
			}
			if (url.pathname === '/oauth/token')
				return send(200, {
					access_token: `fake-access-${Date.now()}`,
					refresh_token: `fake-refresh-${Date.now()}`,
					expires_in: 3600
				});
			if (url.pathname === '/v2/users/me')
				return send(200, {
					id: 'fake-zoom-user',
					email: 'jafar.zoom@example.com',
					display_name: 'Jafar Zoom'
				});
			const meeting = url.pathname.match(/^\/v2\/meetings\/(\d+)$/);
			if (url.pathname === '/v2/users/me/meetings' && req.method === 'POST') {
				calls.push('POST create');
				if (failCreates) return send(500, { message: 'down' });
				const id = String(nextId++);
				meetings.set(id, JSON.parse(raw));
				return send(201, {
					id: Number(id),
					join_url: `https://zoom.example/j/${id}?pwd=e2e`,
					start_url: 'https://zoom.example/start/secret'
				});
			}
			if (meeting && req.method === 'PATCH') {
				calls.push(`PATCH ${meeting[1]}`);
				meetings.set(meeting[1], { ...meetings.get(meeting[1])!, ...JSON.parse(raw) });
				return send(204);
			}
			if (meeting && req.method === 'DELETE') {
				calls.push(`DELETE ${meeting[1]}`);
				meetings.delete(meeting[1]);
				return send(204);
			}
			send(404, {});
		});
	});
	return new Promise((done) => server.listen(FAKE_PORT, '127.0.0.1', () => done(server)));
}

test.describe.serial('a Zoom call whose meeting UCRM makes', () => {
	test.skip(
		!ownerEmail ||
			!ownerPassword ||
			!supabaseUrl ||
			!serviceKey ||
			(Boolean(turnstileSecret) && !turnstileSecret?.startsWith('1x')),
		'Set the owner login, the Supabase service key and the Turnstile test keys to run the Zoom check.'
	);

	let wasEnabled = true;
	let fake: Server;

	test.beforeAll(async () => {
		fake = await startFakeZoom();
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
		await database().from('platform_zoom_connection').delete().eq('id', true);
		if (!wasEnabled)
			await database()
				.from('platform_owner_settings')
				.update({ booking_enabled: false })
				.eq('id', true);
		await new Promise((done) => fake.close(done));
	});

	async function book(request: APIRequestContext, startsAt: string, name: string) {
		return request.post(`/api/public/book/${slug}`, {
			data: {
				starts_at: startsAt,
				name,
				email: visitorEmail,
				phone: '+880 1711 000011',
				business_name: 'E2E Zoom Plumbing',
				country_code: 'BD',
				trade: 'Plumbing',
				note: null,
				time_zone: 'Asia/Dhaka',
				turnstile_token: 'XXXX.DUMMY.TOKEN.XXXX'
			}
		});
	}

	test('connect, book, move, survive an outage, cancel', async ({ page }) => {
		test.setTimeout(120_000);
		const startedAt = new Date().toISOString();
		await signIn(page);
		const request = page.request;
		const settings = (await (await request.get('/api/jafar/booking')).json()) as {
			meeting_types: MeetingType[];
		};
		const type = settings.meeting_types.find((candidate) => candidate.slug === slug)!;
		expect(type, `the ${slug} meeting type`).toBeTruthy();
		const saved = await request.patch(`/api/jafar/booking/types/${type.id}`, {
			data: typeBody(type, { location_kind: 'zoom', video_link_mode: 'automatic' })
		});
		expect(saved.ok(), await saved.text()).toBe(true);

		try {
			// Connect through the stand-in's sign-in page and come back to Booking settings.
			await page.goto('/api/jafar/booking/zoom/connect');
			await page.waitForURL(/\/jafar\/settings\/booking/);
			await expect(page.getByText('jafar.zoom@example.com')).toBeVisible();
			await expect(page.getByText('Connected', { exact: true })).toBeVisible();
			const stored = await database().from('platform_zoom_connection').select('*').single();
			expect(JSON.stringify(stored.data)).not.toContain('fake-access');
			expect(JSON.stringify(stored.data)).not.toContain('fake-refresh');
			if (shots)
				for (const width of [1440, 390]) {
					await page.setViewportSize({ width, height: width === 390 ? 844 : 900 });
					await page.getByRole('heading', { name: 'Zoom', exact: true }).scrollIntoViewIfNeeded();
					await page.screenshot({ path: `${shots}/zoom-connected-${width}.png` });
				}
			await page.setViewportSize({ width: 1440, height: 900 });

			// A booking gets its own meeting, and the confirmation carries its link.
			const from = new Date(Date.now() + DAY).toISOString();
			const to = new Date(Date.now() + 44 * DAY).toISOString();
			const slots = await request.get(`/api/public/book/${slug}/slots`, { params: { from, to } });
			const starts = (await slots.json()) as string[];
			expect(starts.length).toBeGreaterThan(2);
			const first = await book(request, starts[starts.length - 1], 'E2E Zoom Visitor');
			expect(first.ok(), await first.text()).toBe(true);
			const call = ((await first.json()) as { call: { video_join_url: string } }).call;
			expect(call.video_join_url).toMatch(/^https:\/\/zoom\.example\/j\/\d+\?pwd=e2e$/);
			const meetingId = /\/j\/(\d+)/.exec(call.video_join_url)![1];
			expect(meetings.get(meetingId)).toMatchObject({ duration: type.duration_minutes });
			const confirmation = await emailsSince('booking_booked', startedAt);
			expect(confirmation).toHaveLength(1);
			expect(confirmation[0]).toContain(call.video_join_url);
			expect(JSON.stringify(confirmation)).not.toContain('start/secret');

			// Moving the call moves the meeting.
			const row = await database()
				.from('platform_bookings')
				.select('id, entry_id, relationship_id')
				.eq('visitor_email', visitorEmail)
				.single();
			if (row.error) throw row.error;
			const moveTo = new Date(starts[starts.length - 2]);
			const moved = await request.patch(`/api/jafar/calendar/entries/${row.data.entry_id}`, {
				data: {
					action: 'move',
					starts_at: moveTo.toISOString(),
					ends_at: new Date(moveTo.getTime() + Number(type.duration_minutes) * 60_000).toISOString()
				}
			});
			expect(moved.ok(), await moved.text()).toBe(true);
			expect(calls).toContain(`PATCH ${meetingId}`);
			expect(new Date(meetings.get(meetingId)!.start_time).getTime()).toBe(moveTo.getTime());

			// Cancelling deletes the meeting and takes the link off the booking.
			const cancelled = await request.patch(`/api/jafar/calendar/entries/${row.data.entry_id}`, {
				data: { action: 'close', outcome: 'cancelled' }
			});
			expect(cancelled.ok(), await cancelled.text()).toBe(true);
			expect(calls).toContain(`DELETE ${meetingId}`);
			expect(meetings.has(meetingId)).toBe(false);
			const after = await database()
				.from('platform_bookings')
				.select('video_join_url, video_provider_meeting_id')
				.eq('id', row.data.id)
				.single();
			expect(after.data).toEqual({ video_join_url: null, video_provider_meeting_id: null });

			// A Zoom outage never loses the booking: the visitor is told the link will follow.
			failCreates = true;
			const second = await book(request, starts[starts.length - 3], 'E2E Zoom Outage');
			expect(second.ok(), await second.text()).toBe(true);
			expect(((await second.json()) as { call: Record<string, unknown> }).call).toMatchObject({
				location_kind: 'zoom',
				video_join_url: null
			});
			const confirmations = await emailsSince('booking_booked', startedAt);
			expect(
				confirmations.filter((email) =>
					email.includes('We will email you the joining link before the call.')
				)
			).toHaveLength(1);
			failCreates = false;

			// Disconnecting keeps the booking and says so.
			await page.goto('/jafar/settings/booking', { waitUntil: 'networkidle' });
			await page.getByRole('button', { name: 'Disconnect' }).click();
			await page.getByRole('alertdialog').getByRole('button', { name: 'Disconnect' }).click();
			await expect(page.getByText('Not connected')).toBeVisible();
			const gone = await database().from('platform_zoom_connection').select('id');
			expect(gone.data).toHaveLength(0);
		} finally {
			const back = await request.patch(`/api/jafar/booking/types/${type.id}`, {
				data: typeBody(type)
			});
			expect(back.ok(), await back.text()).toBe(true);
		}
	});
});
