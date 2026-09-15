import { describe, it, expect, beforeEach } from 'vitest';
import { randomUUID } from 'node:crypto';
import { encryptTwilioCredential, type TwilioCredentialKeyring } from './twilio-credential-crypto';
import type {
	InsertCredentialInput,
	ProvisioningEventInput,
	StoredTwilioAccount,
	StoredTwilioCredential,
	TwilioProvisioningStore
} from './twilio-provisioning-store';
import type {
	CreateMessagingServiceInput,
	CreateRestrictedApiKeyInput,
	FoundApiKey,
	SubaccountAuthInput,
	TwilioProvisioningClient
} from './twilio';
import {
	adoptPhoneNumber,
	adoptTwilioSubaccount,
	provisionTwilioForOrganization,
	rotateAuthToken,
	rotateRestrictedKey,
	type TwilioProvisioningDeps
} from './twilio-provisioning';

const ORG = 'a2100000-0000-4000-8000-000000000099';
const SUBACCOUNT = 'AC00000000000000000000000000000001';
const KEY_SID = 'SK00000000000000000000000000000001';
const KEY_SID_2 = 'SK00000000000000000000000000000002';
const MESSAGING_SERVICE = 'MG00000000000000000000000000000001';
const PHONE_NUMBER_SID = 'PN00000000000000000000000000000001';

const keyring: TwilioCredentialKeyring = {
	activeKeyId: 'v1',
	keys: new Map([['v1', new Uint8Array(32).fill(7)]])
};

// --- In-memory store that enforces the real "one current per (account, purpose, lifecycle)" invariant ---
type StoredCred = StoredTwilioCredential & {
	accountId: string;
	organizationId: string;
	retireAfter: string | null;
};

function createFakeStore() {
	const accounts: StoredTwilioAccount[] = [];
	const creds: StoredCred[] = [];
	const events: ProvisioningEventInput[] = [];
	const senderIdentities: {
		id: string;
		organizationId: string;
		phoneNumber: string;
		displayName: string | null;
	}[] = [];

	function assertUniqueLifecycle(accountId: string, purpose: string, lifecycle: string) {
		const clash = creds.find(
			(c) => c.accountId === accountId && c.purpose === purpose && c.lifecycleState === lifecycle
		);
		if (clash) throw new Error(`invariant: duplicate ${purpose}/${lifecycle}`);
	}

	const store: TwilioProvisioningStore = {
		async getAccount(organizationId) {
			return accounts.find((a) => a.organizationId === organizationId) ?? null;
		},
		async getAccountBySubaccountSid(subaccountSid) {
			return accounts.find((a) => a.subaccountSid === subaccountSid) ?? null;
		},
		async storeProvisionedSubaccount({
			organizationId,
			subaccountSid,
			authTokenCredentialId,
			encrypted
		}) {
			if (accounts.some((a) => a.organizationId === organizationId)) {
				throw new Error('invariant: duplicate account for organization');
			}
			const account: StoredTwilioAccount = {
				id: randomUUID(),
				organizationId,
				subaccountSid,
				messagingServiceSid: null,
				lifecycleState: 'provisioning'
			};
			accounts.push(account);
			creds.push({
				id: authTokenCredentialId,
				accountId: account.id,
				organizationId,
				purpose: 'auth_token',
				lifecycleState: 'current',
				credentialSid: null,
				encrypted,
				retireAfter: null
			});
			return account;
		},
		async setMessagingService({ accountId, messagingServiceSid }) {
			const account = accounts.find((a) => a.id === accountId);
			if (account) account.messagingServiceSid = messagingServiceSid;
		},
		async setAccountLifecycle({ accountId, lifecycleState }) {
			const account = accounts.find((a) => a.id === accountId);
			if (account) account.lifecycleState = lifecycleState;
		},
		async getCredential({ accountId, purpose, lifecycleState }) {
			return (
				creds.find(
					(c) =>
						c.accountId === accountId &&
						c.purpose === purpose &&
						c.lifecycleState === lifecycleState
				) ?? null
			);
		},
		async insertCredential(input: InsertCredentialInput) {
			assertUniqueLifecycle(input.accountId, input.purpose, input.lifecycleState);
			creds.push({
				id: input.id,
				accountId: input.accountId,
				organizationId: input.organizationId,
				purpose: input.purpose,
				lifecycleState: input.lifecycleState,
				credentialSid: input.credentialSid,
				encrypted: input.encrypted,
				retireAfter: input.retireAfter ?? null
			});
		},
		async deleteStagedCredential({ accountId, purpose }) {
			for (let i = creds.length - 1; i >= 0; i--) {
				if (
					creds[i].accountId === accountId &&
					creds[i].purpose === purpose &&
					creds[i].lifecycleState === 'staged'
				) {
					creds.splice(i, 1);
				}
			}
		},
		async completeAuthTokenRotation({ accountId, retireAfter }) {
			const staged = creds.filter(
				(c) =>
					c.accountId === accountId && c.purpose === 'auth_token' && c.lifecycleState === 'staged'
			);
			const current = creds.filter(
				(c) =>
					c.accountId === accountId && c.purpose === 'auth_token' && c.lifecycleState === 'current'
			);
			if (staged.length !== 1 || current.length !== 1) {
				throw new Error('invariant: rotation requires one staged and one current');
			}
			for (let i = creds.length - 1; i >= 0; i--) {
				if (
					creds[i].accountId === accountId &&
					creds[i].purpose === 'auth_token' &&
					creds[i].lifecycleState === 'prior'
				) {
					creds.splice(i, 1);
				}
			}
			current[0].lifecycleState = 'prior';
			current[0].retireAfter = retireAfter;
			staged[0].lifecycleState = 'current';
			staged[0].retireAfter = null;
		},
		async completeRestrictedKeyRotation({ accountId }) {
			const staged = creds.filter(
				(c) =>
					c.accountId === accountId &&
					c.purpose === 'restricted_api_key' &&
					c.lifecycleState === 'staged'
			);
			const current = creds.filter(
				(c) =>
					c.accountId === accountId &&
					c.purpose === 'restricted_api_key' &&
					c.lifecycleState === 'current'
			);
			if (staged.length !== 1 || current.length !== 1) {
				throw new Error('invariant: rotation requires one staged and one current');
			}
			const idx = creds.indexOf(current[0]);
			creds.splice(idx, 1);
			staged[0].lifecycleState = 'current';
		},
		async recordEvent(input) {
			events.push(input);
		},
		async insertSenderIdentity({ organizationId, phoneNumber, displayName }) {
			const id = randomUUID();
			senderIdentities.push({ id, organizationId, phoneNumber, displayName });
			return { id };
		}
	};

	return { store, accounts, creds, events, senderIdentities };
}

// --- Fake Twilio adapter with a call log and injectable behavior ---
type TwilioCall = { method: string; args: unknown };

function createFakeTwilio(
	behavior: Partial<{
		findSubaccount: () => { subaccountSid: string; status: string } | null;
		fetchSubaccountBySid: () => { subaccountSid: string; authToken: string; status: string };
		addPhoneNumberToMessagingService: () => void;
		listApiKeys: () => FoundApiKey[];
		verifyAuthToken: (token: string) => boolean;
		verifyRestrictedApiKey: (keySid: string) => boolean;
		nextKeySid: () => string;
		nextSecondaryToken: () => string;
	}> = {}
) {
	const calls: TwilioCall[] = [];
	const record = (method: string, args: unknown) => calls.push({ method, args });

	const twilio: TwilioProvisioningClient = {
		async createSubaccount(friendlyName) {
			record('createSubaccount', friendlyName);
			return { subaccountSid: SUBACCOUNT, authToken: 'authtoken-primary', status: 'active' };
		},
		async findSubaccount(friendlyName) {
			record('findSubaccount', friendlyName);
			return behavior.findSubaccount ? behavior.findSubaccount() : null;
		},
		async fetchSubaccountBySid(subaccountSid) {
			record('fetchSubaccountBySid', subaccountSid);
			return behavior.fetchSubaccountBySid
				? behavior.fetchSubaccountBySid()
				: { subaccountSid, authToken: 'authtoken-adopted', status: 'active' };
		},
		async addPhoneNumberToMessagingService(input) {
			record('addPhoneNumberToMessagingService', input);
			if (behavior.addPhoneNumberToMessagingService) behavior.addPhoneNumberToMessagingService();
			return { phoneNumberSid: input.phoneNumberSid };
		},
		async createRestrictedApiKey(input: CreateRestrictedApiKeyInput) {
			record('createRestrictedApiKey', input);
			return {
				keySid: behavior.nextKeySid ? behavior.nextKeySid() : KEY_SID,
				secret: 'key-secret'
			};
		},
		async listApiKeys(input: SubaccountAuthInput) {
			record('listApiKeys', input);
			return behavior.listApiKeys ? behavior.listApiKeys() : [];
		},
		async deleteApiKey(input) {
			record('deleteApiKey', input);
		},
		async createMessagingService(input: CreateMessagingServiceInput) {
			record('createMessagingService', input);
			return { messagingServiceSid: MESSAGING_SERVICE };
		},
		async findMessagingService(input) {
			record('findMessagingService', input);
			return null;
		},
		async createSecondaryAuthToken(input) {
			record('createSecondaryAuthToken', input);
			return {
				secondaryAuthToken: behavior.nextSecondaryToken
					? behavior.nextSecondaryToken()
					: 'authtoken-secondary'
			};
		},
		async deleteSecondaryAuthToken(input) {
			record('deleteSecondaryAuthToken', input);
		},
		async promoteAuthToken(input) {
			record('promoteAuthToken', input);
		},
		async verifyAuthToken(input) {
			record('verifyAuthToken', input);
			return behavior.verifyAuthToken ? behavior.verifyAuthToken(input.authToken) : true;
		},
		async verifyRestrictedApiKey(input) {
			record('verifyRestrictedApiKey', input);
			return behavior.verifyRestrictedApiKey ? behavior.verifyRestrictedApiKey(input.keySid) : true;
		}
	};

	return { twilio, calls };
}

function countCalls(calls: TwilioCall[], method: string): number {
	return calls.filter((c) => c.method === method).length;
}

const PROVISION_INPUT = {
	organizationId: ORG,
	inboundRequestUrl: 'https://app.example.com/api/webhooks/twilio/inbound',
	statusCallback: 'https://app.example.com/api/webhooks/twilio/status'
};

describe('provisionTwilioForOrganization', () => {
	let fakeStore: ReturnType<typeof createFakeStore>;

	beforeEach(() => {
		fakeStore = createFakeStore();
	});

	function deps(twilio: TwilioProvisioningClient): TwilioProvisioningDeps {
		return { store: fakeStore.store, twilio, keyring };
	}

	it('provisions a subaccount, Restricted key and Messaging Service to a ready state', async () => {
		const { twilio, calls } = createFakeTwilio();
		const summary = await provisionTwilioForOrganization(deps(twilio), PROVISION_INPUT);

		expect(summary).toEqual({
			organizationId: ORG,
			subaccountSid: SUBACCOUNT,
			messagingServiceSid: MESSAGING_SERVICE,
			restrictedKeySid: KEY_SID,
			lifecycleState: 'ready'
		});
		expect(countCalls(calls, 'createSubaccount')).toBe(1);
		expect(countCalls(calls, 'createRestrictedApiKey')).toBe(1);
		expect(countCalls(calls, 'createMessagingService')).toBe(1);
		// Auth Token (current) + Restricted key (current) are stored.
		expect(fakeStore.creds).toHaveLength(2);
	});

	it('is idempotent: a repeated run creates nothing new', async () => {
		const first = createFakeTwilio();
		await provisionTwilioForOrganization(deps(first.twilio), PROVISION_INPUT);

		const second = createFakeTwilio();
		const summary = await provisionTwilioForOrganization(deps(second.twilio), PROVISION_INPUT);

		expect(summary.lifecycleState).toBe('ready');
		expect(countCalls(second.calls, 'createSubaccount')).toBe(0);
		expect(countCalls(second.calls, 'createRestrictedApiKey')).toBe(0);
		expect(countCalls(second.calls, 'createMessagingService')).toBe(0);
		expect(fakeStore.creds).toHaveLength(2);
	});

	it('resumes after a crash that left only the subaccount and Auth Token', async () => {
		// Seed a partially provisioned account (subaccount + auth token only).
		const authId = randomUUID();
		await fakeStore.store.storeProvisionedSubaccount({
			organizationId: ORG,
			subaccountSid: SUBACCOUNT,
			authTokenCredentialId: authId,
			encrypted: encryptTwilioCredential(
				'authtoken-primary',
				{
					organizationId: ORG,
					credentialId: authId,
					subaccountSid: SUBACCOUNT,
					purpose: 'auth_token'
				},
				keyring
			)
		});

		const { twilio, calls } = createFakeTwilio();
		const summary = await provisionTwilioForOrganization(deps(twilio), PROVISION_INPUT);

		expect(summary.lifecycleState).toBe('ready');
		expect(countCalls(calls, 'createSubaccount')).toBe(0);
		expect(countCalls(calls, 'createRestrictedApiKey')).toBe(1);
		expect(countCalls(calls, 'createMessagingService')).toBe(1);
	});

	it('refuses to duplicate a subaccount and stops for review when an orphan is found', async () => {
		const { twilio, calls } = createFakeTwilio({
			findSubaccount: () => ({ subaccountSid: SUBACCOUNT, status: 'active' })
		});
		await expect(
			provisionTwilioForOrganization(deps(twilio), PROVISION_INPUT)
		).rejects.toMatchObject({
			code: 'twilio_orphan_subaccount',
			retryable: false
		});
		expect(countCalls(calls, 'createSubaccount')).toBe(0);
		expect(fakeStore.events.at(-1)).toMatchObject({
			step: 'subaccount_created',
			result: 'needs_review'
		});
	});

	it('deletes an orphaned Restricted key before creating a fresh one', async () => {
		// Account + auth token already exist, plus an orphan key at Twilio carrying our name.
		const authId = randomUUID();
		const acct = await fakeStore.store.storeProvisionedSubaccount({
			organizationId: ORG,
			subaccountSid: SUBACCOUNT,
			authTokenCredentialId: authId,
			encrypted: encryptTwilioCredential(
				'authtoken-primary',
				{
					organizationId: ORG,
					credentialId: authId,
					subaccountSid: SUBACCOUNT,
					purpose: 'auth_token'
				},
				keyring
			)
		});
		expect(acct).toBeTruthy();

		const { twilio, calls } = createFakeTwilio({
			listApiKeys: () => [{ keySid: KEY_SID_2, friendlyName: `ucrm-org-${ORG}-messaging` }]
		});
		await provisionTwilioForOrganization(deps(twilio), PROVISION_INPUT);

		expect(countCalls(calls, 'deleteApiKey')).toBe(1);
		expect(
			(calls.find((c) => c.method === 'deleteApiKey')?.args as { keySid: string }).keySid
		).toBe(KEY_SID_2);
		expect(countCalls(calls, 'createRestrictedApiKey')).toBe(1);
	});

	it('targets the correct subaccount and uses the least-privilege Messaging policy', async () => {
		const { twilio, calls } = createFakeTwilio();
		await provisionTwilioForOrganization(deps(twilio), PROVISION_INPUT);

		const keyCall = calls.find((c) => c.method === 'createRestrictedApiKey')
			?.args as CreateRestrictedApiKeyInput;
		expect(keyCall.subaccountSid).toBe(SUBACCOUNT);
		expect(keyCall.subaccountAuthToken).toBe('authtoken-primary');
		expect(keyCall.policy.allow).toContain('/twilio/messaging/messages/create');
	});

	it('never exposes a secret in the summary or recorded history', async () => {
		const { twilio } = createFakeTwilio();
		const summary = await provisionTwilioForOrganization(deps(twilio), PROVISION_INPUT);

		const serialized = JSON.stringify({ summary, events: fakeStore.events });
		expect(serialized).not.toContain('authtoken-primary');
		expect(serialized).not.toContain('key-secret');
	});
});

describe('rotateAuthToken', () => {
	let fakeStore: ReturnType<typeof createFakeStore>;

	beforeEach(async () => {
		fakeStore = createFakeStore();
		const first = createFakeTwilio();
		await provisionTwilioForOrganization(
			{ store: fakeStore.store, twilio: first.twilio, keyring },
			PROVISION_INPUT
		);
	});

	function deps(twilio: TwilioProvisioningClient): TwilioProvisioningDeps {
		return { store: fakeStore.store, twilio, keyring };
	}

	it('stages, verifies, promotes and flips to the new token with a prior retirement window', async () => {
		const { twilio, calls } = createFakeTwilio({ nextSecondaryToken: () => 'authtoken-secondary' });
		await rotateAuthToken(deps(twilio), { organizationId: ORG, priorTokenRetentionMs: 3_600_000 });

		expect(countCalls(calls, 'createSecondaryAuthToken')).toBe(1);
		expect(countCalls(calls, 'promoteAuthToken')).toBe(1);

		const current = await fakeStore.store.getCredential({
			accountId: fakeStore.accounts[0].id,
			purpose: 'auth_token',
			lifecycleState: 'current'
		});
		const prior = fakeStore.creds.find(
			(c) => c.purpose === 'auth_token' && c.lifecycleState === 'prior'
		);
		expect(current).toBeTruthy();
		expect(prior).toBeTruthy();
		expect(prior?.retireAfter).toBeTruthy();
	});

	it('rolls back before promotion when the new token fails verification', async () => {
		const { twilio, calls } = createFakeTwilio({
			verifyAuthToken: (token) => token !== 'authtoken-secondary'
		});
		await expect(
			rotateAuthToken(deps(twilio), { organizationId: ORG, priorTokenRetentionMs: 3_600_000 })
		).rejects.toMatchObject({ code: 'twilio_rotation_verification_failed' });

		expect(countCalls(calls, 'promoteAuthToken')).toBe(0);
		expect(countCalls(calls, 'deleteSecondaryAuthToken')).toBe(1);
		// Old token remains the only current; no staged left behind.
		const staged = fakeStore.creds.find(
			(c) => c.purpose === 'auth_token' && c.lifecycleState === 'staged'
		);
		expect(staged).toBeUndefined();
		expect(fakeStore.events.at(-1)).toMatchObject({ result: 'rolled_back' });
	});

	it('resumes forward when a prior run promoted but never flipped', async () => {
		const account = fakeStore.accounts[0];
		// Simulate an interrupted rotation: a staged token exists and Twilio has already promoted it (old dead).
		const stagedId = randomUUID();
		await fakeStore.store.insertCredential({
			id: stagedId,
			organizationId: ORG,
			accountId: account.id,
			purpose: 'auth_token',
			lifecycleState: 'staged',
			credentialSid: null,
			encrypted: encryptTwilioCredential(
				'authtoken-secondary',
				{
					organizationId: ORG,
					credentialId: stagedId,
					subaccountSid: account.subaccountSid,
					purpose: 'auth_token'
				},
				keyring
			)
		});

		const { twilio, calls } = createFakeTwilio({
			// Old primary is dead; only the staged (secondary) token is accepted.
			verifyAuthToken: (token) => token === 'authtoken-secondary'
		});
		await rotateAuthToken(deps(twilio), { organizationId: ORG, priorTokenRetentionMs: 3_600_000 });

		// No new secondary created and no second promotion; it simply completes the flip.
		expect(countCalls(calls, 'createSecondaryAuthToken')).toBe(0);
		expect(countCalls(calls, 'promoteAuthToken')).toBe(0);
		const current = fakeStore.creds.find(
			(c) => c.purpose === 'auth_token' && c.lifecycleState === 'current'
		);
		expect(current?.id).toBe(stagedId);
	});
});

describe('rotateRestrictedKey', () => {
	let fakeStore: ReturnType<typeof createFakeStore>;

	beforeEach(async () => {
		fakeStore = createFakeStore();
		const first = createFakeTwilio();
		await provisionTwilioForOrganization(
			{ store: fakeStore.store, twilio: first.twilio, keyring },
			PROVISION_INPUT
		);
	});

	function deps(twilio: TwilioProvisioningClient): TwilioProvisioningDeps {
		return { store: fakeStore.store, twilio, keyring };
	}

	it('creates, verifies, cuts over to a new key and deletes the old one', async () => {
		const { twilio, calls } = createFakeTwilio({ nextKeySid: () => KEY_SID_2 });
		const summary = await rotateRestrictedKey(deps(twilio), { organizationId: ORG });

		expect(summary.restrictedKeySid).toBe(KEY_SID_2);
		expect(countCalls(calls, 'createRestrictedApiKey')).toBe(1);
		expect(countCalls(calls, 'deleteApiKey')).toBe(1);
		expect(
			(calls.find((c) => c.method === 'deleteApiKey')?.args as { keySid: string }).keySid
		).toBe(KEY_SID);
		const current = fakeStore.creds.find(
			(c) => c.purpose === 'restricted_api_key' && c.lifecycleState === 'current'
		);
		expect(current?.credentialSid).toBe(KEY_SID_2);
		// Exactly one restricted key remains (no staged, no old current).
		expect(fakeStore.creds.filter((c) => c.purpose === 'restricted_api_key')).toHaveLength(1);
	});

	it('rolls back and keeps the old key when the new one fails verification', async () => {
		const { twilio, calls } = createFakeTwilio({
			nextKeySid: () => KEY_SID_2,
			verifyRestrictedApiKey: (keySid) => keySid !== KEY_SID_2
		});
		await expect(rotateRestrictedKey(deps(twilio), { organizationId: ORG })).rejects.toMatchObject({
			code: 'twilio_rotation_verification_failed'
		});
		// The unverified new key is deleted; the original stays current.
		const current = fakeStore.creds.find(
			(c) => c.purpose === 'restricted_api_key' && c.lifecycleState === 'current'
		);
		expect(current?.credentialSid).toBe(KEY_SID);
		expect(
			calls
				.filter((c) => c.method === 'deleteApiKey')
				.map((c) => (c.args as { keySid: string }).keySid)
		).toContain(KEY_SID_2);
	});
});

describe('adoptTwilioSubaccount', () => {
	let fakeStore: ReturnType<typeof createFakeStore>;

	beforeEach(() => {
		fakeStore = createFakeStore();
	});

	function deps(twilio: TwilioProvisioningClient): TwilioProvisioningDeps {
		return { store: fakeStore.store, twilio, keyring };
	}

	const ADOPT_INPUT = {
		organizationId: ORG,
		subaccountSid: SUBACCOUNT,
		inboundRequestUrl: PROVISION_INPUT.inboundRequestUrl,
		statusCallback: PROVISION_INPUT.statusCallback
	};

	it('adopts an out-of-band subaccount to a ready state without calling createSubaccount', async () => {
		const { twilio, calls } = createFakeTwilio();
		const summary = await adoptTwilioSubaccount(deps(twilio), ADOPT_INPUT);

		expect(summary).toEqual({
			organizationId: ORG,
			subaccountSid: SUBACCOUNT,
			messagingServiceSid: MESSAGING_SERVICE,
			restrictedKeySid: KEY_SID,
			lifecycleState: 'ready'
		});
		expect(countCalls(calls, 'fetchSubaccountBySid')).toBe(1);
		expect(countCalls(calls, 'createSubaccount')).toBe(0);
		expect(countCalls(calls, 'createRestrictedApiKey')).toBe(1);
		expect(countCalls(calls, 'createMessagingService')).toBe(1);
		expect(fakeStore.events.at(-1)?.step).toBe('provisioning_completed');
		expect(
			fakeStore.events.some((e) => e.step === 'subaccount_adopted' && e.result === 'succeeded')
		).toBe(true);
	});

	it('refuses when the organization already has a Twilio account on record', async () => {
		const first = createFakeTwilio();
		await adoptTwilioSubaccount(deps(first.twilio), ADOPT_INPUT);

		const second = createFakeTwilio();
		await expect(adoptTwilioSubaccount(deps(second.twilio), ADOPT_INPUT)).rejects.toMatchObject({
			code: 'twilio_already_provisioned'
		});
		expect(countCalls(second.calls, 'fetchSubaccountBySid')).toBe(0);
	});

	it('refuses to adopt a subaccount that is not active', async () => {
		const { twilio, calls } = createFakeTwilio({
			fetchSubaccountBySid: () => ({
				subaccountSid: SUBACCOUNT,
				authToken: 'authtoken-adopted',
				status: 'suspended'
			})
		});
		await expect(adoptTwilioSubaccount(deps(twilio), ADOPT_INPUT)).rejects.toMatchObject({
			code: 'twilio_subaccount_not_active'
		});
		expect(countCalls(calls, 'createRestrictedApiKey')).toBe(0);
		expect(fakeStore.events.at(-1)).toMatchObject({
			step: 'subaccount_adopted',
			result: 'needs_review'
		});
	});

	it('never exposes the fetched Auth Token in the summary or recorded history', async () => {
		const { twilio } = createFakeTwilio();
		const summary = await adoptTwilioSubaccount(deps(twilio), ADOPT_INPUT);

		const serialized = JSON.stringify({ summary, events: fakeStore.events });
		expect(serialized).not.toContain('authtoken-adopted');
	});
});

describe('adoptPhoneNumber', () => {
	let fakeStore: ReturnType<typeof createFakeStore>;

	beforeEach(async () => {
		fakeStore = createFakeStore();
		const first = createFakeTwilio();
		await provisionTwilioForOrganization(
			{ store: fakeStore.store, twilio: first.twilio, keyring },
			PROVISION_INPUT
		);
	});

	function deps(twilio: TwilioProvisioningClient): TwilioProvisioningDeps {
		return { store: fakeStore.store, twilio, keyring };
	}

	const ADOPT_NUMBER_INPUT = {
		organizationId: ORG,
		phoneNumberSid: PHONE_NUMBER_SID,
		phoneNumber: '+13613262553',
		displayName: 'UCRM internal test'
	};

	it('attaches the number to the Messaging Service and records a sender identity', async () => {
		const { twilio, calls } = createFakeTwilio();
		const summary = await adoptPhoneNumber(deps(twilio), ADOPT_NUMBER_INPUT);

		expect(summary.phoneNumber).toBe('+13613262553');
		expect(summary.messagingServiceSid).toBe(MESSAGING_SERVICE);
		expect(countCalls(calls, 'addPhoneNumberToMessagingService')).toBe(1);
		expect(fakeStore.senderIdentities).toHaveLength(1);
		expect(fakeStore.senderIdentities[0]).toMatchObject({
			organizationId: ORG,
			phoneNumber: '+13613262553',
			displayName: 'UCRM internal test'
		});
		expect(fakeStore.events.at(-1)).toMatchObject({
			step: 'phone_number_attached',
			result: 'succeeded'
		});
	});

	it('refuses when the organization has no Twilio account yet', async () => {
		const emptyStore = createFakeStore();
		const { twilio } = createFakeTwilio();
		await expect(
			adoptPhoneNumber({ store: emptyStore.store, twilio, keyring }, ADOPT_NUMBER_INPUT)
		).rejects.toMatchObject({ code: 'twilio_not_provisioned' });
	});
});
