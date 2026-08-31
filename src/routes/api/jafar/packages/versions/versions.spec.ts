import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { POST as publish } from '../publish/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function event(body: unknown) {
	return {
		request: new Request('http://localhost/api/jafar/packages/versions', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/packages/versions'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

describe('platform owner package version write API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(event({}));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the package version before calling the database', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});

		const response = await POST(event({ package_key: 'growth' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('creates a draft through the atomic owner database operation', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});
		const rpc = vi.fn().mockResolvedValue({ data: 'version-id', error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await POST(
			event({
				package_key: 'growth',
				display_name: 'Growth',
				public_description: 'For growing teams.',
				value_explanation: 'Includes pipeline tools.',
				price_usd_cents: 14900,
				feature_keys: ['sales.pipeline'],
				limit: { key: 'employee_seats', state: 'numeric', value: 10 },
				email_allowances: {
					operational: { state: 'numeric', value: 10000 },
					essential: { state: 'numeric', value: 1000 }
				},
				website_chat_limits: {
					widgets: { state: 'numeric', value: 3 },
					accepted_conversations: { state: 'numeric', value: 200 }
				},
				automation_limits: {
					active_recipes: { state: 'numeric', value: 20 },
					conditions_per_recipe: { state: 'numeric', value: 6 },
					steps_per_recipe: { state: 'numeric', value: 15 },
					customer_messages_per_enrollment: { state: 'numeric', value: 5 },
					message_spacing_minutes: { state: 'numeric', value: 60 },
					max_delay_days: { state: 'numeric', value: 90 },
					max_enrollment_duration_days: { state: 'unlimited', value: null }
				}
			})
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ version_id: 'version-id', saved: true });
		expect(rpc).toHaveBeenCalledWith(
			'manage_platform_package_version',
			expect.objectContaining({ operation: 'create_draft', actor_email: 'owner@example.com' })
		);
		expect(rpc).toHaveBeenCalledWith('manage_platform_package_email_allowances', {
			target_version_id: 'version-id',
			target_operational_state: 'numeric',
			target_operational_value: 10000,
			target_essential_state: 'numeric',
			target_essential_value: 1000,
			actor_email: 'owner@example.com'
		});
		expect(rpc).toHaveBeenCalledWith('manage_platform_package_website_chat_limits', {
			target_version_id: 'version-id',
			target_widgets_state: 'numeric',
			target_widgets_value: 3,
			target_accepted_conversations_state: 'numeric',
			target_accepted_conversations_value: 200,
			actor_email: 'owner@example.com'
		});
		expect(rpc).toHaveBeenCalledWith('manage_platform_package_automation_limits', {
			target_version_id: 'version-id',
			target_active_recipes_state: 'numeric',
			target_active_recipes_value: 20,
			target_conditions_state: 'numeric',
			target_conditions_value: 6,
			target_steps_state: 'numeric',
			target_steps_value: 15,
			target_customer_messages_state: 'numeric',
			target_customer_messages_value: 5,
			target_message_spacing_state: 'numeric',
			target_message_spacing_value: 60,
			target_max_delay_state: 'numeric',
			target_max_delay_value: 90,
			target_max_duration_state: 'unlimited',
			target_max_duration_value: null,
			actor_email: 'owner@example.com'
		});
	});

	it('rejects a numeric allowance without a recipient count', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});

		const response = await POST(
			event({
				package_key: 'growth',
				display_name: 'Growth',
				public_description: 'For growing teams.',
				price_usd_cents: 14900,
				feature_keys: [],
				email_allowances: {
					operational: { state: 'numeric', value: null },
					essential: { state: 'not_included', value: null }
				}
			})
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('does not expose allowance command errors', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValueOnce({ data: 'version-id', error: null })
			.mockResolvedValueOnce({ data: null, error: { message: 'draft-only details' } });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await POST(
			event({
				package_key: 'growth',
				display_name: 'Growth',
				public_description: 'For growing teams.',
				price_usd_cents: 14900,
				feature_keys: [],
				email_allowances: {
					operational: { state: 'unlimited', value: null },
					essential: { state: 'numeric', value: 500 }
				},
				website_chat_limits: {
					widgets: { state: 'not_included', value: null },
					accepted_conversations: { state: 'not_included', value: null }
				}
			})
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'The package version could not be saved.' });
	});

	it('does not expose raw database errors when saving a draft is rejected', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});
		mockedClient.mockReturnValue({
			rpc: vi.fn().mockResolvedValue({
				data: null,
				error: { message: 'internal constraint details' }
			})
		} as never);

		const response = await POST(
			event({
				package_key: 'growth',
				display_name: 'Growth',
				public_description: 'For growing teams.',
				price_usd_cents: 14900,
				feature_keys: [],
				email_allowances: {
					operational: { state: 'not_included', value: null },
					essential: { state: 'not_included', value: null }
				},
				website_chat_limits: {
					widgets: { state: 'not_included', value: null },
					accepted_conversations: { state: 'not_included', value: null }
				}
			})
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'The package version could not be saved.'
		});
	});

	it('does not expose raw database errors when publishing is rejected', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});
		mockedClient.mockReturnValue({
			rpc: vi.fn().mockResolvedValue({
				data: null,
				error: { message: 'internal publication details' }
			})
		} as never);

		const response = await publish(
			event({
				package_key: 'growth',
				version_id: '123e4567-e89b-12d3-a456-426614174000'
			}) as unknown as Parameters<typeof publish>[0]
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'The package version could not be published.'
		});
	});
});
