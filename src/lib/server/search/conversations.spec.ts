import { describe, expect, it } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { searchConversations } from './conversations';

type Call = { table: string; method: string; args: unknown[] };

function queryClient(rows: Record<string, unknown[]> = {}) {
	const calls: Call[] = [];
	const from = (table: string) => {
		const data = rows[table] ?? [];
		const builder: Record<string, unknown> = {};
		for (const method of ['select', 'eq', 'neq', 'or', 'order', 'limit', 'ilike', 'in']) {
			builder[method] = (...args: unknown[]) => {
				calls.push({ table, method, args });
				return builder;
			};
		}
		builder.then = (resolve: (value: { data: unknown[]; error: null }) => unknown) =>
			Promise.resolve(resolve({ data, error: null }));
		return builder;
	};
	return { client: { from } as unknown as SupabaseClient<Database>, calls };
}

describe('conversation search visibility', () => {
	it('does no database work without a Conversations viewing permission', async () => {
		const { client, calls } = queryClient();

		const result = await searchConversations(client, 'org-1', 'roof', {
			canViewTeam: false,
			canViewAssigned: false,
			userId: 'user-1'
		});

		expect(result).toEqual([]);
		expect(calls).toEqual([]);
	});

	it('restricts assigned-only search to assigned or followed clients on every source', async () => {
		const { client, calls } = queryClient({
			communication_conversation_assignments: [{ client_id: 'client-assigned' }],
			communication_conversation_followers: [{ client_id: 'client-followed' }],
			communication_inbound_messages: [
				{
					id: 'unauthorized',
					organization_id: 'org-1',
					client_id: 'client-other',
					sender_email: 'private@example.test',
					sender_name: 'Private',
					subject: 'Roof',
					created_at: '2026-09-11T10:00:00Z'
				}
			]
		});

		const result = await searchConversations(client, 'org-1', 'roof', {
			canViewTeam: false,
			canViewAssigned: true,
			userId: 'user-1'
		});

		const sources = [
			'communication_delivery_intents',
			'communication_inbound_messages',
			'communication_forward_events',
			'website_chat_messages'
		];
		for (const table of sources) {
			expect(calls).toContainEqual({
				table,
				method: 'eq',
				args: ['organization_id', 'org-1']
			});
			expect(calls).toContainEqual({
				table,
				method: 'in',
				args: ['client_id', ['client-assigned', 'client-followed']]
			});
			expect(calls).toContainEqual({ table, method: 'limit', args: [5] });
		}
		expect(result).toEqual([]);
	});

	it('allows team viewers to find unresolved email and Website Chat without merging conversations', async () => {
		const { client, calls } = queryClient({
			communication_inbound_messages: [
				{
					id: 'email-1',
					organization_id: 'org-1',
					client_id: null,
					sender_email: 'lead@example.test',
					sender_name: 'New Lead',
					subject: 'Roof repair',
					review_status: 'pending',
					created_at: '2026-09-11T10:00:00Z'
				}
			],
			website_chat_messages: [
				{
					id: 'chat-1',
					organization_id: 'org-1',
					client_id: null,
					session_id: 'session-1',
					body: 'Roof repair from chat',
					created_at: '2026-09-11T11:00:00Z'
				}
			],
			website_chat_sessions: [{ id: 'session-1', visitor_name: 'Chat Visitor' }]
		});

		const result = await searchConversations(client, 'org-1', 'roof', {
			canViewTeam: true,
			canViewAssigned: false,
			userId: 'user-1'
		});

		expect(result.map(({ id, title }) => ({ id, title }))).toEqual([
			{ id: 'webchat:session-1', title: 'Chat Visitor' },
			{ id: 'guarded:lead@example.test', title: 'New Lead' }
		]);
		expect(calls.some(({ table }) => table === 'communication_conversation_assignments')).toBe(
			false
		);
	});

	it('deduplicates channels into the contact-centered conversation result', async () => {
		const { client } = queryClient({
			communication_delivery_intents: [
				{
					id: 'email-1',
					organization_id: 'org-1',
					client_id: 'client-1',
					recipient_email: 'client@example.test',
					subject: 'Roof quote',
					created_at: '2026-09-11T10:00:00Z'
				}
			],
			website_chat_messages: [
				{
					id: 'chat-1',
					organization_id: 'org-1',
					client_id: 'client-1',
					session_id: 'session-1',
					body: 'Roof timing',
					created_at: '2026-09-11T11:00:00Z'
				}
			],
			clients: [{ id: 'client-1', display_name: 'Taylor Home' }],
			website_chat_sessions: [{ id: 'session-1', visitor_name: 'Taylor' }]
		});

		const result = await searchConversations(client, 'org-1', 'roof', {
			canViewTeam: true,
			canViewAssigned: true,
			userId: 'user-1'
		});

		expect(result).toHaveLength(1);
		expect(result[0]).toMatchObject({
			id: 'client-1',
			type: 'conversation',
			title: 'Taylor Home',
			subtitle: 'Website Chat · Roof timing'
		});
	});

	it('drops a row defensively if an owner-client response belongs to another organization', async () => {
		const { client } = queryClient({
			communication_inbound_messages: [
				{
					id: 'foreign-email',
					organization_id: 'org-other',
					client_id: null,
					sender_email: 'foreign@example.test',
					sender_name: 'Foreign Lead',
					subject: 'Roof',
					created_at: '2026-09-11T10:00:00Z'
				}
			]
		});

		const result = await searchConversations(client, 'org-1', 'roof', {
			canViewTeam: true,
			canViewAssigned: false,
			userId: 'user-1'
		});

		expect(result).toEqual([]);
	});
});
