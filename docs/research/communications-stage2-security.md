# Communications Stage 2 security research

**Date:** 2026-09-13  
**Scope:** Twilio credentials, webhook verification, encryption-key operations, and Supabase Vault  
**Sources:** Current official Twilio, Supabase, NIST, and AWS documentation only

## Decision summary

The approved tenant boundary remains correct: use one Twilio subaccount per contractor. Twilio explicitly presents
subaccounts as the way for a hosted service to segment each customer's resources and activity, and subaccount
credentials cannot access the main account or another subaccount. Twilio's default limit is 1,000 subaccounts, so
the planned 100–200 organization launch is inside the documented default but the 40,000-user product target is not
evidence of account capacity; organization count must be tracked separately and Twilio Support is required before
exceeding that default. [Twilio: Subaccounts](https://www.twilio.com/docs/iam/api/subaccounts)

Two corrections are required before Stage 2 implementation:

1. **Separate outbound API authority from webhook-signing authority.** Create a subaccount-level Restricted API key
   with only the exact Messaging and setup/read permissions UCRM needs. Use its SID and secret for ordinary Twilio
   API calls. Retain the subaccount Auth Token only where Twilio requires it: default webhook signature validation
   and Auth Token lifecycle operations. Twilio says API keys are preferred for applications, Restricted keys provide
   endpoint/action-level permissions, and Auth Tokens provide account-wide authority.
   [Twilio: API requests](https://www.twilio.com/docs/usage/requests-to-twilio),
   [Twilio: Restricted API keys](https://www.twilio.com/docs/iam/api-keys/restricted-api-keys),
   [Twilio: fraud containment](https://www.twilio.com/docs/usage/fraud-response-guide/contain)
2. **Do not describe Auth Token rotation as a provider-side overlap after promotion.** Primary and secondary tokens
   overlap only before promotion. Promotion immediately deletes the old primary. UCRM should stage and test the
   secondary token, then promote it; locally retaining the prior token for a short, documented webhook-retry window
   is defensive compatibility, not a token that Twilio still accepts for API calls. The exact retirement window must
   be selected from the webhook retry behavior used by the configured Twilio product and verified in staging rather
   than guessed. [Twilio: Auth Token rotation](https://help.twilio.com/articles/223136027-Auth-Tokens-and-How-to-Change-Them),
   [Twilio: Auth Token API](https://www.twilio.com/docs/iam/api/authtoken)

No implementation or infrastructure change is authorized by this research.

## Credential model

Store these as distinct server-only credential records per subaccount:

- the Restricted API key SID and encrypted secret for outbound and permitted management calls;
- the encrypted current Auth Token for default webhook verification and token management;
- during rotation only, encrypted next/prior Auth Token material with explicit state and retirement time;
- non-secret identifiers such as Account SID, Messaging Service SID, key SID, and encryption-key version.

Twilio states that main-account API keys cannot access subaccount resources, while subaccount-level API keys can be
used for subaccount CRUD. This means UCRM must create each operational API key in its owning subaccount rather than
reusing one main-account key across all contractors. [Twilio: Subaccounts authentication](https://www.twilio.com/docs/iam/api/subaccounts)

Restricted API keys are now the least-privilege choice for supported Messaging operations. The exact permissions
must be derived from Stage 2's actual Twilio calls; do not grant a broad Standard key merely for convenience. If an
endpoint needed by the minimum setup workflow is not supported by Restricted keys, document that endpoint and use
the narrowest supported credential as an explicit exception. [Twilio: Restricted API keys](https://www.twilio.com/docs/iam/api-keys/restricted-api-keys)

## Webhook verification

For the launch path, keep Twilio's generally available default signature system:

- require HTTPS with a publicly trusted certificate;
- require `X-Twilio-Signature`;
- resolve the owning subaccount from server-held sender/provider configuration, never from an untrusted tenant ID;
- validate with the official Twilio SDK using that subaccount's Auth Token, the exact externally visible URL, and
  every received parameter;
- for form requests, preserve all form fields; for JSON, preserve the raw body and `bodySHA256` query parameter;
- reject before parsing into durable business work when validation fails.

Twilio warns that webhook parameters can be added without notice and explicitly recommends its SDK rather than a
custom validator. It also requires the exact URL representation, including query parameters and encoding.
[Twilio: Secure webhooks](https://www.twilio.com/docs/usage/webhooks/webhooks-security)

Reverse-proxy handling is therefore part of the security boundary. UCRM must reconstruct the canonical configured
public URL from trusted deployment configuration, not blindly trust client-supplied `Host` or forwarding headers.
Fixture tests should cover host/protocol/query/encoding differences and both the current and staged rotation token.

Twilio now offers independently rotatable SharedKeys with HMAC-SHA256, which would remove the Auth Token from normal
webhook verification and reduce blast radius. However, the Webhooks configuration API is **Public Beta**, has no GA
SLA, and requires a dual-validation migration. It is a worthwhile later hardening option, not a launch dependency
or a reason to build custom signing now. [Twilio: SharedKey webhook signing](https://www.twilio.com/docs/usage/webhooks/webhook-shared-keys)

## Encryption and key operations

Application-layer AES-256-GCM with a versioned keyring outside Postgres is an acceptable small, portable baseline
for the planned VPS architecture, provided the implementation includes the operational controls below. GCM is an
authenticated-encryption mode, so authentication failure must be a hard failure; every encryption must use a fresh,
unpredictable nonce/IV and bind stable context such as credential record ID, subaccount SID, credential purpose, and
schema version as authenticated additional data. Use the platform's maintained cryptographic library rather than a
home-grown construction. [NIST SP 800-38D](https://csrc.nist.gov/pubs/sp/800/38/d/final)

The database record should contain ciphertext, nonce, authentication tag where the library does not combine it,
algorithm/format version, and key ID. The active key encrypts new or rotated values; older keys remain decrypt-only
until every dependent value is re-encrypted and verified. Rotation must be resumable and auditable without recording
plaintext. Decrypted material should exist only in the worker/webhook process for the shortest practical time.
NIST treats key inventory, cryptoperiod, backup, recovery, and compromise handling as parts of key management rather
than optional deployment details. [NIST SP 800-57 Part 1 Rev. 5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)

The keyring must be delivered through the production secret mechanism, excluded from images, repositories, database
backups, logs, browser payloads, and audit event bodies. Keep a separately protected off-host recovery copy; test on
a clean machine that a database backup plus the separately restored keyring can decrypt a known canary, and test that
the database backup alone cannot. Losing the keyring is permanent data loss; compromising it together with the
database exposes every stored credential.

The stronger mature-industry destination is a dedicated KMS/HSM-backed secrets service with envelope encryption,
access policies, and audit logs. In envelope encryption, a data key encrypts the secret and a separately protected
root/key-encryption key encrypts that data key. A KMS can keep its root material inside an HSM. This materially
reduces key exposure, but introducing a cloud KMS now is an infrastructure/topology decision and conflicts with the
project's approval boundary; it must be proposed separately rather than smuggled into Stage 2.
[AWS KMS: envelope encryption](https://docs.aws.amazon.com/kms/latest/developerguide/kms-cryptography.html)

Important wording correction: encrypting every credential directly with one versioned application master key is
**application-layer authenticated encryption**, not envelope encryption. Do not claim envelope encryption unless
UCRM actually introduces per-record/per-batch data keys wrapped by a separate key-encryption key.

## Supabase Vault assessment

Supabase Vault has the right high-level property: authenticated ciphertext is stored in Postgres while the root key
is held separately, and backups/replication retain ciphertext. Its decrypted view also means any database role that
can query that view can retrieve plaintext, so grants remain security-critical.
[Supabase: Vault](https://supabase.com/docs/guides/database/vault)

Vault is officially marked **Public Alpha**, although Supabase marks it available for self-hosting. Managed-project
manual `pg_dump`/`pg_restore` migration requires the old root key to be copied because a new project receives a new
key. Those facts make Vault a weaker fit for this production cutover than a small application-owned encryption
boundary whose key backup and restore UCRM controls and rehearses explicitly.
[Supabase: Vault feature status](https://supabase.com/features/vault),
[Supabase: Vault key portability](https://supabase.com/docs/guides/database/vault#key-portability-and-migration)

Do not confuse Supabase Vault with `pgsodium`: Supabase says `pgsodium` is pending deprecation, does not recommend
its transparent column encryption because of operational complexity and misconfiguration risk, and says Vault is a
separate extension unaffected by that deprecation. [Supabase: pgsodium status](https://supabase.com/docs/guides/database/extensions/pgsodium)

## Minimal Stage 2 acceptance gates

Before implementation is considered complete, tests should prove:

- one subaccount's keys/tokens cannot operate on or validate another subaccount's traffic;
- outbound calls use the Restricted API key, while webhook validation uses only the matching Auth Token;
- ciphertext or copied backups reveal no plaintext, and swapping ciphertext between credential rows fails because
  authenticated context no longer matches;
- malformed ciphertext, unknown key versions, invalid tags, and missing keys fail closed without secret-bearing logs;
- secondary-token staging, promotion, application cutover, rollback-before-promotion, and bounded prior-token
  retirement are rehearsed;
- exact external URL signature fixtures pass and forwarded-host/protocol/query manipulation fails;
- clean-machine restore requires both the database backup and separately protected keyring;
- all audit records contain identifiers, actor, time, result, and sanitized reason only—never secrets or bodies.

## Recommendation to present before building

Approve Stage 2 with the two corrections above: use per-subaccount Restricted API keys for ordinary Twilio API
access, and reserve encrypted Auth Tokens for default webhook validation/token lifecycle; describe rotation as a
staged secondary-token cutover with bounded local compatibility, not continuing provider acceptance of the old token.
Keep AES-256-GCM plus the external versioned keyring as the smallest portable launch implementation, subject to the
restore and rotation gates. Track KMS/HSM-backed envelope encryption and Twilio SharedKey signing as later hardening
decisions, not silent Stage 2 expansion.
