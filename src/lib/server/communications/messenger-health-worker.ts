import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadMessengerPageToken } from './messenger-connections';
import { checkMessengerPageHealth, messengerGraphConfig } from './messenger-graph';

const BATCH_SIZE = 6;
const CONCURRENCY = 3;
const CHECK_INTERVAL_MS = 60 * 60 * 1000;

type Connection = {
	id: string;
	organization_id: string;
	updated_at: string;
	page_id: string;
};
type Health = Awaited<ReturnType<typeof checkMessengerPageHealth>>;

export type MessengerHealthClient = {
	due(before: string, limit: number): Promise<Connection[]>;
	claim(row: Connection, before: string, checkedAt: string): Promise<boolean>;
	pageToken(row: Connection): Promise<string | null>;
	finish(row: Connection, checkedAt: string, health: Health): Promise<void>;
};

function resolveClient(): MessengerHealthClient {
	const owner = getOwnerSupabaseClient();
	return {
		due: async (before, limit) => {
			const { data, error } = await owner
				.from('communication_messenger_connections')
				.select('id, organization_id, page_id, updated_at')
				.eq('status', 'active')
				.or(`last_checked_at.is.null,last_checked_at.lte.${before}`)
				.order('last_checked_at', { ascending: true, nullsFirst: true })
				.order('id')
				.limit(limit);
			if (error) throw error;
			return data ?? [];
		},
		claim: async (row, before, checkedAt) => {
			const { data, error } = await owner
				.from('communication_messenger_connections')
				.update({ last_checked_at: checkedAt })
				.eq('id', row.id)
				.eq('organization_id', row.organization_id)
				.eq('status', 'active')
				.eq('updated_at', row.updated_at)
				.or(`last_checked_at.is.null,last_checked_at.lte.${before}`)
				.select('id');
			if (error) throw error;
			return Boolean(data?.length);
		},
		pageToken: (row) =>
			loadMessengerPageToken({
				organizationId: row.organization_id,
				connectionId: row.id
			}),
		finish: async (row, checkedAt, health) => {
			if (health === 'healthy') return;
			const { error } = await owner
				.from('communication_messenger_connections')
				.update({
					status: 'needs_reconnect',
					needs_reconnect_reason: health,
					updated_at: new Date().toISOString()
				})
				.eq('id', row.id)
				.eq('organization_id', row.organization_id)
				.eq('status', 'active')
				.eq('updated_at', row.updated_at)
				.eq('last_checked_at', checkedAt);
			if (error) throw error;
		}
	};
}

/** Cron only: bounded Page checks; failures never delay a staff reply or the webhook acknowledgement. */
export async function checkDueMessengerConnections(
	options: {
		client?: MessengerHealthClient;
		check?: typeof checkMessengerPageHealth;
		now?: Date;
	} = {}
) {
	const result = { checked: 0, reconnect: 0, deferred: 0, skipped: 0 };
	if (!options.client && !messengerGraphConfig()) return result;
	const client = options.client ?? resolveClient();
	const check = options.check ?? checkMessengerPageHealth;
	const now = options.now ?? new Date();
	const checkedAt = now.toISOString();
	const before = new Date(now.getTime() - CHECK_INTERVAL_MS).toISOString();
	const rows = await client.due(before, BATCH_SIZE);
	for (let offset = 0; offset < rows.length; offset += CONCURRENCY) {
		await Promise.all(
			rows.slice(offset, offset + CONCURRENCY).map(async (row) => {
				try {
					if (!(await client.claim(row, before, checkedAt))) {
						result.skipped++;
						return;
					}
					const token = await client.pageToken(row);
					const health = token ? await check(row.page_id, token) : 'token_invalid';
					await client.finish(row, checkedAt, health);
					result.checked++;
					if (health !== 'healthy') result.reconnect++;
				} catch {
					// Never log Graph envelopes, URLs or decrypted credentials. Retry at the next due check.
					result.deferred++;
					console.warn('Messenger connection health check deferred.', { connectionId: row.id });
				}
			})
		);
	}
	return result;
}
