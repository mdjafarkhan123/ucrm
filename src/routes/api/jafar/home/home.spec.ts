import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSetupCataloguesInUse } from '$lib/server/setup/catalogue';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/setup/catalogue', () => ({ readSetupCataloguesInUse: vi.fn() }));
vi.mock('$lib/setup/onboarding-list', () => ({ onboardingCatalogues: () => ({}) }));

const mockedSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedCatalogue = vi.mocked(readSetupCataloguesInUse);

const CORE = {
	review: 2,
	first_contact: 1,
	accounts_to_create: 0,
	overdue: 1,
	today: 0,
	upcoming: 0,
	items: [{ id: 'lead-1', due_on: '2026-10-06' }]
};

function call(today: string | null, everyone = false) {
	const url = new URL('http://localhost/api/jafar/home');
	if (today !== null) url.searchParams.set('today', today);
	if (everyone) url.searchParams.set('everyone', '1');
	return GET({ url } as unknown as Parameters<typeof GET>[0]);
}

function client(rpcs: Record<string, { data?: unknown; error?: unknown }>) {
	const rpc = vi.fn(async (name: string) => rpcs[name] ?? { data: null, error: new Error(name) });
	mockedClient.mockReturnValue({ rpc } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.spyOn(console, 'error').mockImplementation(() => {});
	mockedSession.mockResolvedValue({
		email: 'owner@example.com',
		role: null,
		access: null,
		memberId: null
	} as Awaited<ReturnType<typeof getOwnerSession>>);
	mockedCatalogue.mockResolvedValue(
		new Map() as Awaited<ReturnType<typeof readSetupCataloguesInUse>>
	);
});

describe('GET /api/jafar/home', () => {
	it('refuses someone who is not signed in', async () => {
		mockedSession.mockResolvedValue(null);
		expect((await call('2026-10-07')).status).toBe(401);
	});

	it('refuses a missing or malformed date before touching the database', async () => {
		const rpc = client({});
		expect((await call(null)).status).toBe(422);
		expect((await call('07/10/2026')).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it("asks for Jafar's own day and adds the onboarding and renewal counts", async () => {
		const rpc = client({
			owner_business_home: { data: CORE, error: null },
			owner_client_onboarding_list: { data: { totals: { uplift: 3 } }, error: null },
			owner_organization_directory: {
				data: { totals: { attention: { renewal_due: 2, payment_overdue: 1 } } },
				error: null
			}
		});
		const response = await call('2026-10-07');
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ...CORE, setups_waiting: 3, renewals: 3 });
		expect(rpc).toHaveBeenCalledWith('owner_business_home', {
			today_date: '2026-10-07',
			agenda_limit: 60,
			viewer_member_id: undefined,
			everyone: false
		});
		expect(rpc).toHaveBeenCalledWith(
			'owner_client_onboarding_list',
			expect.objectContaining({ waiting_filter: 'uplift', page_size: 1 })
		);
	});

	it("shows Jafar the whole team's to-dos when he asks (D3b)", async () => {
		const rpc = client({ owner_business_home: { data: CORE, error: null } });
		await call('2026-10-07', true);
		expect(rpc).toHaveBeenCalledWith(
			'owner_business_home',
			expect.objectContaining({ viewer_member_id: undefined, everyone: true })
		);
	});

	it('gives a Sales teammate their own to-dos and only the counts they can open (D3b)', async () => {
		mockedSession.mockResolvedValue({
			email: 'sam@example.com',
			role: 'sales',
			access: null,
			memberId: 'member-sam'
		} as Awaited<ReturnType<typeof getOwnerSession>>);
		const rpc = client({ owner_business_home: { data: CORE, error: null } });
		// A teammate cannot ask for everyone's.
		const body = await (await call('2026-10-07', true)).json();
		expect(rpc).toHaveBeenCalledWith(
			'owner_business_home',
			expect.objectContaining({ viewer_member_id: 'member-sam', everyone: false })
		);
		// Sales opens Leads (their first contacts) but cannot approve, make accounts, or see onboarding and renewals.
		expect(body.first_contact).toBe(1);
		expect(body.review).toBeNull();
		expect(body.accounts_to_create).toBeNull();
		expect(body.setups_waiting).toBeNull();
		expect(body.renewals).toBeNull();
		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('still loads the day when a side count fails, showing that count as unknown', async () => {
		client({
			owner_business_home: { data: CORE, error: null },
			owner_organization_directory: { data: null, error: new Error('down') }
		});
		mockedCatalogue.mockResolvedValue(null);
		const body = await (await call('2026-10-07')).json();
		expect(body.setups_waiting).toBeNull();
		expect(body.renewals).toBeNull();
		expect(body.review).toBe(2);
	});

	it('fails plainly when the to-do list itself cannot be read', async () => {
		client({ owner_business_home: { data: null, error: new Error('down') } });
		const response = await call('2026-10-07');
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Your day could not be loaded.' });
	});
});
