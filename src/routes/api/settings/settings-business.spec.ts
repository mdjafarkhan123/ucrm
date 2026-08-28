import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getSettingsHome } from './+server';
import { GET as getBusiness } from './business/+server';
import { PATCH as patchProfile } from './business/profile/+server';
import { PATCH as patchHours } from './business/hours/+server';
import { PATCH as patchBranding } from './branding/+server';
import { POST as presignLogo } from './branding/logo-upload/+server';
import { PUT as commitLogo, DELETE as removeLogo } from './branding/logo/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { createPresignedUploadUrl, deleteObject, headObject } from '$lib/server/storage/r2';
import { forgetOrganizationTimezone } from '$lib/server/requests/timezone';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

vi.mock('$lib/server/requests/timezone', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/requests/timezone')>(
		'$lib/server/requests/timezone'
	);
	return { ...actual, forgetOrganizationTimezone: vi.fn() };
});

vi.mock('$lib/server/storage/r2', () => ({
	buildOrganizationLogoObjectKey: (organizationId: string, fileName: string) =>
		`${organizationId}/logo/fixed-uuid-${fileName}`,
	createPresignedUploadUrl: vi.fn(),
	headObject: vi.fn(),
	deleteObject: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedRateLimit = vi.mocked(checkRateLimit);
const mockedPresign = vi.mocked(createPresignedUploadUrl);
const mockedHead = vi.mocked(headObject);
const mockedDelete = vi.mocked(deleteObject);
const mockedForgetTimezone = vi.mocked(forgetOrganizationTimezone);

const ORGANIZATION_ID = 'org-1';

function context(permissions: Record<string, boolean>, features: Record<string, boolean> = {}) {
	return {
		auth: {
			organization: { id: ORGANIZATION_ID, name: 'Bright Spark Electrical', role: 'owner' },
			user: { id: 'user-1', email: 'owner@example.com' }
		},
		access: { permissions, features }
	} as never;
}

// Monday split into two, Tuesday running past midnight, Wednesday all day, the rest closed.
const savedPeriods = [
	{
		weekday: 0,
		period_index: 0,
		is_open: false,
		is_open_24h: false,
		opens_at: null,
		closes_at: null
	},
	{
		weekday: 1,
		period_index: 0,
		is_open: true,
		is_open_24h: false,
		opens_at: '08:00',
		closes_at: '12:00'
	},
	{
		weekday: 1,
		period_index: 1,
		is_open: true,
		is_open_24h: false,
		opens_at: '13:00',
		closes_at: '17:00'
	},
	{
		weekday: 2,
		period_index: 0,
		is_open: true,
		is_open_24h: false,
		opens_at: '22:00',
		closes_at: '02:00'
	},
	{
		weekday: 3,
		period_index: 0,
		is_open: true,
		is_open_24h: true,
		opens_at: null,
		closes_at: null
	},
	{
		weekday: 4,
		period_index: 0,
		is_open: false,
		is_open_24h: false,
		opens_at: null,
		closes_at: null
	},
	{
		weekday: 5,
		period_index: 0,
		is_open: false,
		is_open_24h: false,
		opens_at: null,
		closes_at: null
	},
	{
		weekday: 6,
		period_index: 0,
		is_open: false,
		is_open_24h: false,
		opens_at: null,
		closes_at: null
	}
];

const savedSettings = {
	trade: 'Electrical',
	phone: '555-0100' as string | null,
	website: 'brightspark.example',
	description: 'Domestic and commercial electricians.',
	address_line1: '12 Mill Lane' as string | null,
	address_line2: null,
	city: 'Leeds' as string | null,
	region: 'West Yorkshire',
	postal_code: 'LS1 1AA',
	country_code: 'GB' as string | null,
	address_is_public: false,
	timezone: 'Europe/London',
	locale: 'en-GB',
	currency_code: 'GBP',
	timezone_confirmed_at: '2026-08-20T09:00:00Z' as string | null,
	currency_confirmed_at: '2026-08-20T09:00:00Z' as string | null,
	brand_color: '#2F6FED',
	logo_object_key: null as string | null,
	hours_mode: 'weekly',
	profile_revision: 4,
	branding_revision: 2,
	hours_revision: 3,
	profile_updated_at: '2026-08-21T10:00:00Z',
	branding_updated_at: null as string | null,
	hours_updated_at: '2026-08-19T08:00:00Z',
	profile_updated_by: 'user-9',
	branding_updated_by: null as string | null,
	hours_updated_by: 'user-9'
};

type ReadOptions = {
	logoObjectKey?: string | null;
	currencyLocked?: boolean;
	settings?: Partial<typeof savedSettings>;
	periods?: typeof savedPeriods;
};

// The read fans out over three tables and one function at once, so the fake answers by table name rather
// than by call order. The builder is awaitable so a chain ending in `.order()` resolves like the real one.
function readEvent(options: ReadOptions = {}) {
	const settings = {
		...savedSettings,
		...options.settings,
		logo_object_key: options.logoObjectKey ?? null
	};
	const rpc = vi.fn(() => Promise.resolve({ data: options.currencyLocked ?? false, error: null }));

	const from = vi.fn((table: string) => {
		const single =
			table === 'organization_settings'
				? settings
				: table === 'profiles'
					? { full_name: 'Sam Rivers' }
					: null;
		const list =
			table === 'profiles'
				? [{ id: 'user-9', full_name: 'Dana Admin' }]
				: (options.periods ?? savedPeriods);

		const builder: Record<string, unknown> = {
			select: () => builder,
			eq: () => builder,
			order: () => builder,
			in: () => Promise.resolve({ data: list, error: null }),
			maybeSingle: () => Promise.resolve({ data: single, error: null }),
			then: (resolve: (value: unknown) => unknown) =>
				Promise.resolve({ data: list, error: null }).then(resolve)
		};
		return builder;
	});

	return {
		request: new Request('http://localhost/api/settings/business'),
		locals: { supabase: { from, rpc } }
	} as unknown as Parameters<typeof getBusiness>[0] & Parameters<typeof getSettingsHome>[0];
}

function writeEvent(
	body: unknown,
	rpcResult: unknown = { data: { status: 'saved' }, error: null }
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		request: new Request('http://localhost/api/settings/business', {
			method: 'POST',
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
		// Several routes share this fake event and each one's generated type names its own route id, so
		// the shape is handed over untyped rather than pretending to be one of them.
	} as unknown as Parameters<typeof patchProfile>[0] &
		Parameters<typeof patchHours>[0] &
		Parameters<typeof patchBranding>[0] &
		Parameters<typeof presignLogo>[0] &
		Parameters<typeof commitLogo>[0] &
		Parameters<typeof removeLogo>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const validProfile = {
	expected_revision: 4,
	name: 'Bright Spark Electrical',
	trade: 'Electrical',
	phone: '555-0100',
	website: 'brightspark.example',
	description: '',
	address_line1: '12 Mill Lane',
	address_line2: '',
	city: 'Leeds',
	region: 'West Yorkshire',
	postal_code: 'LS1 1AA',
	country_code: 'gb',
	address_is_public: false,
	timezone: 'Europe/London',
	currency_code: 'gbp',
	confirm_timezone: true,
	confirm_currency: true
};

const closedDay = (weekday: number) => ({
	weekday,
	period_index: 0,
	is_open: false,
	is_open_24h: false,
	opens_at: null,
	closes_at: null
});

const wholeWeekClosed = [0, 1, 2, 3, 4, 5, 6].map(closedDay);

const stale = {
	data: { status: 'stale', editor_name: 'Dana Admin', edited_at: '2026-08-22T07:30:00Z' },
	error: null
};

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(
		context({ 'settings.business.view': true, 'settings.business.edit': true })
	);
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
});

describe('reading business settings', () => {
	it('never hands the storage key to the browser, only the stable URL', async () => {
		const response = await getBusiness(readEvent({ logoObjectKey: 'org-1/logo/abc.png' }));
		const body = await response.json();

		expect(body.branding.logo_url).toBe('/api/settings/branding/logo/view?v=2');
		expect(JSON.stringify(body)).not.toContain('org-1/logo/abc.png');
	});

	it('reports no logo rather than a URL that would 404', async () => {
		const body = await (await getBusiness(readEvent())).json();
		expect(body.branding.logo_url).toBeNull();
	});

	it('gives each section its own revision so the pages do not collide', async () => {
		const body = await (await getBusiness(readEvent())).json();

		expect(body.profile.revision).toBe(4);
		expect(body.branding.revision).toBe(2);
		expect(body.hours.revision).toBe(3);
	});

	it('names who last changed each section, and says nobody when nobody has', async () => {
		const body = await (await getBusiness(readEvent())).json();

		expect(body.profile.last_editor).toEqual({ name: 'Dana Admin', at: '2026-08-21T10:00:00Z' });
		expect(body.branding.last_editor).toBeNull();
	});

	it('returns split, overnight, and all-day periods as they were saved', async () => {
		const body = await (await getBusiness(readEvent())).json();

		expect(body.hours.mode).toBe('weekly');
		expect(body.hours.periods).toHaveLength(8);
		expect(body.hours.periods[3]).toMatchObject({ opens_at: '22:00', closes_at: '02:00' });
		expect(body.hours.periods[4]).toMatchObject({ is_open_24h: true, opens_at: null });
	});

	it('calls the profile complete on name, timezone, and currency alone', async () => {
		const body = await (
			await getBusiness(
				readEvent({
					settings: { phone: null, address_line1: null, city: null, country_code: null }
				})
			)
		).json();

		expect(body.readiness.profile).toEqual({ complete: true, missing: [] });
	});

	it('counts an unconfirmed timezone or currency as missing', async () => {
		const body = await (
			await getBusiness(
				readEvent({ settings: { timezone_confirmed_at: null, currency_confirmed_at: null } })
			)
		).json();

		expect(body.readiness.profile).toEqual({
			complete: false,
			missing: ['timezone', 'currency']
		});
	});

	it('tells the page currency is locked once a quote has gone out', async () => {
		const body = await (await getBusiness(readEvent({ currencyLocked: true }))).json();
		expect(body.currency_locked).toBe(true);
	});

	it('does not call currency missing once it is locked, even if nobody ever confirmed it', async () => {
		const body = await (
			await getBusiness(
				readEvent({ currencyLocked: true, settings: { currency_confirmed_at: null } })
			)
		).json();

		expect(body.readiness.profile).toEqual({ complete: true, missing: [] });
	});

	it('marks a viewer without the edit permission as read-only', async () => {
		mockedRequire.mockResolvedValue(context({ 'settings.business.view': true }));
		const body = await (await getBusiness(readEvent())).json();

		expect(body.permissions).toEqual({ view: true, edit: false });
	});

	it('keeps the answer out of any shared cache', async () => {
		const response = await getBusiness(readEvent());
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});
});

describe('the settings home', () => {
	it('says hours are not set until somebody chooses how the week works', async () => {
		const body = await (
			await getSettingsHome(readEvent({ settings: { hours_mode: 'not_configured' } }))
		).json();

		expect(body.readiness.business_hours_set).toBe(false);
	});

	it('treats appointment only as a configured week', async () => {
		const body = await (
			await getSettingsHome(readEvent({ settings: { hours_mode: 'appointment_only' } }))
		).json();

		expect(body.readiness.business_hours_set).toBe(true);
	});

	it('tells the page whether this person may change anything', async () => {
		mockedRequire.mockResolvedValue(context({ 'settings.business.view': true }));
		const body = await (await getSettingsHome(readEvent())).json();

		expect(body.permissions).toEqual({
			business_edit: false,
			team_manage: false,
			communications_manage: false,
			snippets_manage: false,
			taxes_manage: false,
			price_book_manage: false,
			quotes_manage: false
		});
	});

	it('only exposes Team management when the actor has that permission', async () => {
		mockedRequire.mockResolvedValue(
			context({ 'settings.business.view': true, 'team.manage': true }, { 'core.team': true })
		);
		const body = await (await getSettingsHome(readEvent())).json();

		expect(body.permissions.team_manage).toBe(true);
	});

	it('does not call currency missing once it is locked, even if nobody ever confirmed it', async () => {
		const body = await (
			await getSettingsHome(
				readEvent({ currencyLocked: true, settings: { currency_confirmed_at: null } })
			)
		).json();

		expect(body.readiness.business_profile).toEqual({ complete: true, missing: [] });
	});
});

describe('saving the business profile', () => {
	it('refuses to run at all without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await patchProfile(writeEvent(validProfile));

		expect(response.status).toBe(403);
	});

	it('sends only profile fields with the revision the person started from', async () => {
		const event = writeEvent(validProfile);
		await patchProfile(event);

		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('save_organization_business_profile');
		expect(args).toMatchObject({
			expected_revision: 4,
			new_country_code: 'GB',
			new_currency_code: 'GBP',
			confirm_timezone: true,
			confirm_currency: true
		});
		expect(args).not.toHaveProperty('new_hours');
		expect(args).not.toHaveProperty('new_brand_color');
	});

	it('treats an emptied box as cleared rather than as an empty string', async () => {
		const event = writeEvent(validProfile);
		await patchProfile(event);

		const [, args] = event.__rpc.mock.calls[0];
		expect(args.new_description).toBeNull();
		expect(args.new_address_line2).toBeNull();
	});

	it('turns a stale save into a conflict that names the other person', async () => {
		const response = await patchProfile(writeEvent(validProfile, stale));
		const body = await response.json();

		expect(response.status).toBe(409);
		expect(body).toMatchObject({
			reason: 'stale',
			editor_name: 'Dana Admin',
			edited_at: '2026-08-22T07:30:00Z'
		});
	});

	it('passes the refusal sentence through when the database says currency is locked', async () => {
		const response = await patchProfile(
			writeEvent(validProfile, {
				data: null,
				error: { code: '23514', message: 'Currency cannot change once a Quote has been sent.' }
			})
		);
		const body = await response.json();

		expect(response.status).toBe(422);
		expect(body.field_errors.form).toContain('Currency cannot change');
	});

	it('waits its turn when the organization is saving too often', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const response = await patchProfile(writeEvent(validProfile));

		expect(response.status).toBe(429);
	});

	it('drops the cached timezone and currency the rest of the app formats with', async () => {
		await patchProfile(writeEvent(validProfile));
		expect(mockedForgetTimezone).toHaveBeenCalledWith(ORGANIZATION_ID);
	});

	it('leaves that cache alone when the save did not go through', async () => {
		await patchProfile(writeEvent(validProfile, stale));
		expect(mockedForgetTimezone).not.toHaveBeenCalled();
	});
});

describe('saving business hours', () => {
	it('sends the week as periods when hours are weekly', async () => {
		const event = writeEvent({ expected_revision: 3, mode: 'weekly', periods: savedPeriods });
		const response = await patchHours(event);

		expect(response.status).toBe(200);
		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('save_organization_business_hours');
		expect(args.new_mode).toBe('weekly');
		expect(args.new_hours).toHaveLength(8);
	});

	it('sends no grid at all for appointment only', async () => {
		const event = writeEvent({ expected_revision: 3, mode: 'appointment_only', periods: [] });
		await patchHours(event);

		const [, args] = event.__rpc.mock.calls[0];
		expect(args.new_hours).toBeNull();
	});

	it('refuses a week that does not cover every day', async () => {
		const response = await patchHours(
			writeEvent({ expected_revision: 3, mode: 'weekly', periods: wholeWeekClosed.slice(0, 6) })
		);

		expect(response.status).toBe(422);
	});

	it('refuses a day marked open 24 hours that also carries times', async () => {
		const response = await patchHours(
			writeEvent({
				expected_revision: 3,
				mode: 'weekly',
				periods: [
					{ ...closedDay(0), is_open: true, is_open_24h: true, opens_at: '08:00' },
					...wholeWeekClosed.slice(1)
				]
			})
		);

		expect(response.status).toBe(422);
	});

	it('refuses a closed day that carries times', async () => {
		const response = await patchHours(
			writeEvent({
				expected_revision: 3,
				mode: 'weekly',
				periods: [
					{ ...closedDay(0), opens_at: '08:00', closes_at: '17:00' },
					...wholeWeekClosed.slice(1)
				]
			})
		);

		expect(response.status).toBe(422);
	});

	it('refuses a fourth period on one day', async () => {
		const response = await patchHours(
			writeEvent({
				expected_revision: 3,
				mode: 'weekly',
				periods: [
					{
						...closedDay(0),
						period_index: 3,
						is_open: true,
						opens_at: '08:00',
						closes_at: '09:00'
					},
					...wholeWeekClosed.slice(1)
				]
			})
		);

		expect(response.status).toBe(422);
	});

	it('refuses unconfigured as something to save', async () => {
		const response = await patchHours(
			writeEvent({ expected_revision: 3, mode: 'not_configured', periods: [] })
		);

		expect(response.status).toBe(422);
	});

	it('conflicts on its own revision, not the profile one', async () => {
		const response = await patchHours(
			writeEvent({ expected_revision: 3, mode: 'appointment_only', periods: [] }, stale)
		);

		expect(response.status).toBe(409);
	});
});

describe('saving branding', () => {
	it('saves the brand color on the branding revision', async () => {
		const event = writeEvent({ expected_revision: 2, brand_color: '#2F6FED' });
		await patchBranding(event);

		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('save_organization_branding');
		expect(args).toMatchObject({ expected_revision: 2, new_brand_color: '#2F6FED' });
	});

	it('clears the brand color when the box is emptied', async () => {
		const event = writeEvent({ expected_revision: 2, brand_color: '' });
		await patchBranding(event);

		expect(event.__rpc.mock.calls[0][1].new_brand_color).toBeNull();
	});

	it('refuses something that is not a color', async () => {
		const response = await patchBranding(
			writeEvent({ expected_revision: 2, brand_color: 'blue-ish' })
		);

		expect(response.status).toBe(422);
	});
});

describe('logo upload', () => {
	it('issues a key under this organization and nobody else', async () => {
		mockedPresign.mockResolvedValue('https://storage.example/put');
		const response = await presignLogo(
			writeEvent({ file_name: 'logo.png', mime_type: 'image/png', size_bytes: 1024 })
		);
		const body = await response.json();

		expect(body.object_key.startsWith(`${ORGANIZATION_ID}/logo/`)).toBe(true);
	});

	it('turns away a file type the browser would not render as a picture', async () => {
		const response = await presignLogo(
			writeEvent({ file_name: 'logo.svg', mime_type: 'image/svg+xml', size_bytes: 1024 })
		);

		expect(response.status).toBe(422);
		expect(mockedPresign).not.toHaveBeenCalled();
	});

	it('turns away a file over the size limit before signing anything', async () => {
		const response = await presignLogo(
			writeEvent({ file_name: 'logo.png', mime_type: 'image/png', size_bytes: 5 * 1024 * 1024 })
		);

		expect(response.status).toBe(422);
		expect(mockedPresign).not.toHaveBeenCalled();
	});
});

describe('committing and removing the logo', () => {
	it('refuses a key belonging to another organization', async () => {
		const response = await commitLogo(writeEvent({ object_key: 'org-2/logo/theirs.png' }));

		expect(response.status).toBe(422);
		expect(mockedHead).not.toHaveBeenCalled();
	});

	it('refuses bytes that arrived as something other than an image', async () => {
		mockedHead.mockResolvedValue({ contentType: 'application/pdf', contentLength: 1024 } as never);
		const response = await commitLogo(writeEvent({ object_key: 'org-1/logo/new.png' }));

		expect(response.status).toBe(422);
		expect(mockedDelete).toHaveBeenCalledWith('org-1/logo/new.png');
	});

	it('refuses bytes that arrived larger than the limit', async () => {
		mockedHead.mockResolvedValue({
			contentType: 'image/png',
			contentLength: 5 * 1024 * 1024
		} as never);
		const response = await commitLogo(writeEvent({ object_key: 'org-1/logo/big.png' }));

		expect(response.status).toBe(422);
	});

	it('keeps the replaced image instead of deleting it out from under a sent document', async () => {
		mockedHead.mockResolvedValue({ contentType: 'image/png', contentLength: 2048 } as never);
		const response = await commitLogo(
			writeEvent(
				{ object_key: 'org-1/logo/new.png' },
				{
					data: {
						status: 'saved',
						branding_revision: 6,
						previous_object_key: 'org-1/logo/old.png'
					},
					error: null
				}
			)
		);
		const body = await response.json();

		expect(body.logo_url).toBe('/api/settings/branding/logo/view?v=6');
		expect(mockedDelete).not.toHaveBeenCalled();
	});

	it('removes the logo without touching the object behind it', async () => {
		const response = await removeLogo(
			writeEvent(undefined, {
				data: { status: 'saved', branding_revision: 7, previous_object_key: 'org-1/logo/old.png' },
				error: null
			})
		);
		const body = await response.json();

		expect(body).toEqual({ branding_revision: 7, logo_url: null });
		expect(mockedDelete).not.toHaveBeenCalled();
	});

	it('refuses to remove anything without the edit permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await removeLogo(writeEvent(undefined));

		expect(response.status).toBe(403);
	});

	it('rate-limits the logo writes the same way the other saves are limited', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 15 });

		expect((await commitLogo(writeEvent({ object_key: 'org-1/logo/new.png' }))).status).toBe(429);
		expect((await removeLogo(writeEvent(undefined))).status).toBe(429);
	});
});
