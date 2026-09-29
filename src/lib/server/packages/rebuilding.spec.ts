import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { RequestEvent } from '@sveltejs/kit';
import { getOwnerSession } from '$lib/server/auth/owner';
import { packageSystemRebuilding } from './rebuilding';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const event = {} as RequestEvent;

describe('packageSystemRebuilding', () => {
	beforeEach(() => vi.clearAllMocks());

	it('asks for the owner sign-in first', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await packageSystemRebuilding(event);
		expect(response.status).toBe(401);
	});

	it('tells the owner the change is switched off while the package system is rebuilt', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);

		const response = await packageSystemRebuilding(event);
		expect(response.status).toBe(410);
		expect(await response.json()).toMatchObject({ reason: 'package_system_rebuilding' });
	});
});
