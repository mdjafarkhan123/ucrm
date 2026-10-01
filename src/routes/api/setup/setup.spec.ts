import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getSummary } from './+server';
import { PATCH as patchAnswers } from './answers/+server';
import { POST as postWelcome } from './welcome/+server';
import { GET as getSection, PATCH as patchSection } from './sections/[section]/+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationAdmin: vi.fn() };
});

vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationAdmin);
const mockedRateLimit = vi.mocked(checkRateLimit);

const ORGANIZATION_ID = 'org-1';

type AnswerRow = { fact_key: string; availability: string; value: unknown; note: string | null };
type HoursRow = {
	weekday: number;
	period_index: number;
	is_open: boolean;
	is_open_24h: boolean;
	opens_at: string | null;
	closes_at: string | null;
};

// The three setup tables plus the two reads a section makes for suggestions. Every read is a chain ending
// in either `maybeSingle()` or an awaited `eq()`.
function supabase(options: {
	setup?: { welcome_seen_at: string | null } | null;
	answers?: AnswerRow[];
	sections?: string[];
	settings?: Record<string, string | null>;
	hours?: HoursRow[];
	profileName?: string | null;
}) {
	const rpc = vi.fn().mockResolvedValue({ data: { status: 'saved' }, error: null });
	const rows: Record<string, unknown> = {
		organization_setup: options.setup ?? null,
		organization_setup_answers: options.answers ?? [],
		organization_setup_sections: (options.sections ?? []).map((section_key) => ({ section_key })),
		organization_settings: options.settings ?? { trade: null, phone: null },
		organization_business_hours: options.hours ?? [],
		profiles: { full_name: options.profileName ?? null }
	};
	const from = vi.fn((table: string) => {
		const result = { data: rows[table], error: null };
		const chain = {
			select: () => chain,
			eq: () => chain,
			maybeSingle: () => Promise.resolve(result),
			then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve)
		};
		return chain;
	});
	return { from, rpc };
}

function event(client: ReturnType<typeof supabase>, body?: unknown, section = 'business') {
	return {
		locals: { supabase: client },
		params: { section },
		request: new Request('http://localhost/api/setup', {
			method: 'POST',
			body: body === undefined ? undefined : JSON.stringify(body)
		})
	} as never;
}

function admin() {
	return {
		auth: {
			organization: { id: ORGANIZATION_ID, name: 'Bright Spark Electrical', role: 'owner' },
			user: { id: 'user-1', email: 'owner@example.com' }
		},
		access: { permissions: {}, features: {} }
	} as never;
}

const have = (fact_key: string, value: string): AnswerRow => ({
	fact_key,
	availability: 'have',
	value,
	note: null
});

const WEEKDAYS_NINE_TO_FIVE = {
	mode: 'weekly',
	days: [0, 1, 2, 3, 4, 5, 6].map((weekday) =>
		weekday >= 1 && weekday <= 5
			? { open: true, all_day: false, periods: [['09:00', '17:00']] }
			: { open: false, all_day: false, periods: [] }
	)
};

// Every required question except the public phone and email, which the tests answer in different ways.
const REQUIRED = [
	have('business.public_name', 'Bright Spark Electrical'),
	have('business.trade', 'Electrical'),
	have('business.type', 'company'),
	have('business.contact_name', 'Sam Lee'),
	have('business.contact_email', 'sam@example.com'),
	have('business.contact_phone', '+44 20 7946 0958'),
	have('business.country', 'GB'),
	have('business.address_line1', '12 Mill Lane'),
	have('business.address_city', 'Leeds'),
	have('business.address_postal_code', 'LS1 4AB'),
	have('business.address_customers_visit', 'no'),
	have('business.address_public', 'no'),
	have('business.language', 'English'),
	have('business.timezone', 'Europe/London'),
	have('business.currency', 'GBP'),
	{ fact_key: 'business.hours', availability: 'have', value: WEEKDAYS_NINE_TO_FIVE, note: null }
];

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(admin());
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
});

describe('GET /api/setup', () => {
	it('refuses anyone who is not an owner or administrator', async () => {
		mockedRequire.mockResolvedValue({
			response: new Response(null, { status: 403 })
		} as never);
		const response = await getSummary(event(supabase({})));
		expect(response.status).toBe(403);
	});

	it('shows a brand-new organization as not started, with the welcome still to see', async () => {
		const body = await (await getSummary(event(supabase({})))).json();
		expect(body.welcome_seen).toBe(false);
		expect(body.progress).toEqual({ done: 0, total: 1 });
		expect(body.next).toMatchObject({ key: 'business', status: 'not_started' });
		expect(body.delivery.state).toBe('collecting');
	});

	it('shows half-filled setup as in progress so it can be resumed on another device', async () => {
		const client = supabase({
			setup: { welcome_seen_at: '2026-10-01T10:00:00Z' },
			answers: REQUIRED.slice(0, 3)
		});
		const body = await (await getSummary(event(client))).json();
		expect(body.welcome_seen).toBe(true);
		expect(body.sections[0]).toMatchObject({ status: 'in_progress', answered: 3 });
		expect(body.next).toMatchObject({ key: 'business', status: 'in_progress' });
	});

	it('counts a section as done only while its required answers are all still there', async () => {
		const helpWithPublic: AnswerRow[] = [
			{ fact_key: 'business.public_phone', availability: 'need_help', value: null, note: null },
			{ fact_key: 'business.public_email', availability: 'not_yet', value: null, note: null }
		];
		const complete = supabase({
			answers: [...REQUIRED, ...helpWithPublic],
			sections: ['business']
		});
		expect((await (await getSummary(event(complete))).json()).progress.done).toBe(1);

		const cleared = supabase({ answers: REQUIRED, sections: ['business'] });
		const body = await (await getSummary(event(cleared))).json();
		expect(body.progress.done).toBe(0);
		expect(body.sections[0].status).toBe('in_progress');
	});
});

describe('PATCH /api/setup/answers', () => {
	it('saves valid answers through the one command, trimmed', async () => {
		const client = supabase({});
		const response = await patchAnswers(
			event(client, {
				answers: [
					{ fact_key: 'business.public_name', availability: 'have', value: '  Bright Spark  ' },
					{ fact_key: 'business.public_phone', availability: 'need_help', note: ' No number yet ' }
				]
			})
		);
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('save_organization_setup_answers', {
			target_organization_id: ORGANIZATION_ID,
			new_answers: [
				{
					fact_key: 'business.public_name',
					availability: 'have',
					value: 'Bright Spark',
					note: null
				},
				{
					fact_key: 'business.public_phone',
					availability: 'need_help',
					value: null,
					note: 'No number yet'
				}
			]
		});
	});

	it('never stores a value alongside "need help", so help cannot pass as a finished answer', async () => {
		const client = supabase({});
		await patchAnswers(
			event(client, {
				answers: [{ fact_key: 'business.public_email', availability: 'need_help', value: 'x@y.co' }]
			})
		);
		expect(client.rpc.mock.calls[0][1].new_answers[0].value).toBeNull();
	});

	it('refuses an invalid value without touching the database, naming the field', async () => {
		const client = supabase({});
		const response = await patchAnswers(
			event(client, {
				answers: [{ fact_key: 'business.contact_email', availability: 'have', value: 'sam@' }]
			})
		);
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors['business.contact_email']).toBeTruthy();
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('stores opening hours and a holiday exception as real data, dates in order', async () => {
		const client = supabase({});
		const exceptions = [
			{ date: '2026-12-26', name: ' Boxing Day ', closed: true },
			{ date: '2026-12-24', name: 'Christmas Eve', closed: false, opens: '09:00', closes: '13:00' }
		];
		const response = await patchAnswers(
			event(client, {
				answers: [
					{
						fact_key: 'business.hours',
						availability: 'have',
						value: JSON.stringify(WEEKDAYS_NINE_TO_FIVE)
					},
					{
						fact_key: 'business.hours_exceptions',
						availability: 'have',
						value: JSON.stringify(exceptions)
					}
				]
			})
		);
		expect(response.status).toBe(200);
		const [hours, saved] = client.rpc.mock.calls[0][1].new_answers;
		expect(hours.value).toEqual(WEEKDAYS_NINE_TO_FIVE);
		expect(saved.value).toEqual([
			{ date: '2026-12-24', name: 'Christmas Eve', closed: false, opens: '09:00', closes: '13:00' },
			{ date: '2026-12-26', name: 'Boxing Day', closed: true, opens: null, closes: null }
		]);
	});

	it('refuses hours with no open day, and a holiday listed twice', async () => {
		const client = supabase({});
		const closed = { open: false, all_day: false, periods: [] };
		const response = await patchAnswers(
			event(client, {
				answers: [
					{
						fact_key: 'business.hours',
						availability: 'have',
						value: JSON.stringify({ mode: 'weekly', days: Array(7).fill(closed) })
					},
					{
						fact_key: 'business.hours_exceptions',
						availability: 'have',
						value: JSON.stringify([
							{ date: '2026-12-25', name: 'Christmas Day', closed: true },
							{ date: '2026-12-25', name: 'Again', closed: true }
						])
					}
				]
			})
		);
		expect(response.status).toBe(422);
		const errors = (await response.json()).field_errors;
		expect(errors['business.hours']).toMatch(/at least one day/);
		expect(errors['business.hours_exceptions']).toMatch(/same date/);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses a time zone or country that is not a real one', async () => {
		const client = supabase({});
		const response = await patchAnswers(
			event(client, {
				answers: [
					{ fact_key: 'business.timezone', availability: 'have', value: 'Mars/Olympus' },
					{ fact_key: 'business.country', availability: 'have', value: 'England' }
				]
			})
		);
		expect(response.status).toBe(422);
		expect(Object.keys((await response.json()).field_errors).sort()).toEqual([
			'business.country',
			'business.timezone'
		]);
	});

	it('refuses a question that is not part of setup', async () => {
		const client = supabase({});
		const response = await patchAnswers(
			event(client, {
				answers: [{ fact_key: 'google.password', availability: 'have', value: 'hunter2' }]
			})
		);
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses "I don\'t have this yet" on a question that must be answered', async () => {
		const client = supabase({});
		const response = await patchAnswers(
			event(client, { answers: [{ fact_key: 'business.public_name', availability: 'not_yet' }] })
		);
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('clears an answer when asked to', async () => {
		const client = supabase({});
		await patchAnswers(
			event(client, { answers: [{ fact_key: 'business.legal_name', availability: null }] })
		);
		expect(client.rpc.mock.calls[0][1].new_answers).toEqual([
			{ fact_key: 'business.legal_name', availability: null, value: null, note: null }
		]);
	});

	it('stops when the organization is saving too fast', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const client = supabase({});
		const response = await patchAnswers(
			event(client, {
				answers: [{ fact_key: 'business.public_name', availability: 'have', value: 'A' }]
			})
		);
		expect(response.status).toBe(429);
		expect(client.rpc).not.toHaveBeenCalled();
	});
});

describe('GET /api/setup/sections/[section]', () => {
	it('offers what the CRM already knows only for questions nobody has answered', async () => {
		const client = supabase({
			answers: [have('business.public_name', 'Sparky & Sons')],
			settings: { trade: 'Electrical', phone: 'not a number' },
			profileName: 'Sam Lee'
		});
		const body = await (await getSection(event(client))).json();
		expect(body.answers['business.public_name'].value).toBe('Sparky & Sons');
		expect(body.suggestions).toEqual({
			'business.trade': 'Electrical',
			'business.contact_name': 'Sam Lee',
			'business.contact_email': 'owner@example.com'
		});
		expect(body.status).toBe('in_progress');
	});

	it('gives saved hours back as text the page can load, holiday exception included', async () => {
		const exceptions = [
			{ date: '2026-12-25', name: 'Christmas Day', closed: true, opens: null, closes: null }
		];
		const client = supabase({
			answers: [
				...REQUIRED,
				{
					fact_key: 'business.hours_exceptions',
					availability: 'have',
					value: exceptions,
					note: null
				}
			]
		});
		const body = await (await getSection(event(client))).json();
		expect(JSON.parse(body.answers['business.hours'].value)).toEqual(WEEKDAYS_NINE_TO_FIVE);
		expect(JSON.parse(body.answers['business.hours_exceptions'].value)).toEqual(exceptions);
	});

	it("offers the address and hours already in Settings, and the country's currency", async () => {
		const client = supabase({
			settings: {
				trade: null,
				phone: null,
				address_line1: '12 Mill Lane',
				city: 'Leeds',
				postal_code: 'LS1 4AB',
				country_code: 'GB',
				timezone: 'UTC',
				timezone_confirmed_at: null,
				currency_code: 'USD',
				currency_confirmed_at: null,
				hours_mode: 'weekly'
			},
			hours: [
				{
					weekday: 1,
					period_index: 0,
					is_open: true,
					is_open_24h: false,
					opens_at: '08:00:00',
					closes_at: '16:30:00'
				}
			]
		});
		const { suggestions } = await (await getSection(event(client))).json();
		expect(suggestions).toMatchObject({
			'business.country': 'GB',
			'business.address_line1': '12 Mill Lane',
			'business.address_city': 'Leeds',
			'business.address_postal_code': 'LS1 4AB',
			'business.currency': 'GBP'
		});
		// The account's unconfirmed default time zone is not something the business said.
		expect(suggestions['business.timezone']).toBeUndefined();
		const hours = JSON.parse(suggestions['business.hours']);
		expect(hours.days[1]).toEqual({ open: true, all_day: false, periods: [['08:00', '16:30']] });
		expect(hours.days[0].open).toBe(false);
	});

	it('answers 404 for a section that does not exist', async () => {
		const response = await getSection(event(supabase({}), undefined, 'nonsense'));
		expect(response.status).toBe(404);
	});
});

describe('PATCH /api/setup/sections/[section]', () => {
	it('will not mark a section done while a required question has no answer, and says which', async () => {
		const client = supabase({ answers: REQUIRED });
		const response = await patchSection(event(client, { done: true }));
		expect(response.status).toBe(422);
		expect(Object.keys((await response.json()).field_errors).sort()).toEqual([
			'business.public_email',
			'business.public_phone'
		]);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('marks it done once every required question has an answer, help requests included', async () => {
		const client = supabase({
			answers: [
				...REQUIRED,
				{ fact_key: 'business.public_phone', availability: 'need_help', value: null, note: null },
				have('business.public_email', 'hello@example.com')
			]
		});
		const response = await patchSection(event(client, { done: true }));
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('set_organization_setup_section_done', {
			target_organization_id: ORGANIZATION_ID,
			target_section_key: 'business',
			is_done: true
		});
	});

	it('reopens a section without checking its answers', async () => {
		const client = supabase({});
		const response = await patchSection(event(client, { done: false }));
		expect(response.status).toBe(200);
		expect(client.rpc.mock.calls[0][1].is_done).toBe(false);
	});
});

describe('POST /api/setup/welcome', () => {
	it('records that the welcome was shown', async () => {
		const client = supabase({});
		const response = await postWelcome(event(client));
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('mark_organization_setup_welcome_seen', {
			target_organization_id: ORGANIZATION_ID
		});
	});
});
