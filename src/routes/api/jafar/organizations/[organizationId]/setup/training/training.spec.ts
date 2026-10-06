import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as book } from './booking/+server';
import { POST as cancel } from './cancel/+server';
import { POST as setRecording } from './recording/+server';
import { POST as saveHandover } from '../handover/+server';
import { POST as markLive } from '../handover/live/+server';
import { POST as markDelivered } from '../handover/delivered/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	sendDeliveredEmails,
	sendLiveEmails,
	sendTrainingBookedEmails,
	sendTrainingCancelledEmails
} from '$lib/server/setup/training';

// Client onboarding E6: Jafar's booking, cancellation, recording link, handover, Live and Delivered.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/setup/training', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/setup/training')>(
		'$lib/server/setup/training'
	);
	return {
		...actual,
		sendLiveEmails: vi.fn(),
		sendDeliveredEmails: vi.fn(),
		sendTrainingBookedEmails: vi.fn(),
		sendTrainingCancelledEmails: vi.fn()
	};
});

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();
const attendees = [{ name: 'Sam', role: '', email: 'sam@example.com' }];

function call(handler: (event: never) => Response | Promise<Response>, body: unknown = {}) {
	return handler({
		params: { organizationId: ORGANIZATION_ID },
		url: new URL('http://localhost/api'),
		request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) })
	} as never);
}

describe('Jafar training and handover routes', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
	});

	it('needs the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		expect((await call(markLive)).status).toBe(401);
		expect((await call(markDelivered)).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('books training and emails the people the client named', async () => {
		rpc.mockResolvedValueOnce({
			data: {
				status: 'booked',
				booked_at: '2026-10-06T10:00:00Z',
				meeting_at: '2026-10-20T09:00:00Z',
				meeting_url: 'https://meet.google.com/abc',
				time_zone: 'Europe/London',
				attendees
			},
			error: null
		});
		const response = await call(book, {
			meeting_at: '2026-10-20T09:00:00.000Z',
			meeting_url: 'https://meet.google.com/abc'
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ status: 'booked', emailed: true, attendees: 1 });
		expect(rpc).toHaveBeenCalledWith('owner_book_setup_training', {
			target_organization_id: ORGANIZATION_ID,
			new_meeting_at: '2026-10-20T09:00:00.000Z',
			new_meeting_url: 'https://meet.google.com/abc',
			actor_email: 'owner@example.com'
		});
		expect(sendTrainingBookedEmails).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({ changed: false, attendees })
		);
	});

	it('sends nothing when the booking did not change, and refuses a link that is not https', async () => {
		rpc.mockResolvedValueOnce({ data: { status: 'unchanged' }, error: null });
		await call(book, {
			meeting_at: '2026-10-20T09:00:00Z',
			meeting_url: 'https://meet.google.com/abc'
		});
		expect(sendTrainingBookedEmails).not.toHaveBeenCalled();

		const refused = await call(book, {
			meeting_at: '2026-10-20T09:00:00Z',
			meeting_url: 'http://meet.google.com/abc'
		});
		expect(refused.status).toBe(422);
		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('keeps the booking when its email cannot be queued, and says so', async () => {
		rpc.mockResolvedValueOnce({
			data: {
				status: 'changed',
				booked_at: '2026-10-07T10:00:00Z',
				meeting_at: '2026-10-21T09:00:00Z',
				meeting_url: 'https://zoom.us/j/1',
				attendees
			},
			error: null
		});
		vi.mocked(sendTrainingBookedEmails).mockRejectedValueOnce(new Error('queue down'));
		const response = await call(book, {
			meeting_at: '2026-10-21T09:00:00Z',
			meeting_url: 'https://zoom.us/j/1'
		});
		expect(response.status).toBe(200);
		expect((await response.json()).emailed).toBe(false);
	});

	it('tells the attendees when training is cancelled', async () => {
		rpc.mockResolvedValueOnce({
			data: {
				status: 'cancelled',
				event_id: 7,
				meeting_at: '2026-10-20T09:00:00Z',
				time_zone: 'Europe/London',
				attendees
			},
			error: null
		});
		const response = await call(cancel);
		expect(response.status).toBe(200);
		expect(sendTrainingCancelledEmails).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({ eventId: 7 })
		);
	});

	it('removes the recording link by sending null, not by leaving it out', async () => {
		rpc.mockResolvedValueOnce({ data: { status: 'removed' }, error: null });
		const response = await call(setRecording, { recording_url: null });
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_set_setup_training_recording', {
			target_organization_id: ORGANIZATION_ID,
			new_recording_url: null,
			actor_email: 'owner@example.com'
		});
	});

	it('saves the handover whole, a blank summary as null', async () => {
		rpc.mockResolvedValueOnce({ data: { status: 'saved' }, error: null });
		const response = await call(saveHandover, {
			access_summary: '  ',
			guides: [{ title: ' Quotes ', url: 'https://help.example.com/quotes' }]
		});
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_save_setup_handover', {
			target_organization_id: ORGANIZATION_ID,
			new_access_summary: null,
			new_guides: [{ title: 'Quotes', url: 'https://help.example.com/quotes' }],
			actor_email: 'owner@example.com'
		});
	});

	it('emails owners and administrators once on Live, not when already live', async () => {
		rpc.mockResolvedValueOnce({ data: { status: 'live', live_at: 'x' }, error: null });
		await call(markLive);
		expect(sendLiveEmails).toHaveBeenCalledOnce();

		rpc.mockResolvedValueOnce({ data: { status: 'unchanged' }, error: null });
		await call(markLive);
		expect(sendLiveEmails).toHaveBeenCalledOnce();
	});

	it('passes on why delivery cannot close, in the database’s words', async () => {
		rpc.mockResolvedValueOnce({
			data: null,
			error: { code: '23514', message: 'Book the training, or the owner says they don’t need it.' }
		});
		const response = await call(markDelivered);
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(
			'Book the training, or the owner says they don’t need it.'
		);
		expect(sendDeliveredEmails).not.toHaveBeenCalled();
	});
});
