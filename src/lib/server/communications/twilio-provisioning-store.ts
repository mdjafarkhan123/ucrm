import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import type {
	EncryptedTwilioCredential,
	TwilioCredentialPurpose
} from './twilio-credential-crypto';

// The durable-state boundary for the Twilio provisioning saga. The saga depends on this port, never on
// Supabase directly, so its logic is driven in tests against an in-memory fake and every atomic transition is
// exercised without a live database. The real implementation below wraps the service-role client and the
// Stage 2B transition RPCs. State is derived entirely from these records -- the saga keeps no separate machine.

export type TwilioCredentialLifecycle = 'staged' | 'current' | 'prior';

export type StoredTwilioAccount = {
	id: string;
	organizationId: string;
	subaccountSid: string;
	messagingServiceSid: string | null;
	lifecycleState: string;
};

export type StoredTwilioCredential = {
	id: string;
	purpose: TwilioCredentialPurpose;
	lifecycleState: TwilioCredentialLifecycle;
	credentialSid: string | null;
	encrypted: EncryptedTwilioCredential;
};

export type InsertCredentialInput = {
	id: string;
	organizationId: string;
	accountId: string;
	purpose: TwilioCredentialPurpose;
	lifecycleState: TwilioCredentialLifecycle;
	credentialSid: string | null;
	encrypted: EncryptedTwilioCredential;
	retireAfter?: string | null;
};

export type ProvisioningEventInput = {
	organizationId: string;
	accountId?: string | null;
	operation: 'provision' | 'rotate_auth_token' | 'rotate_restricted_key';
	step: string;
	result: 'succeeded' | 'skipped' | 'rolled_back' | 'needs_review' | 'failed';
	detail?: Record<string, unknown>;
};

export type TwilioProvisioningStore = {
	getAccount(organizationId: string): Promise<StoredTwilioAccount | null>;
	/** Atomic: create the account record and its first (current) Auth Token together. */
	storeProvisionedSubaccount(input: {
		organizationId: string;
		subaccountSid: string;
		authTokenCredentialId: string;
		encrypted: EncryptedTwilioCredential;
	}): Promise<StoredTwilioAccount>;
	setMessagingService(input: { accountId: string; messagingServiceSid: string }): Promise<void>;
	setAccountLifecycle(input: { accountId: string; lifecycleState: string }): Promise<void>;
	getCredential(input: {
		accountId: string;
		purpose: TwilioCredentialPurpose;
		lifecycleState: TwilioCredentialLifecycle;
	}): Promise<StoredTwilioCredential | null>;
	insertCredential(input: InsertCredentialInput): Promise<void>;
	deleteStagedCredential(input: {
		accountId: string;
		purpose: TwilioCredentialPurpose;
	}): Promise<void>;
	/** Atomic cutover: demote current -> prior (with retirement) and promote staged -> current. */
	completeAuthTokenRotation(input: { accountId: string; retireAfter: string }): Promise<void>;
	/** Atomic cutover: drop old current and promote staged -> current (no retry window). */
	completeRestrictedKeyRotation(input: { accountId: string }): Promise<void>;
	recordEvent(input: ProvisioningEventInput): Promise<void>;
};

type AccountRow = Database['public']['Tables']['communication_twilio_accounts']['Row'];
type CredentialRow = Database['public']['Tables']['communication_twilio_credentials']['Row'];

function mapAccount(row: AccountRow): StoredTwilioAccount {
	return {
		id: row.id,
		organizationId: row.organization_id,
		subaccountSid: row.subaccount_sid,
		messagingServiceSid: row.messaging_service_sid,
		lifecycleState: row.lifecycle_state
	};
}

function toBytes(value: CredentialRow['nonce']): Uint8Array {
	// Supabase returns bytea as a hex string prefixed with \x; normalize to bytes.
	if (typeof value === 'string') {
		const hex = value.startsWith('\\x') ? value.slice(2) : value;
		return new Uint8Array(Buffer.from(hex, 'hex'));
	}
	return new Uint8Array(value as unknown as ArrayBufferLike);
}

function toHex(bytes: Uint8Array): string {
	return `\\x${Buffer.from(bytes).toString('hex')}`;
}

function mapCredential(row: CredentialRow): StoredTwilioCredential {
	return {
		id: row.id,
		purpose: row.credential_purpose as TwilioCredentialPurpose,
		lifecycleState: row.lifecycle_state as TwilioCredentialLifecycle,
		credentialSid: row.credential_sid,
		encrypted: {
			algorithm: 'aes-256-gcm',
			formatVersion: 1,
			keyId: row.encryption_key_id,
			nonce: toBytes(row.nonce),
			ciphertext: toBytes(row.ciphertext),
			authenticationTag: toBytes(row.authentication_tag)
		}
	};
}

class TwilioProvisioningStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'TwilioProvisioningStoreError';
	}
}

export function createSupabaseTwilioProvisioningStore(
	client: SupabaseClient<Database>
): TwilioProvisioningStore {
	return {
		async getAccount(organizationId) {
			const { data, error } = await client
				.from('communication_twilio_accounts')
				.select('*')
				.eq('organization_id', organizationId)
				.maybeSingle();
			if (error) throw new TwilioProvisioningStoreError('Could not read the Twilio account.');
			return data ? mapAccount(data) : null;
		},

		async storeProvisionedSubaccount({
			organizationId,
			subaccountSid,
			authTokenCredentialId,
			encrypted
		}) {
			const { data, error } = await client
				.rpc('communication_twilio_store_provisioned_subaccount', {
					p_organization_id: organizationId,
					p_subaccount_sid: subaccountSid,
					p_auth_token_credential_id: authTokenCredentialId,
					p_encryption_key_id: encrypted.keyId,
					p_nonce: toHex(encrypted.nonce),
					p_ciphertext: toHex(encrypted.ciphertext),
					p_authentication_tag: toHex(encrypted.authenticationTag)
				})
				.single();
			if (error)
				throw new TwilioProvisioningStoreError('Could not store the provisioned subaccount.');
			return mapAccount(data as AccountRow);
		},

		async setMessagingService({ accountId, messagingServiceSid }) {
			const { error } = await client
				.from('communication_twilio_accounts')
				.update({ messaging_service_sid: messagingServiceSid })
				.eq('id', accountId);
			if (error) throw new TwilioProvisioningStoreError('Could not store the Messaging Service.');
		},

		async setAccountLifecycle({ accountId, lifecycleState }) {
			const { error } = await client
				.from('communication_twilio_accounts')
				.update({ lifecycle_state: lifecycleState })
				.eq('id', accountId);
			if (error) throw new TwilioProvisioningStoreError('Could not update the account lifecycle.');
		},

		async getCredential({ accountId, purpose, lifecycleState }) {
			const { data, error } = await client
				.from('communication_twilio_credentials')
				.select('*')
				.eq('twilio_account_id', accountId)
				.eq('credential_purpose', purpose)
				.eq('lifecycle_state', lifecycleState)
				.maybeSingle();
			if (error) throw new TwilioProvisioningStoreError('Could not read a Twilio credential.');
			return data ? mapCredential(data) : null;
		},

		async insertCredential(input) {
			const { error } = await client.from('communication_twilio_credentials').insert({
				id: input.id,
				organization_id: input.organizationId,
				twilio_account_id: input.accountId,
				credential_purpose: input.purpose,
				lifecycle_state: input.lifecycleState,
				credential_sid: input.credentialSid,
				encryption_key_id: input.encrypted.keyId,
				nonce: toHex(input.encrypted.nonce),
				ciphertext: toHex(input.encrypted.ciphertext),
				authentication_tag: toHex(input.encrypted.authenticationTag),
				retire_after: input.retireAfter ?? null
			});
			if (error) throw new TwilioProvisioningStoreError('Could not store a Twilio credential.');
		},

		async deleteStagedCredential({ accountId, purpose }) {
			const { error } = await client
				.from('communication_twilio_credentials')
				.delete()
				.eq('twilio_account_id', accountId)
				.eq('credential_purpose', purpose)
				.eq('lifecycle_state', 'staged');
			if (error) throw new TwilioProvisioningStoreError('Could not clear a staged credential.');
		},

		async completeAuthTokenRotation({ accountId, retireAfter }) {
			const { error } = await client.rpc('communication_twilio_complete_auth_token_rotation', {
				p_account_id: accountId,
				p_retire_after: retireAfter
			});
			if (error) throw new TwilioProvisioningStoreError('Could not complete Auth Token rotation.');
		},

		async completeRestrictedKeyRotation({ accountId }) {
			const { error } = await client.rpc('communication_twilio_complete_restricted_key_rotation', {
				p_account_id: accountId
			});
			if (error)
				throw new TwilioProvisioningStoreError('Could not complete Restricted key rotation.');
		},

		async recordEvent(input) {
			const { error } = await client.from('communication_twilio_provisioning_events').insert({
				organization_id: input.organizationId,
				twilio_account_id: input.accountId ?? null,
				operation: input.operation,
				step: input.step,
				result: input.result,
				detail: (input.detail ?? {}) as Json
			});
			// History is best-effort observability: a failed audit insert must never mask the operation outcome.
			if (error) console.error('Failed to record Twilio provisioning event', { step: input.step });
		}
	};
}
