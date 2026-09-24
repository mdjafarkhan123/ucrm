---
description: "Interactive decision tree for configuring Amazon SES Mail Manager. Walk through use case selection, actions, authentication, TLS policy, and traffic filtering."
---

# Guided Setup — Mail Manager Configuration Decision Tree

This guide walks through the configuration decisions needed to build a Mail Manager pipeline. Agents should follow this tree interactively, asking the user each question and following the branch that matches their answer. Developers can self-navigate by answering each question.

> Start here for every new Mail Manager setup. The answers determine which resources you need, in what order, and with what configuration.

---

## Step 1: What is the use case?

Ask the user: **"What do you need Mail Manager to do?"**

### A) Receive and process inbound email for my domain

You're building an inbound email pipeline. Email arrives from the internet, Mail Manager filters and routes it.

- Ingress type: **OPEN** (no SMTP auth — senders are external)
- DNS: You'll need to update your domain's **MX record** to point to the ingress endpoint
- Continue to [Step 2: What should happen to the email?](#step-2-what-should-happen-to-the-email)

### B) Replace an on-premises SMTP relay (Postfix, Exchange, etc.)

Your applications currently send email through an on-premises SMTP server. You want Mail Manager to accept that SMTP traffic and send it to the internet via SES.

- Ingress type: **AUTH** (your applications authenticate with SMTP credentials)
- DNS: No MX record needed — your applications connect directly to the ingress endpoint hostname
- The primary rule action will be **Send to internet**
- Continue to [Step 3: How should the ingress endpoint authenticate?](#step-3-how-should-the-ingress-endpoint-authenticate)

### C) Route email through a third-party security product

You want Mail Manager to relay email through a security product for scanning before delivery.

- You'll need a **Relay** resource pointing to the security product's SMTP endpoint
- The relay likely requires **authenticated** SMTP (Secrets Manager)
- Continue to [Step 2: What should happen to the email?](#step-2-what-should-happen-to-the-email) — the relay will be one of your rule actions

### D) I'm not sure / something else

Ask the user to describe their email flow:
- Where does the email come from? (internet, internal applications, another AWS service)
- Where should it end up? (archive, S3, another server, external recipients)
- Does it need filtering or scanning?

Map their answers to option A, B, or C.

---

## Step 2: What should happen to the email?

Ask the user: **"Once email arrives, what actions should Mail Manager take? You can choose multiple."**

Present these options:

| Action | What it does | When to use it |
|--------|-------------|----------------|
| **Archive** | Store in Mail Manager's searchable archive | Compliance, legal hold, eDiscovery, audit trail |
| **Write to S3** | Save raw MIME to an S3 bucket | Analysis pipelines, backup, Lambda processing |
| **Send to internet** | Deliver to external recipients via SES | SMTP relay replacement, forwarding |
| **Relay** | Forward to an external SMTP server | Security product integration, on-premises delivery |
| **Publish to SNS** | Send notification to an SNS topic | Event-driven processing, Lambda triggers |
| **Invoke Lambda** | Invoke an AWS Lambda function to process the email | Custom processing, filtering, transformation |
| **Deliver to WorkMail** | Deliver to a WorkMail mailbox | Internal mailbox delivery |
| **Add header** | Inject a custom header | Tagging for downstream processing |
| **Replace recipient** | Rewrite the envelope recipient | Catch-all routing, alias rewriting |
| **Drop** | Silently discard the message | Spam, unwanted traffic |
| **Bounce** | Return a bounce (NDR) to the sender | Reject with a specific SMTP reply code and diagnostic message |

Based on their choices, note which actions need supporting resources:

| Action | Requires |
|--------|----------|
| Archive | A Mail Manager archive resource |
| Write to S3 | An S3 bucket + IAM role with `s3:PutObject` |
| Send to internet | IAM role with `ses:SendRawEmail` (SES sandbox: both sender and recipient must be verified) |
| Relay | A relay resource (+ Secrets Manager secret if authenticated) |
| Publish to SNS | An SNS topic + IAM role |
| Invoke Lambda | A Lambda function + IAM role with `lambda:InvokeFunction` |
| Deliver to WorkMail | A WorkMail organization + IAM role |
| Bounce | IAM role with `ses:SendBounce` + sender address |

**Cost note:** Archives incur storage charges based on email volume and retention period. Ingress points incur per-message processing charges. S3 buckets incur standard storage charges. Delete resources when no longer needed.

Ask: **"Should all messages get the same treatment, or do you need different rules for different messages?"**

- **Same treatment for all** → One rule with no conditions, multiple actions. Continue to [Step 3](#step-3-how-should-the-ingress-endpoint-authenticate).
- **Different rules for different messages** → Continue to [Step 2a: What conditions?](#step-2a-what-conditions-should-determine-routing)


### Step 2a: What conditions should determine routing?

Ask the user: **"How should Mail Manager decide which rule to apply to each message?"**

| Condition type | Example | Use when |
|---------------|---------|----------|
| Recipient address | `@sales.example.com` goes to relay, `@support.example.com` goes to archive | Routing by department or subdomain |
| Sender address | Drop email from `@known-spam.com` | Deny listing |
| Subject line | Archive messages containing "LEGAL HOLD" | Compliance triggers |
| SPF/DKIM verdict | Drop messages that fail SPF | Spam filtering |
| DMARC policy | Quarantine messages with DMARC reject policy | Policy enforcement |
| Source IP | Allow only from `10.0.0.0/8` | Internal-only traffic |
| Message size | Route large messages to S3 instead of archive | Size-based routing |
| Address list membership | Block senders on a managed deny list | Dynamic allow/block lists |

Rules are evaluated in order — first match wins. Plan the rule order:
1. Drop/block rules first (most specific)
2. Conditional routing rules next
3. Catch-all rule last (no conditions — matches everything remaining)

Continue to [Step 3](#step-3-how-should-the-ingress-endpoint-authenticate).

---

## Step 3: How should the ingress endpoint authenticate?

This step applies to **AUTH** and **MTLS** ingress points. Skip to [Step 3b](#step-3b-do-you-want-to-require-starttls) if you chose OPEN in Step 1.

Ask the user: **"Do you want your ingress endpoint to use mTLS (mutual TLS) authentication?"**

- **Yes** → Continue to [Step 3a: mTLS configuration](#step-3a-mtls-configuration)
- **No** → Continue to [SMTP credential configuration](#smtp-credential-configuration)

### Step 3a: mTLS configuration

mTLS requires connecting SMTP clients to present a TLS client certificate signed by a trusted CA. Only clients with valid certificates can send email to the endpoint.

> **Note:** mTLS is only available for public ingress endpoints. Amazon VPC endpoints do not support mTLS.

Ask the user: **"Do you have a CA certificate bundle (PEM format) for your trust store?"**

The trust store defines which client certificates are accepted. Gather the following:

| Field | Required | Description |
|-------|----------|-------------|
| **CAContent** | Yes | CA certificate bundle in PEM format (up to 500 KB). Can include multiple CA certificates. |
| **CrlContent** | No | Certificate revocation list (CRL) in PEM format (up to 500 KB). Revoked client certificates are rejected even if signed by a trusted CA. |
| **KmsKeyArn** | No | ARN of an AWS KMS customer managed key to encrypt the trust store data. If omitted, an AWS managed key is used. The key policy must allow Amazon SES to use the key. |

**Important constraints:**
- Expired CA certificates and expired CRLs are filtered out of the trust store
- If a CRL expires, the associated CA certificate is also removed — clients signed by that CA cannot connect until an updated CRL is provided
- Client certificate attributes (Common Name, serial number, Subject Alternative Name) are available in rule set conditions for routing and filtering
- `TlsPolicy: OPTIONAL` is not available for mTLS endpoints
- The TLS policy for mTLS endpoints on public networks cannot be changed after creation

Create the mTLS ingress endpoint:

```python
ingress = client.create_ingress_point(
    IngressPointName='my-mtls-ingress',
    Type='MTLS',
    TrafficPolicyId=traffic_policy_id,
    RuleSetId=rule_set_id,
    TlsPolicy='REQUIRED',  # or 'FIPS' in US/CA regions
    IngressPointConfiguration={
        'TlsAuthConfiguration': {
            'TrustStore': {
                'CAContent': open('ca-bundle.pem').read(),
                # 'CrlContent': open('crl.pem').read(),       # optional
                # 'KmsKeyArn': 'arn:aws:kms:...:key/...',     # optional
            }
        }
    }
)
```

Continue to [Step 3b](#step-3b-do-you-want-to-require-starttls).

### SMTP credential configuration

Ask the user: **"How do you want to manage SMTP credentials for the ingress endpoint?"**

### A) Simple password (development/testing only — not recommended for production)

- Provide a password directly when creating the ingress endpoint
- The SMTP username is the ingress endpoint ID (such as `inp-xxxxxxxxxxxx`)
- Credentials are not rotatable without recreating the endpoint
- **Security warning:** The password appears in AWS CloudFormation stack events and API call logs. Use Secrets Manager for production workloads to support rotation and avoid exposing credentials in logs.

→ Use `IngressPointConfiguration: { SmtpPassword: "..." }` in CloudFormation or `SmtpPassword` parameter in the CDK/API.

### B) Secrets Manager (recommended for production)

- Store credentials in Secrets Manager with a KMS CMK
- Supports rotation and programmatic retrieval
- Multiple applications can retrieve credentials from the same secret
- Requires additional IAM policies: Secrets Manager resource policy + KMS key policy for SES

→ Use `IngressPointConfiguration: { SecretArn: "arn:..." }`. See the [SMTP relay replacement CloudFormation template](../../examples/06-smtp-relay-replacement/smtp-relay-replacement.yaml) for a complete example with Secrets Manager integration.

Ask: **"Do multiple applications need to share these credentials?"**

- **Yes** → Secrets Manager is strongly recommended. The secret can be retrieved programmatically by any authorized application.
- **No** → Either option works. Secrets Manager is still preferred for production.

Continue to [Step 3b](#step-3b-do-you-want-to-require-starttls).

---

## Step 3b: Do you want to require STARTTLS?

Ask the user: **"Do you want your ingress endpoint to require STARTTLS, or do you want STARTTLS to be optional?"**

The TLS policy controls whether connecting SMTP clients must use TLS encryption. All connections use opportunistic TLS via the STARTTLS command — the connection starts as plaintext and upgrades to TLS if the client supports it.

| TLS Policy | Behavior | Available for |
|------------|----------|---------------|
| **REQUIRED** (default outside US/CA) | Reject connections that do not use TLS | All ingress types |
| **OPTIONAL** | Allow connections with or without TLS | OPEN endpoints, AUTH on private networks |
| **FIPS** (default in US/CA) | Require FIPS-validated cryptography | All types, US/CA regions only, immutable |

**Important constraints:**
- `FIPS` cannot be changed after creation — to switch, delete and recreate the endpoint
- `OPTIONAL` is not available for MTLS endpoints or public AUTH endpoints
- For public AUTH and MTLS endpoints, the TLS policy cannot be changed after creation

Based on the answer:
- **Require TLS** → `TlsPolicy: REQUIRED` (or `FIPS` in US/CA regions)
- **TLS optional** → `TlsPolicy: OPTIONAL` (only if OPEN or private AUTH)

Continue to [Step 4](#step-4-what-traffic-filtering-do-you-need).

---

## Step 4: What traffic filtering do you need?

Ask the user: **"What connections should the traffic policy allow or deny before the message body is received?"**

### Minimum recommended: Require TLS 1.2

Almost every deployment should require TLS 1.2 minimum. This is a single policy statement:

```
Traffic Policy:
  DefaultAction: DENY
  Statement: ALLOW when TLS >= 1.2
```

### Additional filtering options

Ask about each:

| Filter | Question to ask | Configuration |
|--------|----------------|---------------|
| **Recipient restriction** | "Should the endpoint only accept email for specific domains?" | ALLOW statement with `StringExpression` on `RECIPIENT` + `ENDS_WITH` |
| **IP allow list** | "Should only specific IP ranges be allowed to connect?" | ALLOW statement with `IpExpression` on `SENDER_IP` + `CIDR_MATCHES` |
| **IP deny list** | "Are there IP ranges you want to block?" | DENY statement with `IpExpression` |
| **IPv6 filtering** | "Do you need to filter by IPv6 sender addresses?" | ALLOW/DENY with `Ipv6Expression` on `SENDER_IPV6` |
| **Address list** | "Do you have a managed list of allowed/blocked senders?" | `BooleanExpression` with `IsInAddressList` evaluate type |
| **Message size limit** | "Is there a maximum message size?" | `MaxMessageSizeBytes` on the traffic policy (such as 10485760 for 10 MB) |
| **Add-on scanning** | "Do you use a third-party add-on for connection-level scanning?" | `BooleanExpression` with `Analysis` evaluate type |

For most deployments, TLS 1.2 + recipient restriction is sufficient. Add IP filtering and address lists as needed.

Continue to [Step 5](#step-5-review-and-build).

---

## Step 5: Review and build

Summarize the configuration back to the user before building:

```
Use case:           [inbound processing / SMTP relay / security relay]
Ingress type:       [OPEN / AUTH / MTLS]
TLS policy:         [REQUIRED / OPTIONAL / FIPS]
Authentication:     [password / Secrets Manager / N/A]
Traffic policy:     [TLS 1.2 required, recipient restricted to @example.com, ...]
Rule set:
  Rule 1:           [archive all messages]
  Rule 2:           [write to S3]
  Rule 3:           [send to internet]
DNS:                [MX record update needed / not needed]
```

Ask: **"Does this look right? Should I proceed with building the resources?"**

### Choose a deployment method

| Method | Best for | Reference |
|--------|----------|-----------|
| **AWS CDK (TypeScript)** | Repeatable, type-safe IaC | [CDK inbound pipeline example](../../examples/07-cdk-inbound-pipeline/) |
| **CloudFormation** | Direct template deployment | [SMTP relay replacement template](../../examples/06-smtp-relay-replacement/smtp-relay-replacement.yaml) |
| **AWS Console** | Manual step-by-step setup | [Getting Started Guide](../setup/getting-started.md) |
| **boto3 (Python)** | Scripted or interactive setup | [Setup pipeline example](../../examples/01-setup-pipeline/setup_pipeline.py) |

### Resource creation order

Regardless of deployment method, create resources in this order:

```
1. Archive (if needed)          — no dependencies
2. Relay (if needed)            — no dependencies
3. Address List (if needed)     — no dependencies
4. S3 Bucket + IAM Role         — if using WriteToS3
5. Send IAM Role                — if using Send to internet
6. Traffic Policy               — no dependencies
7. Rule Set                     — references archive IDs, relay IDs, role ARNs
8. Ingress Point                — requires TrafficPolicyId + RuleSetId
```

Wait for the ingress point to reach **ACTIVE** status before updating DNS or sharing SMTP credentials.

---

## Cleanup

To delete the resources created during setup and stop incurring charges, delete in reverse dependency order:

```
1. Ingress Point      ← delete first (stops email delivery)
2. Rule Set           ← delete after ingress point is gone
3. Traffic Policy     ← delete after ingress point is gone
4. Relay              ← delete after rule set is gone
5. Archive            ← async deletion (PENDING_DELETION state). **Warning:** permanently removes all stored emails. Export first.
6. S3 Bucket          ← empty first, then delete. **Warning:** permanently removes all stored objects.
7. Address List       ← delete last
```

For the full teardown procedure with code, see the [Cleanup Guide](../cleanup/cleanup-guide.md).

---

## Quick-path recipes

For users who know what they want, here are the three most common configurations:

### Recipe A: Inbound email with archive and S3

```
OPEN ingress → TLS 1.2 traffic policy → Rule: Archive + WriteToS3
```
→ [CDK example](../../examples/07-cdk-inbound-pipeline/) or [Python example](../../examples/01-setup-pipeline/setup_pipeline.py)

### Recipe B: SMTP relay replacement (Postfix migration)

```
AUTH ingress → TLS 1.2 traffic policy → Rule: Send to internet
```
→ [CloudFormation template](../../examples/06-smtp-relay-replacement/smtp-relay-replacement.yaml)

### Recipe C: Security product relay

```
OPEN/AUTH ingress → TLS 1.2 traffic policy → Rule: Archive + Relay to security product
```
→ [Relay guide with security product example](../relays/relay-guide.md#example-third-party-secure-email-relay-integration)
