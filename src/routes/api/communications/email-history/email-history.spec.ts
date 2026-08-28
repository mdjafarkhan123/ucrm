import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/auth/organization', () => ({ getOrganizationContext: vi.fn() }));
vi.mock('$lib/server/access/effective', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/effective')>(
		'$lib/server/access/effective'
	);
	return { ...actual, resolveOrganizationAccess: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedAuth = vi.mocked(getOrganizationContext);
const mockedAccess = vi.mocked(resolveOrganizationAccess);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const mockedRateLimit = vi.mocked(checkRateLimit);

// A single global queue: each `.from(table)` call pops the next result regardless of table name, so a
// test describes exactly what each call in sequence answers with, in the order the route issues them.
function chain(result: { data?: unknown; error?: unknown }) {
	const obj: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'neq', 'not', 'is', 'order', 'or', 'lte', 'in', 'limit']) {
		obj[method] = vi.fn(() => obj);
	}
	(obj as { then: unknown }).then = (...args: unknown[]) =>
		(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(...args);
	return obj;
}

function fromQueue(results: Array<{ data?: unknown; error?: unknown }>) {
	const queue = [...results];
	const chains: Array<Record<string, unknown>> = [];
	const from = vi.fn(() => {
		const built = chain(queue.shift() ?? { data: null, error: null });
		chains.push(built);
		return built;
	});
	return Object.assign(from, { chains });
}

function event(query: string) {
	return {
		url: new URL(`http://localhost/api/communications/email-history?${query}`),
		locals: { supabase: {} }
	} as Parameters<typeof GET>[0];
}

describe('reading Communications history', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedAuth.mockResolvedValue({
			organization: { id: 'org-1' },
			user: { id: 'user-1' }
		} as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('denies a member with neither conversations permission', async () => {
		mockedAccess.mockResolvedValue({ permissions: {}, features: {} } as never);
		const response = await GET(event(''));
		expect(response.status).toBe(403);
	});

	it('returns an honest empty My Inbox for assigned-only access with no assignments or follows', async () => {
		mockedAccess.mockResolvedValue({
			permissions: { 'conversations.view_assigned': true },
			features: {}
		} as never);
		const from = fromQueue([
			{ data: [], error: null }, // assigned to me
			{ data: [], error: null } // followed by me
		]);
		mockedOwnerClient.mockReturnValue({ from } as never);

		const response = await GET(event('channel=all'));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			emails: [],
			messages: [],
			website_chat: [],
			website_chat_sessions: [],
			next_cursor: null,
			view: 'mine',
			can_view_team: false,
			can_manage_assignment: false,
			can_forward: false,
			can_send: false
		});
		expect(from).toHaveBeenCalledTimes(2);
	});

	it('ignores ?view=mine for an assigned-only viewer who is already forced to My Inbox', async () => {
		mockedAccess.mockResolvedValue({
			permissions: { 'conversations.view_assigned': true },
			features: {}
		} as never);
		const from = fromQueue([
			{ data: [], error: null },
			{ data: [], error: null }
		]);
		mockedOwnerClient.mockReturnValue({ from } as never);

		const response = await GET(event('view=team'));
		expect((await response.json()).view).toBe('mine');
	});

	describe('with team access', () => {
		beforeEach(() => {
			mockedAccess.mockResolvedValue({
				permissions: { 'conversations.view_team': true },
				features: {}
			} as never);
		});

		it('keeps the default (email-only) response shape untouched by the inbound merge', async () => {
			const from = fromQueue([
				{
					data: [
						{
							id: 'out-1',
							client_id: 'client-1',
							recipient_email: 'a@example.test',
							quote_id: null,
							subject: 'Hi',
							text_content: 'body',
							status: 'submitted',
							failure_message: null,
							created_at: '2026-08-25T10:00:00+00:00',
							resent_from_intent_id: null,
							send_kind: 'manual',
							created_by: null
						}
					],
					error: null
				},
				{ data: [{ id: 'client-1', display_name: 'Acme' }], error: null }, // clients
				{ data: [], error: null }, // resent-into lookup
				{ data: [], error: null }, // outbound attachments
				{ data: [], error: null }, // assignments
				{ data: [], error: null } // my follows
			]);
			mockedOwnerClient.mockReturnValue({ from } as never);

			const response = await GET(event(''));
			expect(response.status).toBe(200);
			const body = await response.json();
			expect(body.messages).toBeUndefined();
			expect(body.emails).toEqual([
				{
					id: 'out-1',
					client_id: 'client-1',
					recipient_email: 'a@example.test',
					quote_id: null,
					subject: 'Hi',
					text_content: 'body',
					status: 'submitted',
					failure_message: null,
					created_at: '2026-08-25T10:00:00+00:00',
					resent_from_intent_id: null,
					send_kind: 'manual',
					created_by: null,
					client_name: 'Acme',
					client_email: 'a@example.test',
					attachments: [],
					can_resend: false,
					created_by_name: null,
					resent_into_intent_id: null,
					assigned_to: null,
					assigned_to_name: null,
					is_following: false
				}
			]);
			// Only the outbound query and its five lookups run -- no inbound table is ever touched.
			expect(from).toHaveBeenCalledTimes(6);
		});

		it('attaches outbound attachments to the matching outbound message', async () => {
			const from = fromQueue([
				{
					data: [
						{
							id: 'out-1',
							client_id: 'client-1',
							recipient_email: 'a@example.test',
							quote_id: null,
							subject: 'Hi',
							text_content: 'body',
							status: 'submitted',
							failure_message: null,
							created_at: '2026-08-25T10:00:00+00:00',
							resent_from_intent_id: null,
							send_kind: 'manual',
							created_by: null
						}
					],
					error: null
				},
				{ data: [{ id: 'client-1', display_name: 'Acme' }], error: null }, // clients
				{ data: [], error: null }, // resent-into lookup
				{
					data: [
						{
							id: 'oatt-1',
							delivery_intent_id: 'out-1',
							file_name: 'invoice.pdf',
							mime_type: 'application/pdf',
							byte_size: 5678
						}
					],
					error: null
				}, // outbound attachments
				{ data: [], error: null }, // assignments
				{ data: [], error: null } // my follows
			]);
			mockedOwnerClient.mockReturnValue({ from } as never);

			const response = await GET(event(''));
			const body = await response.json();
			expect(body.emails[0].attachments).toEqual([
				{
					id: 'oatt-1',
					delivery_intent_id: 'out-1',
					file_name: 'invoice.pdf',
					mime_type: 'application/pdf',
					byte_size: 5678
				}
			]);
		});

		it('merges inbound replies in with unread computed from the personal read mark', async () => {
			const from = fromQueue([
				// needs-review Website Chat sessions (none in this fixture)
				{ data: [], error: null },
				// outbound page
				{
					data: [
						{
							id: 'out-1',
							client_id: 'client-2',
							recipient_email: 'x@example.test',
							quote_id: null,
							subject: 'Out subject',
							text_content: 'out body',
							status: 'submitted',
							failure_message: null,
							created_at: '2026-08-25T09:30:00+00:00',
							resent_from_intent_id: null,
							send_kind: 'automated',
							created_by: null
						}
					],
					error: null
				},
				// inbound page
				{
					data: [
						{
							id: 'in-2',
							client_id: 'client-1',
							sender_email: 'cust@example.test',
							sender_name: 'Cust',
							subject: 'Re: Hi',
							text_content: 'reply2',
							created_at: '2026-08-25T11:00:00+00:00',
							in_reply_to_intent_id: null,
							message_kind: 'reply',
							review_status: 'accepted',
							review_reason: null,
							automation_suppressed: false,
							attachment_count: 1
						},
						{
							id: 'in-1',
							client_id: 'client-1',
							sender_email: 'cust@example.test',
							sender_name: 'Cust',
							subject: 'Re: Hi',
							text_content: 'reply1',
							created_at: '2026-08-25T08:00:00+00:00',
							in_reply_to_intent_id: null,
							message_kind: 'reply',
							review_status: 'accepted',
							review_reason: null,
							automation_suppressed: false,
							attachment_count: 0
						}
					],
					error: null
				},
				// forward page (none in this fixture)
				{ data: [], error: null },
				// Website Chat messages (none in this fixture)
				{ data: [], error: null },
				// clients
				{
					data: [
						{ id: 'client-1', display_name: 'Jane Client' },
						{ id: 'client-2', display_name: 'Bob Client' }
					],
					error: null
				},
				// resent-into lookup
				{ data: [], error: null },
				// attachments
				{
					data: [
						{
							id: 'att-1',
							inbound_message_id: 'in-2',
							file_name: 'receipt.pdf',
							mime_type: 'application/pdf',
							byte_size: 1234,
							status: 'available'
						}
					],
					error: null
				},
				// outbound attachments
				{ data: [], error: null },
				// read marks
				{
					data: [{ client_id: 'client-1', last_read_at: '2026-08-25T09:00:00+00:00' }],
					error: null
				},
				// assignments
				{ data: [{ client_id: 'client-2', assigned_to: 'user-9' }], error: null },
				// my follows
				{ data: [{ client_id: 'client-1' }], error: null },
				// profiles (for assigned_to's name -- created_by is null on both rows in this fixture)
				{ data: [{ id: 'user-9', full_name: 'Robin' }], error: null }
			]);
			mockedOwnerClient.mockReturnValue({ from } as never);

			const response = await GET(event('channel=all'));
			expect(response.status).toBe(200);

			// A dismissed guarded message stays in the table for audit but must never reach the inbox.
			const inboundChain = from.chains[2] as { neq: ReturnType<typeof vi.fn> };
			expect(inboundChain.neq).toHaveBeenCalledWith('review_status', 'dismissed');

			const body = await response.json();
			expect(body.messages.map((message: { id: string }) => message.id)).toEqual([
				'in-2',
				'out-1',
				'in-1'
			]);

			const newerReply = body.messages[0];
			expect(newerReply.direction).toBe('inbound');
			expect(newerReply.unread).toBe(true);
			expect(newerReply.attachments).toEqual([
				{
					id: 'att-1',
					inbound_message_id: 'in-2',
					file_name: 'receipt.pdf',
					mime_type: 'application/pdf',
					byte_size: 1234,
					status: 'available'
				}
			]);

			const olderReply = body.messages[2];
			expect(olderReply.direction).toBe('inbound');
			expect(olderReply.unread).toBe(false);
			expect(olderReply.attachments).toEqual([]);
			expect(olderReply.client_name).toBe('Jane Client');
			// client-1 is followed by the caller but not assigned to anyone.
			expect(olderReply.assigned_to).toBeNull();
			expect(olderReply.is_following).toBe(true);

			const outbound = body.messages[1];
			expect(outbound.direction).toBe('outbound');
			expect(outbound.client_name).toBe('Bob Client');
			expect(outbound.attachments).toEqual([]);
			// client-2 is assigned to user-9 but not followed by the caller.
			expect(outbound.assigned_to).toBe('user-9');
			expect(outbound.assigned_to_name).toBe('Robin');
			expect(outbound.is_following).toBe(false);
		});

		it('scopes to one client for the Communication tab and includes both directions unasked', async () => {
			const from = fromQueue([
				{ data: [], error: null }, // outbound page (none for this client in this fixture)
				{ data: [], error: null }, // inbound page
				{ data: [], error: null }, // forward page
				{ data: [], error: null }, // Website Chat page
				{ data: [], error: null }, // clients
				{ data: [], error: null }, // resent-into lookup
				{ data: [], error: null }, // attachments
				{ data: [], error: null }, // outbound attachments
				{ data: [], error: null }, // read marks
				{ data: [], error: null }, // assignments
				{ data: [], error: null } // my follows
			]);
			mockedOwnerClient.mockReturnValue({ from } as never);

			const response = await GET(event('client_id=client-1'));
			expect(response.status).toBe(200);
			const body = await response.json();
			expect(body.messages).toEqual([]);

			const outboundChain = from.chains[0] as { eq: ReturnType<typeof vi.fn> };
			expect(outboundChain.eq).toHaveBeenCalledWith('client_id', 'client-1');
			const inboundChain = from.chains[1] as { eq: ReturnType<typeof vi.fn> };
			expect(inboundChain.eq).toHaveBeenCalledWith('client_id', 'client-1');
			// Website Chat is scoped the same way, and a conflicting-identity session is never asked for
			// here: it belongs to no client yet, so it cannot belong to this one.
			const chatChain = from.chains[3] as { eq: ReturnType<typeof vi.fn> };
			expect(chatChain.eq).toHaveBeenCalledWith('client_id', 'client-1');
			expect(from.chains).toHaveLength(4);
		});

		it('merges Website Chat in as a fourth source and names the staff member who replied', async () => {
			const from = fromQueue([
				{ data: [], error: null }, // needs-review sessions
				{ data: [], error: null }, // outbound page
				{ data: [], error: null }, // inbound page
				{ data: [], error: null }, // forward page
				{
					// Website Chat page, newest first
					data: [
						{
							id: 'chat-2',
							client_id: 'client-1',
							session_id: 'session-1',
							sender_type: 'staff',
							sender_user_id: 'user-9',
							body: 'On my way.',
							delivery_state: 'sent',
							created_at: '2026-08-27T10:05:00+00:00'
						},
						{
							id: 'chat-1',
							client_id: 'client-1',
							session_id: 'session-1',
							sender_type: 'visitor',
							sender_user_id: null,
							body: 'Are you open?',
							delivery_state: 'sent',
							created_at: '2026-08-27T10:00:00+00:00'
						}
					],
					error: null
				},
				{ data: [{ id: 'client-1', display_name: 'Jane Client' }], error: null }, // clients
				// The visitor's line landed after the caller last read this conversation.
				{
					data: [{ client_id: 'client-1', last_read_at: '2026-08-27T09:00:00+00:00' }],
					error: null
				},
				{ data: [], error: null }, // assignments
				{ data: [], error: null }, // my follows
				{
					// the session behind both rows
					data: [
						{
							id: 'session-1',
							client_id: 'client-1',
							match_status: 'resolved',
							visitor_name: 'Jane',
							submitted_email: 'jane@example.test',
							submitted_phone_e164: null,
							candidate_client_id_by_phone: null,
							candidate_client_id_by_email: null,
							started_at: '2026-08-27T09:59:00+00:00',
							last_activity_at: '2026-08-27T10:05:00+00:00',
							closed_at: '2026-08-27T10:10:00+00:00',
							closed_reason: 'staff_ended',
							closed_by: 'user-9'
						}
					],
					error: null
				},
				{ data: [{ id: 'user-9', full_name: 'Robin' }], error: null } // profiles
			]);
			mockedOwnerClient.mockReturnValue({ from } as never);

			const body = await (await GET(event('channel=all'))).json();

			// Chat travels beside `messages`; the email-shaped array is left exactly as it was.
			expect(body.messages).toEqual([]);
			expect(body.website_chat.map((row: { id: string }) => row.id)).toEqual(['chat-2', 'chat-1']);

			const [reply, visitorLine] = body.website_chat;
			// Direction is derived from sender_type, never read from the column.
			expect(reply.direction).toBe('outbound');
			expect(reply.sender_name).toBe('Robin');
			expect(reply.unread).toBe(false);
			expect(visitorLine.direction).toBe('inbound');
			expect(visitorLine.unread).toBe(true);
			expect(visitorLine.client_name).toBe('Jane Client');

			// The ended state lives on the session: the system part physically cannot name a person.
			expect(body.website_chat_sessions).toEqual([
				expect.objectContaining({
					id: 'session-1',
					closed_reason: 'staff_ended',
					closed_by_name: 'Robin',
					visitor_name: 'Jane',
					candidates: []
				})
			]);
		});

		it('reads a conflicting-identity session through its own bounded query and offers both candidates', async () => {
			const from = fromQueue([
				{ data: [{ id: 'session-2' }], error: null }, // needs-review sessions
				{ data: [], error: null }, // outbound page
				{ data: [], error: null }, // inbound page
				{ data: [], error: null }, // forward page
				{ data: [], error: null }, // Website Chat, resolved half
				{
					// Website Chat, needs-review half -- client_id is null by design
					data: [
						{
							id: 'chat-9',
							client_id: null,
							session_id: 'session-2',
							sender_type: 'visitor',
							sender_user_id: null,
							body: 'Hello?',
							delivery_state: 'sent',
							created_at: '2026-08-27T11:00:00+00:00'
						}
					],
					error: null
				},
				// No client lookup, no read marks, no assignment and no follow query run at all: every row on
				// this page has client_id = null, so there is no contact for any of them to be about.
				{
					data: [
						{
							id: 'session-2',
							client_id: null,
							match_status: 'needs_review',
							visitor_name: 'Sam',
							submitted_email: 'sam@example.test',
							submitted_phone_e164: '+15550000000',
							candidate_client_id_by_phone: 'client-7',
							candidate_client_id_by_email: 'client-8',
							started_at: '2026-08-27T10:59:00+00:00',
							last_activity_at: '2026-08-27T11:00:00+00:00',
							closed_at: null,
							closed_reason: null,
							closed_by: null
						}
					],
					error: null
				},
				// candidate client names (this fixture needs no profiles)
				{
					data: [
						{ id: 'client-7', display_name: 'Sam Phone' },
						{ id: 'client-8', display_name: 'Sam Email' }
					],
					error: null
				}
			]);
			mockedOwnerClient.mockReturnValue({ from } as never);

			const body = await (await GET(event('channel=all'))).json();

			// Scoped by organization_id as well as session id: website_chat_messages_session_timeline_idx
			// leads with organization_id, and session ids alone cannot drive it.
			const reviewChain = from.chains[5] as {
				eq: ReturnType<typeof vi.fn>;
				in: ReturnType<typeof vi.fn>;
			};
			expect(reviewChain.eq).toHaveBeenCalledWith('organization_id', 'org-1');
			expect(reviewChain.in).toHaveBeenCalledWith('session_id', ['session-2']);

			// A session with no contact has no read-mark seam, so it never clears -- the same rule a
			// guarded inbound email already follows.
			expect(body.website_chat).toHaveLength(1);
			expect(body.website_chat[0]).toEqual(
				expect.objectContaining({ id: 'chat-9', client_id: null, client_name: null, unread: true })
			);
			expect(body.website_chat_sessions[0].candidates).toEqual([
				{ matched_on: 'phone', client_id: 'client-7', client_name: 'Sam Phone' },
				{ matched_on: 'email', client_id: 'client-8', client_name: 'Sam Email' }
			]);
		});
	});

	it("restricts a client-scoped read to an assigned-only viewer's own clients, same as the general inbox", async () => {
		mockedAccess.mockResolvedValue({
			permissions: { 'conversations.view_assigned': true },
			features: {}
		} as never);
		const from = fromQueue([
			{ data: [], error: null }, // assigned to me
			{ data: [], error: null } // followed by me
		]);
		mockedOwnerClient.mockReturnValue({ from } as never);

		const response = await GET(event('client_id=someone-elses-client'));
		expect(response.status).toBe(200);
		expect((await response.json()).messages).toEqual([]);
		// Nothing in myClientIds means the route returns early -- it never even queries this client's
		// messages, the same short-circuit the general My Inbox empty case already takes.
		expect(from).toHaveBeenCalledTimes(2);
	});
});
