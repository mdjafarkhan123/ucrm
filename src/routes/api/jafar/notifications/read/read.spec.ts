import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function clientWith(error: { message: string } | null = null) {
	const update = vi.fn();
	const is = vi.fn().mockResolvedValue({ error });
	const inFilter = vi.fn().mockResolvedValue({ error });
	const eq = vi.fn();
	eq.mockReturnValue({ eq, is });
	update.mockReturnValue({ is, in: inFilter, eq });

	return {
		from: () => ({ update }),
		__update: update,
		__is: is,
		__in: inFilter,
		__eq: eq
	};
}

function postEvent(body: unknown) {
	return {
		request: new Request('http://localhost/api/jafar/notifications/read', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		url: new URL('http://localhost/api/jafar/notifications/read'),
		params: {},
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

const ID = '123e4567-e89b-12d3-a456-426614174000';

describe('platform owner notification read-state API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await POST(postEvent({ all: true }));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a body that is neither a mark-all nor a list of ids', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(postEvent({ read: true }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an id that is not a uuid', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(postEvent({ ids: ['not-a-uuid'], read: true }));
		expect(response.status).toBe(422);
	});

	it('marks every unread notification read in one pass', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ all: true }));
		expect(response.status).toBe(200);
		expect(client.__update).toHaveBeenCalledWith({ read_at: expect.any(String) });
		expect(client.__is).toHaveBeenCalledWith('read_at', null);
	});

	it('marks the listed notifications read', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ ids: [ID], read: true }));
		expect(response.status).toBe(200);
		expect(client.__update).toHaveBeenCalledWith({ read_at: expect.any(String) });
		expect(client.__in).toHaveBeenCalledWith('id', [ID]);
	});

	it('clears the read stamp when a notification is marked unread again', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ ids: [ID], read: false }));
		expect(response.status).toBe(200);
		expect(client.__update).toHaveBeenCalledWith({ read_at: null });
	});

	it('rejects a record target that is not a known kind', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(postEvent({ target_kind: 'invoice', target_id: ID }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	// Opening a record from an alert email has to settle the bell too, otherwise a problem
	// Jafar already dealt with keeps showing as unread.
	it('marks everything unread about one record read when that record is opened', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ target_kind: 'onboarding_application', target_id: ID })
		);
		expect(response.status).toBe(200);
		expect(client.__update).toHaveBeenCalledWith({ read_at: expect.any(String) });
		expect(client.__eq).toHaveBeenCalledWith('target_kind', 'onboarding_application');
		expect(client.__eq).toHaveBeenCalledWith('target_id', ID);
		expect(client.__is).toHaveBeenCalledWith('read_at', null);
	});

	it('leaves notifications about other records untouched', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		await POST(postEvent({ target_kind: 'operation_attempt', target_id: ID }));
		expect(client.__in).not.toHaveBeenCalled();
	});

	it('returns a safe server error when the update fails', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(clientWith({ message: 'internal database details' }) as never);

		const response = await POST(postEvent({ all: true }));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The notifications could not be updated.' });
	});
});
