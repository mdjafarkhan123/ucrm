import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { RequestEvent } from '@sveltejs/kit';
import { requireAutomationAccess } from './automation';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import type { EffectiveOrganizationAccess } from '$lib/server/access/effective';

vi.mock('$lib/server/auth/organization', () => ({ getOrganizationContext: vi.fn() }));
vi.mock('$lib/server/access/effective', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/access/effective')>()),
	resolveOrganizationAccess: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

const authContext = {
	user: { id: 'user-1', email: 'staff@example.com' },
	organization: { id: organizationId, name: 'Acme', role: 'owner' }
};

// resolveAutomationAccess reads only features + permissions off the resolved access, plus the seven limits
// and the authority row from the supabase client. This builds just those two seams.
function accessWith(
	features: Record<string, boolean>,
	permissions: Record<string, boolean>
): EffectiveOrganizationAccess {
	return { features, permissions } as unknown as EffectiveOrganizationAccess;
}

function clientWith(
	authority: Record<string, unknown> | null,
	limitRows: Array<Record<string, unknown>> = [
		{
			limit_key: 'automation_active_recipes',
			state: 'numeric',
			value: 10,
			is_unlimited: false,
			source: 'package'
		}
	]
) {
	return {
		rpc: vi.fn(async () => ({ data: limitRows, error: null })),
		from: vi.fn(() => ({
			select: vi.fn(() => ({
				eq: vi.fn(() => ({
					maybeSingle: vi.fn(async () => ({ data: authority, error: null }))
				}))
			}))
		}))
	};
}

function event(client: ReturnType<typeof clientWith>) {
	return { locals: { supabase: client } } as unknown as RequestEvent;
}

const included = { automations: true };
const viewer = { 'automations.view': true };
const manager = { 'automations.view': true, 'automations.manage': true };

describe('requireAutomationAccess — the direct-route gate', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOrganizationContext).mockResolvedValue(authContext as never);
	});

	it('refuses a caller with no organization context', async () => {
		vi.mocked(getOrganizationContext).mockResolvedValue(null);
		const check = await requireAutomationAccess(event(clientWith(null)), 'view');
		expect('response' in check && check.response.status).toBe(401);
	});

	it('answers not_included when the plan omits Automation, without leaking a resource', async () => {
		vi.mocked(resolveOrganizationAccess).mockResolvedValue(accessWith({ automations: false }, {}));
		const check = await requireAutomationAccess(event(clientWith(null)), 'view');
		expect('response' in check).toBe(true);
		if (!('response' in check)) return;
		expect(check.response.status).toBe(403);
		expect(await check.response.json()).toEqual({
			error: 'Automation is not part of your current plan.',
			reason: 'not_included'
		});
	});

	it('answers permission_denied when a member cannot view', async () => {
		vi.mocked(resolveOrganizationAccess).mockResolvedValue(accessWith(included, {}));
		const check = await requireAutomationAccess(event(clientWith(null)), 'view');
		if (!('response' in check)) throw new Error('expected a denial');
		expect(check.response.status).toBe(403);
		expect((await check.response.json()).reason).toBe('permission_denied');
	});

	it('lets an entitled viewer in, not read-only, on an enabled organization', async () => {
		vi.mocked(resolveOrganizationAccess).mockResolvedValue(accessWith(included, viewer));
		const check = await requireAutomationAccess(
			event(clientWith({ operational_state: 'enabled', security_state: 'active' })),
			'view'
		);
		if ('response' in check) throw new Error('expected access');
		expect(check.automation.authority_state).toBe('enabled');
		expect(check.automation.read_only).toBe(false);
		expect(check.automation.can_view).toBe(true);
		expect(check.automation.limits.automation_active_recipes.value).toBe(10);
	});

	it('keeps a suspended viewer read-only rather than turning them away', async () => {
		vi.mocked(resolveOrganizationAccess).mockResolvedValue(accessWith(included, manager));
		const check = await requireAutomationAccess(
			event(
				clientWith({
					operational_state: 'enabled',
					security_state: 'suspended',
					security_reason: 'Security hold pending review.'
				})
			),
			'view'
		);
		if ('response' in check) throw new Error('expected read-only access');
		expect(check.automation.authority_state).toBe('security_suspended');
		expect(check.automation.read_only).toBe(true);
		expect(check.automation.can_manage).toBe(false);
		expect(check.automation.authority_reason).toBe('Security hold pending review.');
	});

	it('fails a write closed under security suspension with the platform reason', async () => {
		vi.mocked(resolveOrganizationAccess).mockResolvedValue(accessWith(included, manager));
		const check = await requireAutomationAccess(
			event(clientWith({ operational_state: 'enabled', security_state: 'suspended' })),
			'manage'
		);
		if (!('response' in check)) throw new Error('expected a denial');
		expect(check.response.status).toBe(403);
		expect((await check.response.json()).reason).toBe('security_suspended');
	});

	it('fails a write closed under an operational disable', async () => {
		vi.mocked(resolveOrganizationAccess).mockResolvedValue(accessWith(included, manager));
		const check = await requireAutomationAccess(
			event(clientWith({ operational_state: 'disabled', security_state: 'active' })),
			'manage'
		);
		if (!('response' in check)) throw new Error('expected a denial');
		expect(check.response.status).toBe(403);
		expect((await check.response.json()).reason).toBe('operationally_disabled');
	});

	it('denies a write to an enabled organization when the member lacks the capability', async () => {
		vi.mocked(resolveOrganizationAccess).mockResolvedValue(accessWith(included, viewer));
		const check = await requireAutomationAccess(
			event(clientWith({ operational_state: 'enabled', security_state: 'active' })),
			'manage'
		);
		if (!('response' in check)) throw new Error('expected a denial');
		expect(check.response.status).toBe(403);
		expect((await check.response.json()).reason).toBe('permission_denied');
	});
});
