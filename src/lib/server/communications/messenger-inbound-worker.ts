import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { parseMessengerInboundMessages, parseMessengerPageReports } from './messenger-webhook';

// Messenger Part 5: turns saved webhook deliveries (communication_messenger_webhook_events) into inbox messages.
// The webhook route saves first and answers Meta at once, then wakes this; the one-minute cron wakes it too, so a
// delivery the instant wake missed is still processed. Each wake claims its own batch (SKIP LOCKED), so the two
// can overlap safely, and the record RPC ignores a message ID it already has. Part 7 adds Meta's reports about the
// Page's own messages: echoes and delivered/read watermarks.

export const MESSENGER_WORKER_NAME = 'communications-messenger-inbound';
const BATCH_SIZE = 25;
const MAX_BATCHES = 8;

type DbError = { message: string; code?: string } | null;

export type MessengerWebhookEventRow = {
	id: string;
	claim_token: string | null;
	payload: unknown;
};

export type MessengerInboundWorkerClient = {
	claim(limit: number): Promise<{ data: MessengerWebhookEventRow[] | null; error: DbError }>;
	// The live (not disconnected) connection for a Page; a Page feeds one business at a time.
	findConnectionId(pageId: string): Promise<{ data: string | null; error: DbError }>;
	recordMessage(args: {
		target_connection_id: string;
		target_psid: string;
		target_mid: string;
		target_text: string;
		target_attachment_count: number;
		target_sent_at: string | null;
	}): Promise<{ error: DbError }>;
	recordEcho(args: {
		target_connection_id: string;
		target_psid: string;
		target_mid: string;
		target_metadata: string | null;
		target_text: string;
		target_sent_at: string | null;
		target_from_this_app: boolean;
	}): Promise<{ error: DbError }>;
	recordReceipt(args: {
		target_connection_id: string;
		target_psid: string;
		target_kind: 'delivered' | 'read';
		target_watermark: string;
		target_mids: string[];
	}): Promise<{ error: DbError }>;
	finish(
		id: string,
		claimToken: string,
		processingError: string | null
	): Promise<{ error: DbError }>;
};

export type MessengerDrainResult = { claimed: number; processed: number; failed: number };

function resolveClient(client?: MessengerInboundWorkerClient): MessengerInboundWorkerClient {
	if (client) return client;
	const owner = getOwnerSupabaseClient();
	return {
		claim: async (limit) => {
			const { data, error } = await owner.rpc('claim_communication_messenger_webhook_events', {
				p_limit: limit
			});
			return { data: (data as MessengerWebhookEventRow[] | null) ?? null, error };
		},
		findConnectionId: async (pageId) => {
			const { data, error } = await owner
				.from('communication_messenger_connections')
				.select('id')
				.eq('page_id', pageId)
				.neq('status', 'disconnected')
				.maybeSingle();
			return { data: data?.id ?? null, error };
		},
		recordMessage: async (args) => {
			const { error } = await owner.rpc('record_communication_messenger_inbound_message', {
				...args,
				target_sent_at: args.target_sent_at as string
			});
			return { error };
		},
		recordEcho: async (args) => {
			const { error } = await owner.rpc('record_communication_messenger_echo', {
				...args,
				target_metadata: args.target_metadata as string,
				target_sent_at: args.target_sent_at as string
			});
			return { error };
		},
		recordReceipt: async (args) => {
			const { error } = await owner.rpc('record_communication_messenger_receipt', args);
			return { error };
		},
		finish: async (id, claimToken, processingError) => {
			const now = new Date().toISOString();
			const { error } = await owner
				.from('communication_messenger_webhook_events')
				.update({
					claim_token: null,
					claimed_at: null,
					processing_error: processingError?.slice(0, 4000) ?? null,
					processed_at: processingError ? null : now
				})
				.eq('id', id)
				.eq('claim_token', claimToken);
			return { error };
		}
	};
}

async function processEvent(
	client: MessengerInboundWorkerClient,
	event: MessengerWebhookEventRow,
	ourAppId: string | null
) {
	const connectionIds = new Map<string, string | null>();
	// A Page no business has connected (or Meta's dashboard test sample): kept as a raw delivery only.
	async function connectionFor(pageId: string) {
		if (!connectionIds.has(pageId)) {
			const found = await client.findConnectionId(pageId);
			if (found.error) throw new Error(`Connection lookup failed: ${found.error.message}`);
			connectionIds.set(pageId, found.data);
		}
		return connectionIds.get(pageId) ?? null;
	}

	for (const message of parseMessengerInboundMessages(event.payload)) {
		const connectionId = await connectionFor(message.pageId);
		if (!connectionId) continue;

		const recorded = await client.recordMessage({
			target_connection_id: connectionId,
			target_psid: message.psid,
			target_mid: message.mid,
			target_text: message.text,
			target_attachment_count: message.attachmentCount,
			target_sent_at: message.sentAt
		});
		if (recorded.error) throw new Error(`Recording message failed: ${recorded.error.message}`);
	}

	for (const report of parseMessengerPageReports(event.payload)) {
		const connectionId = await connectionFor(report.pageId);
		if (!connectionId) continue;

		const recorded =
			report.kind === 'echo'
				? await client.recordEcho({
						target_connection_id: connectionId,
						target_psid: report.psid,
						target_mid: report.mid,
						target_metadata: report.metadata,
						target_text: report.text,
						target_sent_at: report.sentAt,
						target_from_this_app: ourAppId !== null && report.appId === ourAppId
					})
				: await client.recordReceipt({
						target_connection_id: connectionId,
						target_psid: report.psid,
						target_kind: report.kind,
						target_watermark: report.watermark,
						target_mids: report.mids
					});
		if (recorded.error)
			throw new Error(`Recording a Page report failed: ${recorded.error.message}`);
	}
}

export async function drainMessengerWebhookEvents(
	options: {
		client?: MessengerInboundWorkerClient;
		batchSize?: number;
		maxBatches?: number;
		// Our Meta app: an echo carrying it was sent from UCRM, anything else from the Page's own inbox.
		ourAppId?: string | null;
	} = {}
): Promise<MessengerDrainResult> {
	const client = resolveClient(options.client);
	const ourAppId =
		options.ourAppId === undefined ? env.META_APP_ID?.trim() || null : options.ourAppId;
	const batchSize = options.batchSize ?? BATCH_SIZE;
	const result: MessengerDrainResult = { claimed: 0, processed: 0, failed: 0 };

	for (let batch = 0; batch < (options.maxBatches ?? MAX_BATCHES); batch++) {
		const claimed = await client.claim(batchSize);
		if (claimed.error)
			throw new Error(`Claiming Messenger deliveries failed: ${claimed.error.message}`);
		const events = claimed.data ?? [];
		result.claimed += events.length;

		for (const event of events) {
			if (!event.claim_token) continue;
			let failure: string | null = null;
			try {
				await processEvent(client, event, ourAppId);
			} catch (error) {
				failure = error instanceof Error ? error.message : String(error);
			}
			// Unfinished claims are retaken after five minutes, so a failed finish only delays the retry.
			const finished = await client.finish(event.id, event.claim_token, failure);
			if (finished.error)
				console.error('Could not mark a Messenger delivery as handled.', finished.error);
			if (failure) {
				result.failed += 1;
				console.error('A Messenger delivery could not be processed; it will be retried.', {
					id: event.id,
					error: failure
				});
			} else {
				result.processed += 1;
			}
		}

		if (events.length < batchSize) break;
	}

	return result;
}
