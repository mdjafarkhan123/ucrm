import { randomUUID } from 'node:crypto';
import Stripe from 'stripe';
import { env } from '$env/dynamic/private';
import type { Database } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	decryptStripeSecret,
	encryptStripeSecret,
	type EncryptedStripeSecret,
	type StripeSecretPurpose
} from './stripe-credential-crypto';

// A contractor's own Stripe account, connected with ONE pasted restricted key
// (docs/online-payments-behavior-contract.md §1). Connect verifies the key, creates the webhook endpoint in
// the contractor's account (the create response is the only time Stripe returns its signing secret), and
// stores both secrets encrypted in a service-role-only table. Nothing in this module returns a secret to a
// caller outside it; the status shape below is the only thing routes serialize.

type ConnectionRow = Database['public']['Tables']['payment_stripe_connections']['Row'];

export type StripeCheckStatus =
	'ok' | 'key_rejected' | 'permission_missing' | 'account_unavailable' | 'webhook_missing';

export type StripeConnectionStatus =
	| { connected: false }
	| {
			connected: true;
			account_name: string | null;
			stripe_account_id: string;
			livemode: boolean;
			key_last4: string;
			connected_at: string;
			last_checked_at: string;
			last_check_status: StripeCheckStatus;
	  };

export type StripeConnectFailure = {
	ok: false;
	reason:
		| 'key_rejected'
		| 'permission_missing'
		| 'stripe_unavailable'
		| 'not_configured'
		| 'storage_failed';
};

/** The events Parts 3–5 act on. Everything else stays off so the endpoint carries no unrelated traffic.
 *  Refund confirmation uses the `refund.*` events, not `charge.refunded`/`charge.refund.updated`: on this
 *  account's API version, `charge.refunded` arrives with its `refunds` list empty and `charge.refund.updated`
 *  never fires at all, so the aggregate/legacy charge events carry no usable refund data. `refund.*` events
 *  hand the Refund object itself. */
export const STRIPE_WEBHOOK_EVENTS: Stripe.WebhookEndpointCreateParams.EnabledEvent[] = [
	'checkout.session.completed',
	'checkout.session.async_payment_succeeded',
	'checkout.session.async_payment_failed',
	'refund.created',
	'refund.updated',
	'refund.failed',
	'charge.dispute.created'
];

const COLUMNS =
	'id, organization_id, stripe_account_id, account_display_name, livemode, api_key_last4, webhook_endpoint_id, encryption_key_id, api_key_nonce, api_key_ciphertext, api_key_tag, webhook_secret_nonce, webhook_secret_ciphertext, webhook_secret_tag, connected_by, connected_at, last_checked_at, last_check_status, last_event_received_at, updated_at';

export function stripeClient(apiKey: string) {
	return new Stripe(apiKey, { maxNetworkRetries: 1, timeout: 20_000 });
}

/** The webhook URL for one connection. Built from APP_URL, never the incoming request, so a proxy cannot
 *  steer Stripe's notifications somewhere else. */
export function stripeWebhookUrl(connectionId: string): string {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin) throw new Error('APP_URL must be set before Stripe can be connected.');
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:') throw new Error('APP_URL must use HTTPS for Stripe webhooks.');
	return `${origin.origin}/api/webhooks/stripe/${connectionId}`;
}

function stripeErrorReason(
	error: unknown
): 'key_rejected' | 'permission_missing' | 'stripe_unavailable' {
	const type = (error as { type?: string } | null)?.type;
	if (type === 'StripeAuthenticationError') return 'key_rejected';
	if (type === 'StripePermissionError') return 'permission_missing';
	return 'stripe_unavailable';
}

function isMissingResource(error: unknown) {
	const value = error as { type?: string; code?: string; statusCode?: number } | null;
	return value?.code === 'resource_missing' || value?.statusCode === 404;
}

function accountName(account: Stripe.Account): string | null {
	const name =
		account.settings?.dashboard?.display_name ||
		account.business_profile?.name ||
		account.email ||
		null;
	return name ? name.slice(0, 200) : null;
}

function toHex(bytes: Uint8Array) {
	return `\\x${Buffer.from(bytes).toString('hex')}`;
}

function fromHex(value: string): Uint8Array {
	const hex = value.startsWith('\\x') ? value.slice(2) : value;
	return new Uint8Array(Buffer.from(hex, 'hex'));
}

function envelope(row: ConnectionRow, purpose: StripeSecretPurpose): EncryptedStripeSecret {
	return purpose === 'api_key'
		? {
				keyId: row.encryption_key_id,
				nonce: fromHex(row.api_key_nonce),
				ciphertext: fromHex(row.api_key_ciphertext),
				authenticationTag: fromHex(row.api_key_tag)
			}
		: {
				keyId: row.encryption_key_id,
				nonce: fromHex(row.webhook_secret_nonce),
				ciphertext: fromHex(row.webhook_secret_ciphertext),
				authenticationTag: fromHex(row.webhook_secret_tag)
			};
}

function decryptFromRow(row: ConnectionRow, purpose: StripeSecretPurpose) {
	return decryptStripeSecret(envelope(row, purpose), {
		organizationId: row.organization_id,
		connectionId: row.id,
		purpose
	});
}

function toStatus(row: ConnectionRow | null): StripeConnectionStatus {
	if (!row) return { connected: false };
	return {
		connected: true,
		account_name: row.account_display_name,
		stripe_account_id: row.stripe_account_id,
		livemode: row.livemode,
		key_last4: row.api_key_last4,
		connected_at: row.connected_at,
		last_checked_at: row.last_checked_at,
		last_check_status: row.last_check_status as StripeCheckStatus
	};
}

async function loadRow(organizationId: string): Promise<ConnectionRow | null> {
	const { data, error } = await getOwnerSupabaseClient()
		.from('payment_stripe_connections')
		.select(COLUMNS)
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw error;
	return data;
}

async function recordAudit(organizationId: string, actorUserId: string, change: string) {
	const { error } = await getOwnerSupabaseClient()
		.from('organization_settings_audit')
		.insert({
			organization_id: organizationId,
			section: 'stripe_connection',
			changed_fields: [change],
			actor_user_id: actorUserId
		});
	if (error) console.error('Could not record the Stripe connection audit entry.', error.code);
}

/** A Stripe client acting with this organization's stored key, or null when Stripe is not connected. The key
 *  itself never leaves this module. */
export async function stripeClientForOrganization(
	organizationId: string
): Promise<{ stripe: Stripe; stripeAccountId: string } | null> {
	const row = await loadRow(organizationId);
	if (!row) return null;
	return {
		stripe: stripeClient(decryptFromRow(row, 'api_key')),
		stripeAccountId: row.stripe_account_id
	};
}

export async function getStripeConnectionStatus(
	organizationId: string
): Promise<StripeConnectionStatus> {
	return toStatus(await loadRow(organizationId));
}

/** Connect, or replace the key of, this organization's Stripe account. */
export async function connectStripe(input: {
	organizationId: string;
	actorUserId: string;
	apiKey: string;
}): Promise<{ ok: true; status: StripeConnectionStatus } | StripeConnectFailure> {
	const stripe = stripeClient(input.apiKey);

	let account: Stripe.Account;
	try {
		account = await stripe.accounts.retrieveCurrent();
	} catch (error) {
		return { ok: false, reason: stripeErrorReason(error) };
	}

	const previous = await loadRow(input.organizationId);
	const connectionId = randomUUID();

	let url: string;
	try {
		url = stripeWebhookUrl(connectionId);
	} catch {
		return { ok: false, reason: 'not_configured' };
	}

	let endpoint: Stripe.WebhookEndpoint;
	try {
		endpoint = await stripe.webhookEndpoints.create({
			url,
			enabled_events: STRIPE_WEBHOOK_EVENTS,
			api_version: Stripe.API_VERSION as Stripe.WebhookEndpointCreateParams.ApiVersion,
			description: 'UCRM online payments — created automatically. Do not delete.',
			metadata: { ucrm_organization_id: input.organizationId, ucrm_connection_id: connectionId }
		});
	} catch (error) {
		return { ok: false, reason: stripeErrorReason(error) };
	}

	const removeNewEndpoint = () => stripe.webhookEndpoints.del(endpoint.id).catch(() => undefined);

	if (!endpoint.secret) {
		await removeNewEndpoint();
		return { ok: false, reason: 'stripe_unavailable' };
	}

	let apiKeyEnvelope: EncryptedStripeSecret;
	let secretEnvelope: EncryptedStripeSecret;
	try {
		const context = { organizationId: input.organizationId, connectionId };
		apiKeyEnvelope = encryptStripeSecret(input.apiKey, { ...context, purpose: 'api_key' });
		secretEnvelope = encryptStripeSecret(endpoint.secret, {
			...context,
			purpose: 'webhook_secret'
		});
	} catch {
		await removeNewEndpoint();
		return { ok: false, reason: 'not_configured' };
	}

	const now = new Date().toISOString();
	const { data: stored, error: storeError } = await getOwnerSupabaseClient()
		.from('payment_stripe_connections')
		.upsert(
			{
				id: connectionId,
				organization_id: input.organizationId,
				stripe_account_id: account.id,
				account_display_name: accountName(account),
				livemode: endpoint.livemode,
				api_key_last4: input.apiKey.slice(-4),
				webhook_endpoint_id: endpoint.id,
				encryption_key_id: apiKeyEnvelope.keyId,
				api_key_nonce: toHex(apiKeyEnvelope.nonce),
				api_key_ciphertext: toHex(apiKeyEnvelope.ciphertext),
				api_key_tag: toHex(apiKeyEnvelope.authenticationTag),
				webhook_secret_nonce: toHex(secretEnvelope.nonce),
				webhook_secret_ciphertext: toHex(secretEnvelope.ciphertext),
				webhook_secret_tag: toHex(secretEnvelope.authenticationTag),
				connected_by: input.actorUserId,
				connected_at: now,
				last_checked_at: now,
				last_check_status: 'ok',
				last_event_received_at: null,
				updated_at: now
			},
			{ onConflict: 'organization_id' }
		)
		.select(COLUMNS)
		.single();

	if (storeError || !stored) {
		await removeNewEndpoint();
		return { ok: false, reason: 'storage_failed' };
	}

	await removeStaleEndpoints({ stripe, organizationId: input.organizationId, previous });
	await recordAudit(
		input.organizationId,
		input.actorUserId,
		previous ? 'key_replaced' : 'connected'
	);

	return { ok: true, status: toStatus(stored) };
}

// Best effort: delete every UCRM endpoint for this organization except the one the stored connection uses.
// Re-reading the stored row first means two admins connecting at once cannot delete the winner's endpoint.
// When the old key belonged to a different Stripe account, its endpoint is removed with the old key.
async function removeStaleEndpoints(input: {
	stripe: Stripe;
	organizationId: string;
	previous: ConnectionRow | null;
}) {
	try {
		const current = await loadRow(input.organizationId);
		if (!current) return;

		const endpoints = await input.stripe.webhookEndpoints.list({ limit: 100 });
		for (const candidate of endpoints.data) {
			if (
				candidate.metadata?.ucrm_organization_id === input.organizationId &&
				candidate.id !== current.webhook_endpoint_id
			) {
				await input.stripe.webhookEndpoints.del(candidate.id).catch(() => undefined);
			}
		}

		const previous = input.previous;
		if (previous && previous.stripe_account_id !== current.stripe_account_id) {
			await stripeClient(decryptFromRow(previous, 'api_key'))
				.webhookEndpoints.del(previous.webhook_endpoint_id)
				.catch(() => undefined);
		}
	} catch {
		// A leftover endpoint only ever receives events its URL can no longer verify; nothing to surface.
	}
}

export async function disconnectStripe(input: { organizationId: string; actorUserId: string }) {
	const row = await loadRow(input.organizationId);
	if (!row) return { ok: true as const };

	const stripe = stripeClient(decryptFromRow(row, 'api_key'));

	try {
		await stripe.webhookEndpoints.del(row.webhook_endpoint_id);
	} catch {
		// A revoked key or an endpoint already deleted in Stripe must never block disconnecting.
	}

	await expireOpenCheckouts({ stripe, organizationId: input.organizationId });

	const { error } = await getOwnerSupabaseClient()
		.from('payment_stripe_connections')
		.delete()
		.eq('id', row.id);
	if (error) throw error;

	await recordAudit(input.organizationId, input.actorUserId, 'disconnected');
	return { ok: true as const };
}

// A customer can be sitting on a live Stripe Checkout page when the contractor disconnects. Once the
// connection row is gone, verifyStripeWebhook can no longer find a signing secret for it, so a payment that
// completes after this point would be lost money with no record. Expire every open session first (while the
// key is still valid to call Stripe) and mark those attempts failed, so the customer sees a stopped payment
// instead of one that silently vanishes.
async function expireOpenCheckouts(input: { stripe: Stripe; organizationId: string }) {
	const db = getOwnerSupabaseClient();
	const { data: openCheckouts, error } = await db
		.from('payment_stripe_checkouts')
		.select('id, checkout_session_id')
		.eq('organization_id', input.organizationId)
		.eq('status', 'open');
	if (error || !openCheckouts?.length) return;

	for (const checkout of openCheckouts) {
		if (checkout.checkout_session_id) {
			await input.stripe.checkout.sessions
				.expire(checkout.checkout_session_id)
				.catch(() => undefined);
		}
		await db
			.from('payment_stripe_checkouts')
			.update({ status: 'failed', updated_at: new Date().toISOString() })
			.eq('id', checkout.id)
			.eq('status', 'open');
	}
}

/** Re-check the stored key and webhook endpoint, and record the result. */
export async function checkStripeConnection(
	organizationId: string
): Promise<StripeConnectionStatus> {
	const row = await loadRow(organizationId);
	if (!row) return { connected: false };

	let status: StripeCheckStatus = 'ok';
	let name = row.account_display_name;
	try {
		const stripe = stripeClient(decryptFromRow(row, 'api_key'));
		const account = await stripe.accounts.retrieveCurrent();
		name = accountName(account);
		try {
			const endpoint = await stripe.webhookEndpoints.retrieve(row.webhook_endpoint_id);
			if (endpoint.status !== 'enabled') status = 'webhook_missing';
		} catch (error) {
			status = isMissingResource(error) ? 'webhook_missing' : checkStatusFor(error);
		}
	} catch (error) {
		status = checkStatusFor(error);
	}

	const { data, error } = await getOwnerSupabaseClient()
		.from('payment_stripe_connections')
		.update({
			last_checked_at: new Date().toISOString(),
			last_check_status: status,
			account_display_name: name,
			updated_at: new Date().toISOString()
		})
		.eq('id', row.id)
		.select(COLUMNS)
		.maybeSingle();
	if (error) throw error;
	return toStatus(data);
}

function checkStatusFor(error: unknown): StripeCheckStatus {
	const reason = stripeErrorReason(error);
	return reason === 'stripe_unavailable' ? 'account_unavailable' : reason;
}

/** Verify a webhook delivery against the signing secret of the connection its URL names. Returns the event
 *  only when the signature is valid; the caller acknowledges anything else with a 400. */
export async function verifyStripeWebhook(input: {
	connectionId: string;
	payload: string;
	signature: string;
}): Promise<{ event: Stripe.Event; organizationId: string } | null> {
	const { data: row, error } = await getOwnerSupabaseClient()
		.from('payment_stripe_connections')
		.select(COLUMNS)
		.eq('id', input.connectionId)
		.maybeSingle();
	if (error) throw error;
	if (!row) return null;

	let event: Stripe.Event;
	try {
		const secret = decryptFromRow(row, 'webhook_secret');
		event = await Stripe.webhooks.constructEventAsync(input.payload, input.signature, secret);
	} catch {
		return null;
	}

	await getOwnerSupabaseClient()
		.from('payment_stripe_connections')
		.update({ last_event_received_at: new Date().toISOString() })
		.eq('id', row.id);

	return { event, organizationId: row.organization_id };
}
