import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type {
	EmailSetup,
	EmailSetupRequest,
	MailboxProvider
} from '$lib/communications/email-setup';

type Client = SupabaseClient<Database>;
type RequestRow = Database['public']['Tables']['communication_email_setup_requests']['Row'];

export type SendingDomainFact = { lifecycle_state: string; created_at: string };

export class EmailSetupRequestError extends Error {
	constructor(
		message: string,
		public readonly status: number
	) {
		super(message);
		this.name = 'EmailSetupRequestError';
	}
}

export function publicRequest(row: RequestRow): EmailSetupRequest {
	return {
		id: row.id,
		root_domain: row.root_domain,
		mailbox_provider: row.mailbox_provider as MailboxProvider,
		note: row.note,
		created_at: row.created_at,
		closed_note: row.closed_note,
		closed_at: row.closed_at
	};
}

/**
 * "Setting up" and "Ready" are never stored on the request; they are read from the sending domains. A request
 * counts as acted on once a sending domain exists that was created after it (a removed one included, so an old
 * ask is never revived by a later removal).
 */
export function deriveEmailSetup(
	latest: RequestRow | null,
	sendingDomains: SendingDomainFact[]
): EmailSetup {
	const live = sendingDomains.filter((domain) => domain.lifecycle_state !== 'removed');
	if (live.some((domain) => domain.lifecycle_state === 'verified')) {
		return { state: 'ready', request: latest ? publicRequest(latest) : null };
	}
	const request = latest ? publicRequest(latest) : null;
	if (live.length > 0) return { state: 'setting_up', request };
	if (latest?.status === 'open') return { state: 'waiting', request };
	if (latest?.status === 'declined') return { state: 'declined', request };
	return { state: 'none', request: null };
}

export async function loadEmailSetup(client: Client, organizationId: string): Promise<EmailSetup> {
	const [latest, domains] = await Promise.all([
		client
			.from('communication_email_setup_requests')
			.select('*')
			.eq('organization_id', organizationId)
			.order('created_at', { ascending: false })
			.limit(1)
			.maybeSingle(),
		client
			.from('communication_email_domains')
			.select('lifecycle_state, created_at')
			.eq('organization_id', organizationId)
			.eq('purpose', 'sending')
	]);
	if (latest.error) throw latest.error;
	if (domains.error) throw domains.error;
	return deriveEmailSetup(latest.data, domains.data ?? []);
}

function commandError(error: { code?: string; message?: string }, fallback: string) {
	if (error.code === 'P0409' || error.code === '23505')
		return new EmailSetupRequestError(error.message || fallback, 409);
	if (error.code === 'P0002' || error.code === 'no_data_found')
		return new EmailSetupRequestError('That request was not found.', 404);
	if (error.code === '23514')
		return new EmailSetupRequestError('Please review the request details.', 422);
	return null;
}

export async function createEmailSetupRequest(
	client: Client,
	input: {
		organizationId: string;
		actorId: string;
		rootDomain: string;
		mailboxProvider: MailboxProvider;
		note: string | null;
	}
) {
	const { data, error } = await client.rpc('communication_email_setup_request_create', {
		p_organization_id: input.organizationId,
		p_actor_id: input.actorId,
		p_root_domain: input.rootDomain,
		p_mailbox_provider: input.mailboxProvider,
		p_note: input.note ?? ''
	});
	if (error) throw commandError(error, 'The request could not be sent.') ?? error;
	return data;
}

export async function cancelEmailSetupRequest(
	client: Client,
	organizationId: string,
	requestId: string
) {
	const { data, error } = await client.rpc('communication_email_setup_request_cancel', {
		p_organization_id: organizationId,
		p_request_id: requestId
	});
	if (error) throw commandError(error, 'The request could not be cancelled.') ?? error;
	return data;
}

export async function closeEmailSetupRequest(client: Client, requestId: string, note: string) {
	const { data, error } = await client.rpc('communication_email_setup_request_close', {
		p_request_id: requestId,
		p_note: note
	});
	if (error) throw commandError(error, 'The request could not be closed.') ?? error;
	return data;
}
