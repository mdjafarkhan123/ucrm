import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { RequestEvent } from '@sveltejs/kit';
import { featureUnavailable, requireOrganizationPermission } from './permission';
import { getOrganizationContext } from '$lib/server/auth/organization';

vi.mock('$lib/server/auth/organization', () => ({ getOrganizationContext: vi.fn() }));

const mockedContext = vi.mocked(getOrganizationContext);

// A member whose role grants Pipeline, in an organization whose edition may or may not include it. The
// real resolver runs, so this is the answer the Pipeline screens receive.
function eventFor(editionCapabilities: string[]) {
	const snapshot = {
		organization: {
			id: 'org-a',
			name: 'Organization A',
			slug: 'org-a',
			lifecycle_status: 'active'
		},
		agreement: {
			id: 'agreement-1',
			edition_id: 'edition-1',
			billing_interval: 'month',
			agreed_price_usd_cents: 14900,
			effective_from: '2026-08-01T00:00:00.000Z'
		},
		edition: {
			id: 'edition-1',
			package_id: 'package-1',
			edition_number: 1,
			status: 'published',
			name: 'Growth',
			promise: null
		},
		package: { id: 'package-1', slug: 'growth' },
		capabilities: ['core.customers_properties', 'sales.pipeline'],
		capability_families: {
			'core.customers_properties': 'shared_platform',
			'sales.pipeline': 'field_service'
		},
		experience: {
			state: 'planned',
			experience: 'contractor',
			definition_version: 1,
			families: ['shared_platform', 'field_service']
		},
		edition_capabilities: editionCapabilities,
		capability_exceptions: [],
		allowance_exceptions: [],
		commercial_state: null,
		commercial_settings: null,
		free_access_events: [],
		employee_seat_limit: { state: 'numeric', value: 5, is_unlimited: false, source: 'package' },
		website_chat_widgets_limit: {
			state: 'not_included',
			value: null,
			is_unlimited: false,
			source: 'package'
		},
		marketing_email_limit: {
			state: 'not_included',
			value: null,
			is_unlimited: false,
			source: 'package'
		},
		membership: { user_id: 'user-a', role: 'sales' },
		role_permissions: [{ permission_key: 'pipeline.view', access_scope: null }],
		member_permission_overrides: []
	};
	return {
		locals: { supabase: { rpc: vi.fn().mockResolvedValue({ data: snapshot, error: null }) } }
	} as unknown as RequestEvent;
}

describe('requireOrganizationPermission', () => {
	beforeEach(() => {
		mockedContext.mockResolvedValue({
			user: { id: 'user-a' },
			organization: { id: 'org-a', role: 'sales' }
		} as never);
	});

	it('lets the member in while the edition includes the capability', async () => {
		const check = await requireOrganizationPermission(
			eventFor(['core.customers_properties', 'sales.pipeline']),
			'pipeline.view'
		);

		expect('response' in check).toBe(false);
	});

	it('answers "not part of your plan" once the capability is removed from the edition', async () => {
		const check = await requireOrganizationPermission(
			eventFor(['core.customers_properties']),
			'pipeline.view'
		);

		expect('response' in check).toBe(true);
		if (!('response' in check)) return;
		expect(check.response.status).toBe(403);
		expect(await check.response.json()).toEqual({
			error: 'This is not part of your current plan.',
			reason: 'feature_unavailable'
		});
	});
});

describe('featureUnavailable', () => {
	it('answers "not part of your plan" for a feature the plan leaves out, and nothing when included', async () => {
		const refusal = featureUnavailable(
			{ features: { 'communications.inbox': false } } as never,
			'communications.inbox'
		);
		expect(refusal?.status).toBe(403);
		expect(await refusal?.json()).toMatchObject({ reason: 'feature_unavailable' });
		expect(
			featureUnavailable(
				{ features: { 'communications.inbox': true } } as never,
				'communications.inbox'
			)
		).toBeNull();
	});
});
