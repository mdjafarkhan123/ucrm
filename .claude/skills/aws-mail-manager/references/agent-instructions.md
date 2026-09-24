---
description: "Complete agent instructions for Amazon SES Mail Manager. Core concepts, workflow order, condition/action syntax, common mistakes, and resource dependency reference."
---

// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

# Amazon SES Mail Manager Context

## What is Mail Manager

Amazon SES Mail Manager is a suite of email processing capabilities built on top of SES. It sits **in front of** your email infrastructure and handles inbound email processing: filtering, routing, archiving, and relay. It is **not** an email sending service — use the SES V2 API (`sesv2` client) for outbound sending.

Mail Manager is the right tool when you need to:
- Help receive and process inbound email
- Route email to different destinations based on content, sender, or recipient rules
- Archive email for compliance and eDiscovery
- Filter spam, block senders, or enforce TLS requirements before email reaches your systems
- Relay email to on-premises or third-party SMTP servers

## Core Concepts

Mail Manager has six resource types that work together in a pipeline:

```
Internet → Ingress Point → Traffic Policy → Rule Set → Action (Archive / Relay / S3 / SNS / Mailbox / Drop)
```

| Resource | Purpose |
|---|---|
| **Ingress Point** | The SMTP endpoint that receives email. Has a DNS hostname — point your MX records here. Type is OPEN, AUTH, or MTLS. |
| **Traffic Policy** | Connection-level gate — allows or denies connections based on sender IP, recipient, or TLS version. Evaluated before the message body is received. |
| **Rule Set** | Ordered list of rules evaluated against the full message. Each rule has conditions and one or more actions. |
| **Relay** | An SMTP relay destination resource. Used in rule set actions to forward email to another server. |
| **Archive** | Long-term email storage with search and export. Can be a rule set action target or standalone. |
| **Address List** | A managed list of email addresses or domains used in rule conditions (allow/block lists). |

## AI Agent Instructions

**CRITICAL WORKFLOW — ALWAYS FOLLOW THIS ORDER:**

1. **UNDERSTAND THE GOAL** — Is this about receiving/processing email (Mail Manager) or sending email (SES V2)? These are different APIs. Mail Manager = `boto3.client('mailmanager')`. SES sending = `boto3.client('sesv2')`.
2. **CHECK EXISTING RESOURCES FIRST** — Before creating anything, list existing traffic policies, rule sets, relays, and ingress points. Users often have existing infrastructure to build on.
3. **BUILD DEPENDENCIES BEFORE DEPENDENTS** — Ingress points require both a traffic policy and a rule set. Create those first.
4. **VALIDATE UNION TYPES** — Traffic policy conditions and rule set conditions/actions are union types. Each object must contain exactly ONE key. See the reference guides for correct syntax.
5. **TEST WITH SAFE OPERATIONS** — Use List and Get operations to verify resources were created correctly before wiring them together.
6. **CONFIRM BEFORE DELETING** — Deleting an ingress point stops email delivery to that endpoint. Confirm before proceeding with destructive operations.

**Pre-Implementation Checklist:**
- [ ] Using `boto3.client('mailmanager')` — NOT `ses` or `sesv2`
- [ ] Traffic policy created (required before ingress point)
- [ ] Rule set created with at least one rule and action (required before ingress point)
- [ ] Ingress point type decided: OPEN, AUTH, or MTLS
- [ ] Ingress point TLS policy decided: REQUIRED (default outside US/CA), OPTIONAL, or FIPS (default in US/CA)
- [ ] DNS MX record update planned (ingress point hostname must be set as MX)
- [ ] Archive created if email retention is required
- [ ] Relay created if forwarding to external SMTP

## User Interaction Guidelines

When asked for help with Mail Manager, clarify these before generating code:

1. **Inbound vs outbound?** — If they want to send email, they need Amazon SES V2 (`sesv2` client), not Mail Manager. Mail Manager is for receiving and processing inbound email, or for acting as an authenticated SMTP relay that sends via SES.
2. **Which region?** — Mail Manager is available in 27 commercial regions. Ask which region to deploy in. Don't assume `us-east-1`.
3. **OPEN or AUTH ingress point?** — OPEN requires no authentication (for MX-based inbound). AUTH requires SMTP credentials (for relay replacement). MTLS requires client certificates. Ask which is needed.
4. **TLS policy?** — `REQUIRED` (default outside US/CA) rejects non-TLS connections. `OPTIONAL` allows plaintext (OPEN and private AUTH only). `FIPS` (default in US/CA, immutable after creation) requires FIPS-validated cryptography.
5. **Sandbox or production?** — If the account is in SES sandbox, the Send to internet action only works for verified recipients. Ask if production access has been requested.
6. **Existing resources?** — Always list existing traffic policies, rule sets, and ingress points before creating new ones. There may be existing infrastructure to build on.
7. **What should happen to the email?** — Ask what actions are needed: archive, relay to another server, write to S3, send to internet, publish to SNS, deliver to WorkMail, or drop.
8. **DNS readiness?** — For OPEN ingress points, an MX record update is required. Confirm DNS access is available and the cutover is understood.

For a complete interactive decision tree, follow [Guided Setup](skills/aws-mail-manager/references/workflows/guided-setup.md).

## Terminology

- **Ingress Point** (also called "ingress endpoint" in AWS documentation) — The SMTP endpoint (hostname) that receives email. You point your domain's MX record here. Type is OPEN, AUTH, or MTLS. Has a configurable `TlsPolicy` (`REQUIRED`, `OPTIONAL`, or `FIPS`) that controls whether connecting clients must use STARTTLS.
- **Traffic Policy** — Connection-level filter. Evaluated before the message body is received. Can block by IP, recipient, or TLS version.
- **Rule Set** — Message-level processing. Evaluated after the full message is received. Can inspect headers, body, attachments, SPF/DKIM verdicts.
- **Rule** — A single condition+action pair within a rule set. Rules are evaluated in order; when a rule's conditions match, its actions execute. `ActionFailurePolicy` controls behavior on action failure: `CONTINUE` skips the failed action and proceeds to the next rule, `DROP` (default) discards the message.
- **Relay** — An SMTP relay resource pointing to an external mail server. Used as a rule action target.
- **Archive** — Durable email storage. Supports search by sender, recipient, subject, date range, and attachment presence.
- **Address List** — A named list of email addresses or domains. Used in rule conditions for allow/block list matching.
- **Add-on** — A third-party integration (such as spam filtering service) that can be attached to a rule set via subscription and instance.

## Common Issues to Avoid

1. **Using `ses` or `sesv2` client for Mail Manager** — Mail Manager has its own boto3 client: `boto3.client('mailmanager')`. The SES clients do not have Mail Manager operations.
2. **Creating an ingress point before traffic policy and rule set exist** — `create_ingress_point()` requires both `TrafficPolicyId` and `RuleSetId`. Create those first.
3. **Using shorthand condition keys in traffic policies** — `RecipientCondition`, `SenderCondition`, `IpCondition` are NOT valid. Use expression objects: `StringExpression`, `IpExpression`, `TlsExpression`, `BooleanExpression`.
4. **Using `Values` (plural) for TLS expressions** — `TlsExpression` uses singular `Value`, not `Values`. This is different from all other expression types.
5. **Forgetting `DefaultAction` on traffic policies** — Every traffic policy needs a `DefaultAction` of `ALLOW` or `DENY` for messages that don't match any statement.
6. **Mixing up rule set vs traffic policy condition attributes** — Rule sets use `SOURCE_IP`; traffic policies use `SENDER_IP`. Rule sets support many string attributes (`RECIPIENT`, `SENDER`, `FROM`, `TO`, `CC`, `SUBJECT`, `MAIL_FROM`, `HELO`); traffic policies only support `RECIPIENT`.
7. **Forgetting that UpdateRuleSet replaces ALL rules** — `update_rule_set()` replaces the entire rules array. Always fetch current rules first and include them in the update.
8. **Forgetting that UpdateTrafficPolicy replaces ALL statements** — Same pattern. Fetch first, then update with the full desired state.
9. **Not waiting for ingress point ACTIVE status** — After `create_ingress_point()`, the endpoint takes time to provision. Poll `get_ingress_point()` until `Status` is `ACTIVE` before updating DNS.
10. **Pointing MX records before ingress point is ACTIVE** — Email will bounce. Wait for ACTIVE status first.
11. **Archive deletion is async** — `delete_archive()` sets state to `PENDING_DELETION`. The archive is not immediately gone.
12. **Address list import requires a pre-signed URL upload** — `create_address_list_import_job()` returns a `PreSignedUrl`. You must PUT your CSV/JSON data to that URL before calling `start_address_list_import_job()`.
13. **DmarcExpression has no Evaluate field** — Unlike all other rule set condition types, `DmarcExpression` takes only `Operator` and `Values` — no `Evaluate` wrapper.
14. **Using archive ARN instead of archive ID in rule actions** — The `TargetArchive` field in the Archive rule action accepts the short archive ID (such as `a-xxxxxxxxxxxx`), NOT the full ARN. The API enforces a 66-character limit. Despite the CFN docs showing a pattern that allows colons and slashes (suggesting ARN format), using the ARN will fail with `Member must have length less than or equal to 66`.
15. **CloudFormation `!GetAtt Archive.ArchiveId` returns the full ARN** — This is a known CloudFormation behavior. Both `ArchiveId` and `ArchiveArn` return the ARN. To get the short ID in CloudFormation, extract it from the ARN: `!Select [1, !Split ["/", !GetAtt MyArchive.ArchiveArn]]`. This splits `arn:aws:ses:...:mailmanager-archive/a-xxxx` on `/` and takes the second element.
16. **Archive names persist through PENDING_DELETION** — When a CloudFormation stack rolls back or deletes, the archive enters `PENDING_DELETION` but the name remains claimed. Creating a new archive with the same name will fail. Use unique names in templates — append `${AWS::AccountId}` or a random suffix to avoid collisions on redeployment.
17. **FIPS TLS policy is immutable** — Once an ingress point is created with `TlsPolicy: FIPS`, it cannot be changed. To switch to `REQUIRED` or `OPTIONAL`, delete and recreate the ingress point. Also, `FIPS` is only available in US and Canada regions.
18. **TLS policy defaults vary by region** — In US and Canada regions, the default TLS policy is `FIPS`. In all other regions, the default is `REQUIRED`. Always set `TlsPolicy` explicitly to avoid surprises.
19. **OPTIONAL TLS policy is restricted** — `OPTIONAL` (allows plaintext connections) is only available for OPEN ingress points and AUTH ingress points on private networks. It is not available for MTLS or public AUTH endpoints.

## Resource Dependency Order

When building from scratch, always create in this order:

```
1. Archive (if needed)          — no dependencies
2. Relay (if needed)            — no dependencies
3. Address List (if needed)     — no dependencies
4. Traffic Policy               — no dependencies
5. Rule Set                     — may reference Archive IDs, Relay IDs in actions
6. Ingress Point                — requires TrafficPolicyId + RuleSetId
```

When tearing down, reverse the order. Delete ingress points before deleting the traffic policies and rule sets they reference.

## CloudFormation Gotchas

When using `AWS::SES::MailManager*` CloudFormation resources, be aware of these issues that differ from the boto3 API:

### TargetArchive requires the short archive ID, not the ARN

The `TargetArchive` property in `AWS::SES::MailManagerRuleSet` ArchiveAction requires the short archive ID (such as `a-xxxxxxxxxxxx`). The API enforces a 66-character limit. However, `!GetAtt MyArchive.ArchiveId` returns the full ARN (known CloudFormation behavior). Extract the short ID:

```yaml
# Incorrect — returns full ARN, exceeds 66-char limit
TargetArchive: !GetAtt MyArchive.ArchiveId

# Incorrect — also the full ARN
TargetArchive: !GetAtt MyArchive.ArchiveArn

# CORRECT — extract short ID from ARN
# Splits "arn:aws:ses:...:mailmanager-archive/a-xxxx" on "/" and takes "a-xxxx"
TargetArchive: !Select
  - 1
  - !Split
    - "/"
    - !GetAtt MyArchive.ArchiveArn
```

### Archive names persist through PENDING_DELETION

Archive deletion is async — the archive enters `PENDING_DELETION` and the name remains claimed for up to 30 days. If a stack rolls back after creating an archive, redeploying with the same archive name will fail. Always use unique names:

```yaml
# RISKY — name collision on redeployment after rollback
ArchiveName: !Sub "${AWS::StackName}-archive"

# SAFE — unique per account
ArchiveName: !Sub "${AWS::StackName}-archive-${AWS::AccountId}"
```

### Resource name uniqueness on rollback

The same PENDING_DELETION issue can affect any Mail Manager resource with a user-specified name. If a stack creates a resource, then rolls back, the resource may be deleted asynchronously while the name remains reserved. Use account ID or timestamp suffixes for names in templates that may be redeployed.

## Traffic Policy Condition Reference

> For full examples and common patterns, see [Traffic Policy Guide](skills/aws-mail-manager/references/traffic-policies/traffic-policy-guide.md). This section covers only the syntax gotchas.

Traffic policies evaluate connections before the message body is received. Conditions are union types — use exactly ONE key:

```python
# Allow specific recipient domain
{"StringExpression": {"Evaluate": {"Attribute": "RECIPIENT"}, "Operator": "ENDS_WITH", "Values": ["@example.com"]}}

# Block IP range
{"IpExpression": {"Evaluate": {"Attribute": "SENDER_IP"}, "Operator": "CIDR_MATCHES", "Values": ["192.0.2.0/24"]}}

# Require TLS 1.2 minimum — note: singular "Value" not "Values"
# MINIMUM_TLS_VERSION matches connections AT or ABOVE the version — use in an ALLOW statement with DefaultAction: DENY
{"TlsExpression": {"Evaluate": {"Attribute": "TLS_PROTOCOL"}, "Operator": "MINIMUM_TLS_VERSION", "Value": "TLS1_2"}}

# Block based on add-on analysis result
{"BooleanExpression": {"Evaluate": {"Analysis": {"Analyzer": "arn:aws:...", "ResultField": "spam"}}, "Operator": "IS_TRUE"}}

# Block senders on a deny list (native address list integration in traffic policies)
{"BooleanExpression": {"Evaluate": {"IsInAddressList": {"Attribute": "SENDER", "AddressLists": ["al-xxxxxxxxxxxx"]}}, "Operator": "IS_TRUE"}}
```

StringExpression operators: `EQUALS`, `NOT_EQUALS`, `STARTS_WITH`, `ENDS_WITH`, `CONTAINS`
IpExpression operators: `CIDR_MATCHES`, `NOT_CIDR_MATCHES`

Ipv6Expression — same as IpExpression but for IPv6:
```python
{"Ipv6Expression": {"Evaluate": {"Attribute": "SENDER_IPV6"}, "Operator": "CIDR_MATCHES", "Values": ["2001:db8::/32"]}}
```
Ipv6Expression operators: `CIDR_MATCHES`, `NOT_CIDR_MATCHES`

TlsExpression operators: `MINIMUM_TLS_VERSION`, `IS` — uses singular `Value` not `Values`
TLS version values: `TLS1_2`, `TLS1_3`

## Rule Set Condition Reference

> For full examples, all 11 action types, and common patterns, see [Rule Set Guide](skills/aws-mail-manager/references/rule-sets/rule-set-guide.md).

Rule set conditions evaluate the full message. Conditions are union types — use exactly ONE key:

```python
# Match on recipient
{"StringExpression": {"Evaluate": {"Attribute": "RECIPIENT"}, "Operator": "ENDS_WITH", "Values": ["@internal.example.com"]}}

# Match on source IP
{"IpExpression": {"Evaluate": {"Attribute": "SOURCE_IP"}, "Operator": "CIDR_MATCHES", "Values": ["10.0.0.0/8"]}}

# Check TLS
{"BooleanExpression": {"Evaluate": {"Attribute": "TLS"}, "Operator": "IS_TRUE"}}

# Check message size (singular "Value")
{"NumberExpression": {"Evaluate": {"Attribute": "MESSAGE_SIZE"}, "Operator": "LESS_THAN", "Value": 10485760}}

# Check SPF verdict
{"VerdictExpression": {"Evaluate": {"Attribute": "SPF"}, "Operator": "EQUALS", "Values": ["PASS"]}}

# Check DMARC policy — NO Evaluate field
{"DmarcExpression": {"Operator": "NOT_EQUALS", "Values": ["NONE"]}}
```

StringExpression attributes: `RECIPIENT`, `SENDER`, `FROM`, `TO`, `CC`, `SUBJECT`, `MAIL_FROM`, `HELO`
BooleanExpression attributes: `READ_RECEIPT_REQUESTED`, `TLS`, `TLS_WRAPPED`
NumberExpression attributes: `MESSAGE_SIZE` (bytes) — uses singular `Value`
VerdictExpression attributes: `SPF`, `DKIM`
DmarcExpression values: `NONE`, `QUARANTINE`, `REJECT`

## Rule Set Action Reference

> For full action documentation, see [Rule Set Guide](skills/aws-mail-manager/references/rule-sets/rule-set-guide.md).

Actions are union types — use exactly ONE key per action object:

```python
{"Drop": {}}
{"Bounce": {"SmtpReplyCode": "550", "StatusCode": "5.1.1", "DiagnosticMessage": "Mailbox not found", "Sender": "postmaster@example.com", "RoleArn": "arn:aws:iam::...:role/..."}}
{"Archive": {"TargetArchive": "a-xxxxxxxxxxxx", "ActionFailurePolicy": "CONTINUE"}}
{"Relay": {"Relay": "r-xxxx", "ActionFailurePolicy": "CONTINUE", "MailFrom": "PRESERVE"}}
{"WriteToS3": {"S3Bucket": "amzn-s3-demo-bucket", "RoleArn": "arn:aws:iam::...:role/...", "S3Prefix": "email/", "ActionFailurePolicy": "CONTINUE"}}
{"DeliverToMailbox": {"MailboxArn": "arn:aws:workmail:...", "RoleArn": "arn:aws:iam::...:role/...", "ActionFailurePolicy": "CONTINUE"}}
{"ReplaceRecipient": {"ReplaceWith": ["user@example.com"]}}
{"AddHeader": {"HeaderName": "X-Processed-By", "HeaderValue": "mail-manager"}}
{"Send": {"RoleArn": "arn:aws:iam::...:role/..."}}
{"PublishToSns": {"TopicArn": "arn:aws:sns:...", "RoleArn": "arn:aws:iam::...:role/..."}}
{"InvokeLambda": {"FunctionArn": "arn:aws:lambda:...:function/...", "InvocationType": "EVENT", "RoleArn": "arn:aws:iam::...:role/..."}}
```

`ActionFailurePolicy`: `CONTINUE` (try next rule on failure) or `DROP` (discard message on failure). Default is `DROP`.
`MailFrom` on Relay: `PRESERVE` (keep original) or `REPLACE` (use relay's address).

## Archive Search Reference

Archive search is async — start a job, poll for completion, then fetch results:

```python
import boto3, time

client = boto3.client('mailmanager', region_name='us-east-1')

# 1. Start search
response = client.start_archive_search(
    ArchiveId='a-xxxx',
    FromTimestamp=1700000000,  # epoch seconds
    ToTimestamp=1700086400,
    MaxResults=100,
    Filters={
        'Include': [
            {'StringExpression': {'Evaluate': {'Attribute': 'FROM'}, 'Operator': 'CONTAINS', 'Values': ['@example.com']}}
        ]
    }
)
search_id = response['SearchId']

# 2. Poll until complete
while True:
    status = client.get_archive_search(SearchId=search_id)
    if status['Status']['CompletionTimestamp']:
        break
    time.sleep(2)

# 3. Fetch results
results = client.get_archive_search_results(SearchId=search_id)
for msg in results['Rows']:
    print(msg['ArchivedMessageId'], msg['Envelope']['From'], msg['Envelope']['To'])
```

Archive filter attributes: `TO`, `FROM`, `CC`, `SUBJECT`, `ENVELOPE_TO`, `ENVELOPE_FROM`
Archive filter operator: always `CONTAINS`
Boolean filter attribute: `HAS_ATTACHMENTS`

## SDK Installation

```bash
pip install boto3
```

AWS credentials must be configured via `aws configure`, environment variables, or IAM role.

## Quick Reference — Which Guide to Use

| Task | Reference Guide |
|------|----------------|
| Set up Mail Manager from scratch | `skills/aws-mail-manager/references/setup/getting-started.md` |
| Create and configure traffic policies | `skills/aws-mail-manager/references/traffic-policies/traffic-policy-guide.md` |
| Build rule sets with conditions and actions | `skills/aws-mail-manager/references/rule-sets/rule-set-guide.md` |
| Set up email archiving and search | `skills/aws-mail-manager/references/archives/archive-guide.md` |
| Configure SMTP relays | `skills/aws-mail-manager/references/relays/relay-guide.md` |
| Manage address lists and bulk import | `skills/aws-mail-manager/references/address-lists/address-list-guide.md` |
| Tear down resources safely | `skills/aws-mail-manager/references/cleanup/cleanup-guide.md` |
| Troubleshoot common issues | `skills/aws-mail-manager/references/troubleshooting/troubleshooting-guide.md` |
| Guided setup (interactive decision tree) | `skills/aws-mail-manager/references/workflows/guided-setup.md` |
| Event-driven AI processing pipeline | `skills/aws-mail-manager/references/workflows/event-driven-ai-pipeline.md` |
| CloudFormation gotchas | See the "CloudFormation Gotchas" section in this document |
| SES v2 + Mail Manager API catalog | `skills/aws-mail-manager/references/api/ses-api-index.md` |

## LLM Context Files

- **Mail Manager Developer Guide**: https://docs.aws.amazon.com/ses/latest/dg/mail-manager.html
- **API Reference**: https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_Operations_Amazon_SES_Mail_Manager.html

## Structure

- `AGENTS.md` — Top-level agent instructions covering both aws-ses and aws-mail-manager skills.
- `CLAUDE.md` — Claude Code entry point (points to AGENTS.md).
- `skills/aws-mail-manager/SKILL.md` — Skill entry point for agent skill loaders.
- `skills/aws-mail-manager/references/agent-instructions.md` — This file. Mail Manager-specific agent instructions.
- `skills/aws-mail-manager/references/` — Task-oriented reference guides per feature area.
- `skills/aws-mail-manager/references/api/ses-api-index.md` — SES v2 + Mail Manager API operation catalog.
- `skills/aws-mail-manager/examples/` — Standalone Python scripts for common workflows.
