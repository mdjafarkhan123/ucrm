import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { searchCoreRecords } from '$lib/server/search/core-records';
import { searchConversations } from '$lib/server/search/conversations';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/organization', () => ({ getOrganizationContext: vi.fn() }));
vi.mock('$lib/server/access/effective', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/effective')>(
		'$lib/server/access/effective'
	);
	return { ...actual, resolveOrganizationAccess: vi.fn() };
});
vi.mock('$lib/server/search/core-records', () => ({ searchCoreRecords: vi.fn() }));
vi.mock('$lib/server/search/conversations', () => ({ searchConversations: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOrganization = vi.mocked(getOrganizationContext);
const mockedAccess = vi.mocked(resolveOrganizationAccess);
const mockedSearch = vi.mocked(searchCoreRecords);
const mockedConversationSearch = vi.mocked(searchConversations);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const supabase = {};
const ownerSupabase = {};

function event(query: string) {
	return {
		url: new URL(`http://localhost/api/search?q=${encodeURIComponent(query)}`),
		locals: { supabase }
	} as Parameters<typeof GET>[0];
}

describe('global core-record search', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOrganization.mockResolvedValue({
			organization: { id: 'org-1', name: 'Acme', role: 'office' },
			user: { id: 'user-1' }
		} as never);
		mockedAccess.mockResolvedValue({
			features: {
				'core.customers_properties': true,
				'core.requests_assessments': true,
				'core.quotes': true,
				'core.jobs': true,
				'core.invoices_payments': true
			},
			permissions: {
				'customers.view': true,
				'quotes.view': false,
				'jobs.view': true,
				'invoices.view': false
			}
		} as never);
		mockedSearch.mockResolvedValue({ clients: [], requests: [], jobs: [] });
		mockedConversationSearch.mockResolvedValue([]);
		mockedOwnerClient.mockReturnValue(ownerSupabase as never);
	});

	it('rejects a one-character query before authentication or database work', async () => {
		const response = await GET(event('a'));

		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({
			error: 'Please review the highlighted fields.',
			field_errors: { q: 'Enter at least 2 characters.' }
		});
		expect(mockedOrganization).not.toHaveBeenCalled();
		expect(mockedSearch).not.toHaveBeenCalled();
	});

	it('requires an active organization membership', async () => {
		mockedOrganization.mockResolvedValue(null);

		const response = await GET(event('roof'));

		expect(response.status).toBe(401);
		expect(mockedSearch).not.toHaveBeenCalled();
	});

	it('trims the query and searches only permitted feature groups', async () => {
		const response = await GET(event('  roof  '));

		expect(response.status).toBe(200);
		expect(mockedSearch).toHaveBeenCalledWith(supabase, 'org-1', 'roof', {
			clients: true,
			requests: true,
			quotes: false,
			jobs: true,
			invoices: false
		});
		expect(await response.json()).toEqual({
			query: 'roof',
			groups: { clients: [], requests: [], jobs: [] }
		});
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('returns no partial results when a search query fails', async () => {
		mockedSearch.mockRejectedValue(new Error('database unavailable'));
		const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);

		const response = await GET(event('roof'));

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({
			error: 'We could not save that record. Please try again.'
		});
		consoleError.mockRestore();
	});

	it('adds conversations only when the member can view them', async () => {
		mockedAccess.mockResolvedValue({
			features: { 'communications.inbox': true },
			permissions: { 'conversations.view_assigned': true }
		} as never);
		mockedConversationSearch.mockResolvedValue([
			{
				id: 'client-1',
				type: 'conversation',
				title: 'Taylor Home',
				subtitle: 'Email · Roof quote',
				href: '/communications?search=roof&conversation=client-1'
			}
		]);

		const response = await GET(event('roof'));

		expect(mockedConversationSearch).toHaveBeenCalledWith(ownerSupabase, 'org-1', 'roof', {
			canViewTeam: false,
			canViewAssigned: true,
			userId: 'user-1'
		});
		expect((await response.json()).groups.conversations).toHaveLength(1);
	});

	it('leaves conversations out when the plan has no shared inbox', async () => {
		mockedAccess.mockResolvedValue({
			features: {},
			permissions: { 'conversations.view_team': true }
		} as never);

		const response = await GET(event('roof'));

		expect(mockedConversationSearch).not.toHaveBeenCalled();
		expect((await response.json()).groups.conversations).toBeUndefined();
	});
});
