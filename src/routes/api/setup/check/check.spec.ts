import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { readSetupServiceKeys } from '$lib/server/setup/catalogue';
import { readSetupState, type SetupState } from '$lib/server/setup/read';
import type { SetupCatalogue } from '$lib/setup/catalogue';

// Client onboarding B13: Check and send to Uplift.

const CATALOGUE: SetupCatalogue = {
	versionId: 'version-7',
	sections: [
		{
			key: 'business',
			title: 'Your business',
			description: '',
			serviceKey: null,
			groups: [
				{
					title: '',
					hint: '',
					facts: [
						{
							key: 'business.name',
							label: 'Business name',
							kind: 'text',
							required: true,
							builtIn: true
						},
						{
							key: 'business.notes',
							label: 'Notes',
							kind: 'longtext',
							required: false,
							builtIn: false
						}
					]
				}
			]
		}
	]
};

vi.mock('$lib/server/setup/catalogue', () => ({
	readSetupCatalogue: vi.fn(async () => CATALOGUE),
	readSetupServiceKeys: vi.fn(async () => new Set<string>())
}));

vi.mock('$lib/server/setup/read', async () => {
	const actual =
		await vi.importActual<typeof import('$lib/server/setup/read')>('$lib/server/setup/read');
	return { ...actual, readSetupState: vi.fn() };
});

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

const mockedState = vi.mocked(readSetupState);

const ALL_CONFIRMATIONS = [
	'accurate',
	'use_materials',
	'permission',
	'build_and_launch',
	'imports'
];

function state(overrides: Partial<SetupState> = {}): SetupState {
	return {
		welcomeSeen: true,
		answers: { 'business.name': { availability: 'have', value: 'Raad Plumbing', note: null } },
		doneSections: new Set(['business']),
		sent: null,
		...overrides
	};
}

function supabase(options: { sentAnswers?: Record<string, unknown>; rpcData?: unknown } = {}) {
	const rpc = vi.fn().mockResolvedValue({
		data: options.rpcData ?? { status: 'sent', submission_number: 1, submitted_at: 'now' },
		error: null
	});
	const result = { data: { answers: options.sentAnswers ?? {} }, error: null };
	const chain = {
		select: () => chain,
		eq: () => chain,
		single: () => Promise.resolve(result),
		// C3c: nothing Uplift has answered.
		then: (resolve: (value: unknown) => unknown) =>
			Promise.resolve({ data: [], error: null }).then(resolve)
	};
	return { from: vi.fn(() => chain), rpc };
}

function event(client: ReturnType<typeof supabase>, body?: unknown) {
	return {
		locals: { supabase: client },
		request: new Request('http://localhost/api/setup/check', {
			method: 'POST',
			body: body === undefined ? undefined : JSON.stringify(body)
		})
	} as never;
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.mocked(requireOrganizationAdmin).mockResolvedValue({
		auth: {
			organization: { id: 'org-1', name: 'Raad Plumbing', role: 'owner' },
			user: { id: 'user-1', email: 'owner@example.com' }
		},
		access: { permissions: {}, features: {} }
	} as never);
	vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	mockedState.mockResolvedValue(state());
});

describe('GET /api/setup/check', () => {
	it('reads every task back with the confirmations for this package', async () => {
		vi.mocked(readSetupServiceKeys).mockResolvedValueOnce(new Set(['marketing']));
		const body = await (await GET(event(supabase()))).json();
		expect(body.can_send).toBe(true);
		expect(body.sections[0]).toMatchObject({ key: 'business', status: 'optional_skipped' });
		expect(body.confirmations.map((c: { key: string }) => c.key)).toContain('marketing_drafts');
		expect(body.sent).toBeNull();
	});
});

describe('POST /api/setup/check', () => {
	it('sends a snapshot of the answers asked, with the wording ticked and the version', async () => {
		const client = supabase();
		const response = await POST(
			event(client, { confirmed: ALL_CONFIRMATIONS, previous_number: 0 })
		);
		expect(response.status).toBe(201);
		expect(client.rpc).toHaveBeenCalledWith('submit_organization_setup', {
			target_organization_id: 'org-1',
			previous_number: 0,
			target_version_id: 'version-7',
			package_service_keys: [],
			fact_keys: ['business.name'],
			new_confirmations: expect.arrayContaining([
				{ key: 'accurate', wording: expect.stringContaining('accurate') }
			]),
			new_confirmations_version: expect.any(String)
		});
	});

	it('refuses while a task is not done, naming it', async () => {
		mockedState.mockResolvedValueOnce(state({ doneSections: new Set() }));
		const client = supabase();
		const response = await POST(
			event(client, { confirmed: ALL_CONFIRMATIONS, previous_number: 0 })
		);
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('Your business');
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses until every confirmation is ticked, saying which', async () => {
		const client = supabase();
		const response = await POST(event(client, { confirmed: ['accurate'], previous_number: 0 }));
		expect(response.status).toBe(422);
		expect(Object.keys((await response.json()).field_errors)).toEqual(
			ALL_CONFIRMATIONS.filter((key) => key !== 'accurate')
		);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('adds nothing for a page showing an older send — a double press or another device', async () => {
		mockedState.mockResolvedValueOnce(
			state({ sent: { number: 1, submitted_at: 'then', submitted_by_name: 'Sam' } })
		);
		const client = supabase();
		const response = await POST(
			event(client, { confirmed: ALL_CONFIRMATIONS, previous_number: 0 })
		);
		expect(response.status).toBe(409);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('answers 409 when the database finds a send got there first', async () => {
		const client = supabase({ rpcData: { status: 'stale', latest_number: 1 } });
		const response = await POST(
			event(client, { confirmed: ALL_CONFIRMATIONS, previous_number: 0 })
		);
		expect(response.status).toBe(409);
	});

	it('refuses to send again when nothing has changed', async () => {
		mockedState.mockResolvedValueOnce(
			state({ sent: { number: 1, submitted_at: 'then', submitted_by_name: 'Sam' } })
		);
		const client = supabase({
			sentAnswers: { 'business.name': { availability: 'have', value: 'Raad Plumbing', note: null } }
		});
		const response = await POST(
			event(client, { confirmed: ALL_CONFIRMATIONS, previous_number: 1 })
		);
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('sends a change after an earlier send', async () => {
		mockedState.mockResolvedValueOnce(
			state({ sent: { number: 1, submitted_at: 'then', submitted_by_name: 'Sam' } })
		);
		const client = supabase({
			sentAnswers: { 'business.name': { availability: 'have', value: 'Raad', note: null } }
		});
		const response = await POST(
			event(client, { confirmed: ALL_CONFIRMATIONS, previous_number: 1 })
		);
		expect(response.status).toBe(201);
		expect(client.rpc).toHaveBeenCalledWith(
			'submit_organization_setup',
			expect.objectContaining({ previous_number: 1 })
		);
	});
});
