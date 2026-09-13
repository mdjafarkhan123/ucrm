import { randomUUID } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	decryptTwilioCredential,
	encryptTwilioCredential,
	getTwilioCredentialKeyring,
	type TwilioCredentialKeyring,
	type TwilioCredentialPurpose
} from './twilio-credential-crypto';
import {
	buildRestrictedKeyMessagingPolicy,
	createTwilioProvisioningClient,
	TwilioProvisioningError,
	type TwilioProvisioningClient
} from './twilio';
import {
	createSupabaseTwilioProvisioningStore,
	type StoredTwilioAccount,
	type StoredTwilioCredential,
	type TwilioProvisioningStore
} from './twilio-provisioning-store';

// The Twilio provisioning saga (A2 Stage 2B). A desired-state reconciler, like the email-domain activation
// saga: every step is idempotent, no database transaction is held across a Twilio call, and a repeated owner
// click or a resume after a crash reconciles the known Twilio SIDs instead of creating a second subaccount,
// key, or Messaging Service. Twilio offers no idempotency key for these creates, so reconciliation is anchored
// on a deterministic per-organization FriendlyName.
//
// Rotation follows Twilio's staged-secondary model: stage and durably store the new secret, verify it, then
// promote (which permanently kills the old one at Twilio), then atomically flip the local pointers. Rollback
// is possible only before promotion; after promotion, recovery moves forward with the new secret.

export type TwilioProvisioningSummary = {
	organizationId: string;
	subaccountSid: string;
	messagingServiceSid: string | null;
	restrictedKeySid: string | null;
	lifecycleState: string;
};

export type TwilioProvisioningDeps = {
	store: TwilioProvisioningStore;
	twilio: TwilioProvisioningClient;
	keyring: TwilioCredentialKeyring;
	now?: () => Date;
};

export type ProvisionInput = {
	organizationId: string;
	inboundRequestUrl: string;
	statusCallback: string;
};

export type RotateAuthTokenInput = {
	organizationId: string;
	// The local grace window during which a just-retired Auth Token is still accepted for late webhook
	// retries only (Twilio itself no longer accepts it). Its production value is set from the configured
	// Messaging product's webhook retry behavior verified in staging -- never guessed in code -- so the caller
	// supplies it explicitly.
	priorTokenRetentionMs: number;
};

function friendlyNames(organizationId: string) {
	const base = `ucrm-org-${organizationId}`;
	return {
		subaccount: base,
		restrictedKey: `${base}-messaging`,
		messagingService: `${base}-messaging`
	};
}

function credentialContext(
	account: StoredTwilioAccount,
	credentialId: string,
	purpose: TwilioCredentialPurpose
) {
	return {
		organizationId: account.organizationId,
		credentialId,
		subaccountSid: account.subaccountSid,
		purpose
	};
}

function decryptCredential(
	keyring: TwilioCredentialKeyring,
	account: StoredTwilioAccount,
	credential: StoredTwilioCredential
): string {
	return decryptTwilioCredential(
		credential.encrypted,
		credentialContext(account, credential.id, credential.purpose),
		keyring
	);
}

function summarize(
	account: StoredTwilioAccount,
	restrictedKeySid: string | null
): TwilioProvisioningSummary {
	return {
		organizationId: account.organizationId,
		subaccountSid: account.subaccountSid,
		messagingServiceSid: account.messagingServiceSid,
		restrictedKeySid,
		lifecycleState: account.lifecycleState
	};
}

/**
 * Bring an organization's Twilio setup to a ready state: subaccount + encrypted Auth Token, a least-privilege
 * Restricted API key, and a Messaging Service. Safe to call repeatedly; each already-completed step is skipped.
 */
export async function provisionTwilioForOrganization(
	deps: TwilioProvisioningDeps,
	input: ProvisionInput
): Promise<TwilioProvisioningSummary> {
	const { store, twilio, keyring } = deps;
	const { organizationId, inboundRequestUrl, statusCallback } = input;
	const names = friendlyNames(organizationId);

	// --- Step 1: subaccount + current Auth Token ---
	let account = await store.getAccount(organizationId);
	let authToken: string;

	if (!account) {
		const existing = await twilio.findSubaccount(names.subaccount);
		if (existing) {
			// A subaccount with our deterministic name exists but we hold no record of it: its Auth Token was
			// returned once at creation and is unrecoverable. We refuse to guess a recovery and stop for review
			// rather than risk creating a duplicate or stranding an inaccessible account.
			await store.recordEvent({
				organizationId,
				operation: 'provision',
				step: 'subaccount_created',
				result: 'needs_review',
				detail: { reason: 'orphan_subaccount_found', subaccount_sid: existing.subaccountSid }
			});
			throw new TwilioProvisioningError(
				'A Twilio subaccount already exists for this organization but its credentials are not on record.',
				null,
				'twilio_orphan_subaccount',
				false
			);
		}

		const created = await twilio.createSubaccount(names.subaccount);
		const credentialId = randomUUID();
		const encrypted = encryptTwilioCredential(
			created.authToken,
			credentialContext(
				{ organizationId, subaccountSid: created.subaccountSid } as StoredTwilioAccount,
				credentialId,
				'auth_token'
			),
			keyring
		);
		account = await store.storeProvisionedSubaccount({
			organizationId,
			subaccountSid: created.subaccountSid,
			authTokenCredentialId: credentialId,
			encrypted
		});
		authToken = created.authToken;
		await store.recordEvent({
			organizationId,
			accountId: account.id,
			operation: 'provision',
			step: 'subaccount_created',
			result: 'succeeded',
			detail: { subaccount_sid: created.subaccountSid }
		});
	} else {
		const current = await store.getCredential({
			accountId: account.id,
			purpose: 'auth_token',
			lifecycleState: 'current'
		});
		if (!current) {
			await store.recordEvent({
				organizationId,
				accountId: account.id,
				operation: 'provision',
				step: 'subaccount_created',
				result: 'needs_review',
				detail: { reason: 'missing_auth_token' }
			});
			throw new TwilioProvisioningError(
				'The Twilio subaccount record has no current Auth Token; operator review required.',
				null,
				'twilio_missing_auth_token',
				false
			);
		}
		authToken = decryptCredential(keyring, account, current);
		await store.recordEvent({
			organizationId,
			accountId: account.id,
			operation: 'provision',
			step: 'subaccount_created',
			result: 'skipped'
		});
	}

	// --- Step 2: least-privilege Restricted API key ---
	let restrictedKey = await store.getCredential({
		accountId: account.id,
		purpose: 'restricted_api_key',
		lifecycleState: 'current'
	});

	if (!restrictedKey) {
		// Any key already carrying our name is an orphan: we never stored its secret (Twilio returns it once),
		// so it is unusable. Delete before creating a fresh one, keeping exactly one usable key.
		const existingKeys = await twilio.listApiKeys({
			subaccountSid: account.subaccountSid,
			subaccountAuthToken: authToken
		});
		const orphans = existingKeys.filter((key) => key.friendlyName === names.restrictedKey);
		for (const orphan of orphans) {
			await twilio.deleteApiKey({
				subaccountSid: account.subaccountSid,
				subaccountAuthToken: authToken,
				keySid: orphan.keySid
			});
			await store.recordEvent({
				organizationId,
				accountId: account.id,
				operation: 'provision',
				step: 'orphan_key_deleted',
				result: 'succeeded',
				detail: { key_sid: orphan.keySid }
			});
		}

		const credentialId = randomUUID();
		const created = await twilio.createRestrictedApiKey({
			subaccountSid: account.subaccountSid,
			subaccountAuthToken: authToken,
			friendlyName: names.restrictedKey,
			policy: buildRestrictedKeyMessagingPolicy()
		});
		const encrypted = encryptTwilioCredential(
			created.secret,
			credentialContext(account, credentialId, 'restricted_api_key'),
			keyring
		);
		await store.insertCredential({
			id: credentialId,
			organizationId,
			accountId: account.id,
			purpose: 'restricted_api_key',
			lifecycleState: 'current',
			credentialSid: created.keySid,
			encrypted
		});
		restrictedKey = {
			id: credentialId,
			purpose: 'restricted_api_key',
			lifecycleState: 'current',
			credentialSid: created.keySid,
			encrypted
		};
		await store.recordEvent({
			organizationId,
			accountId: account.id,
			operation: 'provision',
			step: 'restricted_key_created',
			result: 'succeeded',
			detail: { key_sid: created.keySid }
		});
	} else {
		await store.recordEvent({
			organizationId,
			accountId: account.id,
			operation: 'provision',
			step: 'restricted_key_created',
			result: 'skipped'
		});
	}

	// --- Step 3: Messaging Service ---
	if (!account.messagingServiceSid) {
		const existing = await twilio.findMessagingService({
			subaccountSid: account.subaccountSid,
			subaccountAuthToken: authToken,
			friendlyName: names.messagingService
		});
		const messagingServiceSid = existing
			? existing.messagingServiceSid
			: (
					await twilio.createMessagingService({
						subaccountSid: account.subaccountSid,
						subaccountAuthToken: authToken,
						friendlyName: names.messagingService,
						inboundRequestUrl,
						statusCallback
					})
				).messagingServiceSid;
		await store.setMessagingService({ accountId: account.id, messagingServiceSid });
		account = { ...account, messagingServiceSid };
		await store.recordEvent({
			organizationId,
			accountId: account.id,
			operation: 'provision',
			step: existing ? 'messaging_service_adopted' : 'messaging_service_created',
			result: 'succeeded',
			detail: { messaging_service_sid: messagingServiceSid }
		});
	} else {
		await store.recordEvent({
			organizationId,
			accountId: account.id,
			operation: 'provision',
			step: 'messaging_service_created',
			result: 'skipped'
		});
	}

	// --- Step 4: mark ready ---
	if (account.lifecycleState !== 'ready') {
		await store.setAccountLifecycle({ accountId: account.id, lifecycleState: 'ready' });
		account = { ...account, lifecycleState: 'ready' };
		await store.recordEvent({
			organizationId,
			accountId: account.id,
			operation: 'provision',
			step: 'provisioning_completed',
			result: 'succeeded'
		});
	}

	return summarize(account, restrictedKey?.credentialSid ?? null);
}

async function requireAccount(
	store: TwilioProvisioningStore,
	organizationId: string
): Promise<StoredTwilioAccount> {
	const account = await store.getAccount(organizationId);
	if (!account) {
		throw new TwilioProvisioningError(
			'This organization has no Twilio subaccount to rotate.',
			null,
			'twilio_not_provisioned',
			false
		);
	}
	return account;
}

/**
 * Rotate the subaccount Auth Token: stage a secondary token, verify it, promote it (permanently retiring the
 * old one at Twilio), then flip the local pointers with a bounded prior-token retirement window. Rollback is
 * possible only before promotion; an interrupted rotation resumes forward.
 */
export async function rotateAuthToken(
	deps: TwilioProvisioningDeps,
	input: RotateAuthTokenInput
): Promise<TwilioProvisioningSummary> {
	const { store, twilio, keyring } = deps;
	const now = deps.now ?? (() => new Date());
	const account = await requireAccount(store, input.organizationId);

	const current = await store.getCredential({
		accountId: account.id,
		purpose: 'auth_token',
		lifecycleState: 'current'
	});
	if (!current) {
		throw new TwilioProvisioningError(
			'No current Auth Token to rotate.',
			null,
			'twilio_missing_auth_token',
			false
		);
	}
	const currentToken = decryptCredential(keyring, account, current);
	const retireAfter = new Date(now().getTime() + input.priorTokenRetentionMs).toISOString();

	// Resume an interrupted rotation: a staged token means a previous run created (and maybe promoted) a
	// secondary. Decide forward based on which token Twilio still accepts.
	const staged = await store.getCredential({
		accountId: account.id,
		purpose: 'auth_token',
		lifecycleState: 'staged'
	});
	if (staged) {
		const stagedToken = decryptCredential(keyring, account, staged);
		if (await twilio.verifyAuthToken({ subaccountSid: account.subaccountSid, authToken: stagedToken })) {
			const currentStillLive = await twilio.verifyAuthToken({
				subaccountSid: account.subaccountSid,
				authToken: currentToken
			});
			if (currentStillLive) {
				// Staged never promoted: finish the promotion, then flip.
				await twilio.promoteAuthToken({
					subaccountSid: account.subaccountSid,
					secondaryAuthToken: stagedToken
				});
			}
			await store.completeAuthTokenRotation({ accountId: account.id, retireAfter });
			await store.recordEvent({
				organizationId: input.organizationId,
				accountId: account.id,
				operation: 'rotate_auth_token',
				step: 'auth_token_rotated',
				result: 'succeeded',
				detail: { resumed: true }
			});
			return summarize(account, null);
		}
		// Staged token is not accepted: a failed/stale secondary. Discard it and start a fresh rotation.
		await store.deleteStagedCredential({ accountId: account.id, purpose: 'auth_token' });
		try {
			await twilio.deleteSecondaryAuthToken({
				subaccountSid: account.subaccountSid,
				currentAuthToken: currentToken
			});
		} catch {
			// The secondary may already be gone; a fresh rotation is still safe.
		}
	}

	const secondary = await twilio.createSecondaryAuthToken({
		subaccountSid: account.subaccountSid,
		currentAuthToken: currentToken
	});
	const stagedId = randomUUID();
	const stagedEncrypted = encryptTwilioCredential(
		secondary.secondaryAuthToken,
		credentialContext(account, stagedId, 'auth_token'),
		keyring
	);
	// Store the new token durably BEFORE promotion, so promotion can never strand us without the new secret.
	await store.deleteStagedCredential({ accountId: account.id, purpose: 'auth_token' });
	await store.insertCredential({
		id: stagedId,
		organizationId: input.organizationId,
		accountId: account.id,
		purpose: 'auth_token',
		lifecycleState: 'staged',
		credentialSid: null,
		encrypted: stagedEncrypted
	});

	if (
		!(await twilio.verifyAuthToken({
			subaccountSid: account.subaccountSid,
			authToken: secondary.secondaryAuthToken
		}))
	) {
		// Rollback before promotion: the old token is untouched at Twilio.
		await store.deleteStagedCredential({ accountId: account.id, purpose: 'auth_token' });
		try {
			await twilio.deleteSecondaryAuthToken({
				subaccountSid: account.subaccountSid,
				currentAuthToken: currentToken
			});
		} catch {
			// Best effort; the unverified secondary carries no access we rely on.
		}
		await store.recordEvent({
			organizationId: input.organizationId,
			accountId: account.id,
			operation: 'rotate_auth_token',
			step: 'auth_token_rotated',
			result: 'rolled_back',
			detail: { reason: 'secondary_verification_failed' }
		});
		throw new TwilioProvisioningError(
			'The new Auth Token could not be verified; rotation was rolled back.',
			null,
			'twilio_rotation_verification_failed',
			true
		);
	}

	await twilio.promoteAuthToken({
		subaccountSid: account.subaccountSid,
		secondaryAuthToken: secondary.secondaryAuthToken
	});
	await store.completeAuthTokenRotation({ accountId: account.id, retireAfter });
	await store.recordEvent({
		organizationId: input.organizationId,
		accountId: account.id,
		operation: 'rotate_auth_token',
		step: 'auth_token_rotated',
		result: 'succeeded'
	});
	return summarize(account, null);
}

/**
 * Rotate the Restricted API key: create a new one, verify it, atomically cut over, then delete the old key at
 * Twilio. There is no retry window because a Restricted key authenticates only outbound API calls.
 */
export async function rotateRestrictedKey(
	deps: TwilioProvisioningDeps,
	input: { organizationId: string }
): Promise<TwilioProvisioningSummary> {
	const { store, twilio, keyring } = deps;
	const account = await requireAccount(store, input.organizationId);
	const names = friendlyNames(input.organizationId);

	const authTokenCredential = await store.getCredential({
		accountId: account.id,
		purpose: 'auth_token',
		lifecycleState: 'current'
	});
	if (!authTokenCredential) {
		throw new TwilioProvisioningError(
			'No Auth Token available to manage Restricted keys.',
			null,
			'twilio_missing_auth_token',
			false
		);
	}
	const authToken = decryptCredential(keyring, account, authTokenCredential);

	const current = await store.getCredential({
		accountId: account.id,
		purpose: 'restricted_api_key',
		lifecycleState: 'current'
	});
	if (!current || !current.credentialSid) {
		throw new TwilioProvisioningError(
			'No current Restricted key to rotate.',
			null,
			'twilio_missing_restricted_key',
			false
		);
	}

	// Resume an interrupted rotation.
	const staged = await store.getCredential({
		accountId: account.id,
		purpose: 'restricted_api_key',
		lifecycleState: 'staged'
	});
	if (staged && staged.credentialSid) {
		const stagedSecret = decryptCredential(keyring, account, staged);
		if (
			await twilio.verifyRestrictedApiKey({
				subaccountSid: account.subaccountSid,
				keySid: staged.credentialSid,
				keySecret: stagedSecret
			})
		) {
			const oldKeySid = current.credentialSid;
			await store.completeRestrictedKeyRotation({ accountId: account.id });
			await deleteKeyBestEffort(twilio, account.subaccountSid, authToken, oldKeySid);
			await store.recordEvent({
				organizationId: input.organizationId,
				accountId: account.id,
				operation: 'rotate_restricted_key',
				step: 'restricted_key_rotated',
				result: 'succeeded',
				detail: { resumed: true, key_sid: staged.credentialSid }
			});
			return summarize({ ...account }, staged.credentialSid);
		}
		// Stale staged key: discard at Twilio and locally, then start fresh.
		await deleteKeyBestEffort(twilio, account.subaccountSid, authToken, staged.credentialSid);
		await store.deleteStagedCredential({ accountId: account.id, purpose: 'restricted_api_key' });
	}

	const stagedId = randomUUID();
	const created = await twilio.createRestrictedApiKey({
		subaccountSid: account.subaccountSid,
		subaccountAuthToken: authToken,
		friendlyName: names.restrictedKey,
		policy: buildRestrictedKeyMessagingPolicy()
	});
	const stagedEncrypted = encryptTwilioCredential(
		created.secret,
		credentialContext(account, stagedId, 'restricted_api_key'),
		keyring
	);
	await store.deleteStagedCredential({ accountId: account.id, purpose: 'restricted_api_key' });
	await store.insertCredential({
		id: stagedId,
		organizationId: input.organizationId,
		accountId: account.id,
		purpose: 'restricted_api_key',
		lifecycleState: 'staged',
		credentialSid: created.keySid,
		encrypted: stagedEncrypted
	});

	if (
		!(await twilio.verifyRestrictedApiKey({
			subaccountSid: account.subaccountSid,
			keySid: created.keySid,
			keySecret: created.secret
		}))
	) {
		await deleteKeyBestEffort(twilio, account.subaccountSid, authToken, created.keySid);
		await store.deleteStagedCredential({ accountId: account.id, purpose: 'restricted_api_key' });
		await store.recordEvent({
			organizationId: input.organizationId,
			accountId: account.id,
			operation: 'rotate_restricted_key',
			step: 'restricted_key_rotated',
			result: 'rolled_back',
			detail: { reason: 'new_key_verification_failed' }
		});
		throw new TwilioProvisioningError(
			'The new Restricted key could not be verified; rotation was rolled back.',
			null,
			'twilio_rotation_verification_failed',
			true
		);
	}

	const oldKeySid = current.credentialSid;
	await store.completeRestrictedKeyRotation({ accountId: account.id });
	await deleteKeyBestEffort(twilio, account.subaccountSid, authToken, oldKeySid);
	await store.recordEvent({
		organizationId: input.organizationId,
		accountId: account.id,
		operation: 'rotate_restricted_key',
		step: 'restricted_key_rotated',
		result: 'succeeded',
		detail: { key_sid: created.keySid }
	});
	return summarize({ ...account }, created.keySid);
}

async function deleteKeyBestEffort(
	twilio: TwilioProvisioningClient,
	subaccountSid: string,
	subaccountAuthToken: string,
	keySid: string
): Promise<void> {
	try {
		await twilio.deleteApiKey({ subaccountSid, subaccountAuthToken, keySid });
	} catch {
		// A leftover key at Twilio that we no longer reference is a harmless orphan; do not fail the cutover.
	}
}

/** Wire the real Supabase store, live Twilio adapter, and server keyring. */
export function createTwilioProvisioningDeps(): TwilioProvisioningDeps {
	return {
		store: createSupabaseTwilioProvisioningStore(getOwnerSupabaseClient()),
		twilio: createTwilioProvisioningClient(),
		keyring: getTwilioCredentialKeyring()
	};
}
