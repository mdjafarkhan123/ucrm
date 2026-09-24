---
description: "Configure SMTP relays in Amazon SES Mail Manager. Forward email to external servers with optional authentication, including third-party security product integration."
---

# Relay Guide

SMTP relays forward email from Mail Manager to external SMTP servers. Use relays to integrate with on-premises mail infrastructure, third-party security products (such as an email security gateway), or downstream mail servers.

## Prerequisites

- boto3 installed: `pip install boto3`
- AWS credentials configured: `aws configure`
- Amazon SES Mail Manager enabled in your account/region
- For authenticated relays: an AWS Secrets Manager secret with SMTP credentials and an AWS KMS key policy allowing Amazon SES access

## Key Facts

- Relays are standalone resources — no dependencies on other Mail Manager resources
- Used as a rule set action target (`Relay` action)
- Support authenticated (Secrets Manager) or unauthenticated connections
- `MailFrom` can be `PRESERVE` (keep original sender) or `REPLACE` (use relay's address)
- Relay ID (not ARN) is used in rule set actions

## Create a Relay

### Unauthenticated relay

```python
import boto3

client = boto3.client('mailmanager', region_name='us-east-1')

response = client.create_relay(
    RelayName='internal-mail-server',
    ServerName='mail.internal.example.com',
    ServerPort=25,
    Authentication={'NoAuthentication': {}}
)
relay_id = response['RelayId']
print(f"Relay ID: {relay_id}")
```

### Authenticated relay (Secrets Manager)

```python
response = client.create_relay(
    RelayName='example-security-relay',
    ServerName='relay.security.example.com',
    ServerPort=587,
    Authentication={
        'SecretArn': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:security-smtp-creds'
    }
)
```

The secret must contain SMTP credentials. The AWS Secrets Manager secret requires a resource policy allowing Amazon SES to access it, and an AWS KMS customer managed key (CMK) policy allowing Amazon SES to decrypt. See [Permission policies for SMTP relay](https://docs.aws.amazon.com/ses/latest/dg/eb-policies.html#eb-policies-rule-action) for the required policies.

## Use Relay in a Rule Set Action

```python
client.create_rule_set(
    RuleSetName='relay-to-security-gateway',
    Rules=[
        {
            'Name': 'forward-all',
            'Actions': [
                {
                    'Relay': {
                        'Relay': relay_id,          # relay ID, not ARN
                        'MailFrom': 'PRESERVE',     # or 'REPLACE'
                        'ActionFailurePolicy': 'CONTINUE'
                    }
                }
            ]
        }
    ]
)
```

### MailFrom options

- `PRESERVE` — keep the original sender's MAIL FROM address. Use this when the downstream server needs to see the original sender (most common for security product integrations).
- `REPLACE` — use the relay's configured address. Use this when the downstream server requires a specific sender identity.

## Common Relay Patterns

### Archive then relay to security product

```python
Rules=[
    {
        'Name': 'archive-and-relay',
        'Actions': [
            {'Archive': {'TargetArchive': archive_id, 'ActionFailurePolicy': 'CONTINUE'}},
            {'Relay': {'Relay': security_relay_id, 'ActionFailurePolicy': 'CONTINUE', 'MailFrom': 'PRESERVE'}}
        ]
    }
]
```

### Relay by recipient domain

```python
Rules=[
    {
        'Name': 'relay-internal',
        'Conditions': [
            {'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@internal.example.com']}}
        ],
        'Actions': [
            {'Relay': {'Relay': internal_relay_id, 'ActionFailurePolicy': 'CONTINUE', 'MailFrom': 'PRESERVE'}}
        ]
    },
    {
        'Name': 'relay-partner',
        'Conditions': [
            {'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@partner.example.com']}}
        ],
        'Actions': [
            {'Relay': {'Relay': partner_relay_id, 'ActionFailurePolicy': 'CONTINUE', 'MailFrom': 'PRESERVE'}}
        ]
    }
]
```

## Update a Relay

```python
client.update_relay(
    RelayId=relay_id,
    ServerName='new-mail-server.example.com',
    ServerPort=587,
    Authentication={'SecretArn': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:new-creds'}
)
```

## Integrating with Third-Party Security Products

A common use case for relays is routing email through third-party security inspection services before delivery. The relay acts as a bridge between Mail Manager and the security product's SMTP endpoint.

### Architecture patterns

There are two common configurations:

**Pattern 1: Security product delivers to recipients**

```
Application → SES → Mail Manager → Relay → Security Product → Recipients
```

Mail Manager receives the email and relays it to the security product (such as AnyCompany Secure Email Relay). The security product scans the message, applies policies, and delivers it to the final recipients. Use this when the security product handles DKIM signing and final delivery.

**Pattern 2: Security product routes back to SES for delivery**

```
Application → SES → Mail Manager → Relay → Security Product → SES → Recipients
```

Mail Manager relays to the security product for scanning. After processing, the security product sends the email back to SES (via a second Mail Manager ingress point or directly via SES SMTP) for final delivery. Use this when you want SES deliverability features (VDM, configuration sets, event publishing) on the outbound leg.

### Example: Third-party secure email relay integration

This example shows how to configure Mail Manager to relay through a third-party email security product that provides threat detection, policy enforcement, and DKIM signing for outbound email.

**Step 1: Store SMTP credentials in Secrets Manager**

Create a secret with the SMTP credentials the security product provides. The secret must have a resource policy allowing SES to access it, and the KMS key must allow SES to decrypt.

```python
import boto3
import json

secrets_client = boto3.client('secretsmanager', region_name='us-east-1')

# Create the secret with the security product's SMTP credentials
secret = secrets_client.create_secret(
    Name='security-relay-smtp-creds',
    SecretString=json.dumps({
        'username': 'your-relay-username',
        'password': 'your-relay-password'
    })
)
secret_arn = secret['ARN']
```

You must also add the [Secrets Manager resource policy for SMTP relay](https://docs.aws.amazon.com/ses/latest/dg/eb-policies.html#eb-policies-rule-action) and the [KMS CMK key policy](https://docs.aws.amazon.com/ses/latest/dg/eb-policies.html#eb-policies-rule-action) to allow SES to access the secret.

**Step 2: Create the relay pointing to the security product**

```python
client = boto3.client('mailmanager', region_name='us-east-1')

response = client.create_relay(
    RelayName='security-email-relay',
    ServerName='relay.security.example.com',  # Your security product's SMTP endpoint
    ServerPort=587,
    Authentication={'SecretArn': secret_arn}
)
security_relay_id = response['RelayId']
```

**Step 3: Create a rule set that relays through the security product**

Use `MailFrom: PRESERVE` so the security product sees the original sender — this is required for DKIM signing and policy enforcement to work correctly.

```python
response = client.create_rule_set(
    RuleSetName='security-relay-integration',
    Rules=[
        {
            'Name': 'archive-copy',
            'Actions': [
                {
                    # Keep a copy in the archive before sending to the security product
                    'Archive': {
                        'TargetArchive': archive_id,
                        'ActionFailurePolicy': 'CONTINUE'
                    }
                }
            ]
        },
        {
            'Name': 'relay-to-security-product',
            'Actions': [
                {
                    'Relay': {
                        'Relay': security_relay_id,
                        'MailFrom': 'PRESERVE',
                        'ActionFailurePolicy': 'DROP'  # DROP if security product is unreachable
                    }
                }
            ]
        }
    ]
)
```

**Step 4: Wire up the ingress point**

Create a traffic policy and ingress point as described in the [Getting Started Guide](../setup/getting-started.md). The ingress point receives email from your applications (or from SES via the Send action), and the rule set routes it through the security product.

### Key considerations for security product relays

- Always use `MailFrom: PRESERVE` unless the security product specifically requires a different sender identity. Security products need the original sender for policy evaluation and DKIM signing.
- Use `ActionFailurePolicy: DROP` on the relay action if the security product is mandatory — you don't want unscanned email delivered if the relay is unreachable.
- Use `ActionFailurePolicy: CONTINUE` if you want email to proceed even if the security product is temporarily unavailable (less secure but more resilient).
- Store SMTP credentials in Secrets Manager with a KMS CMK — never use `NoAuthentication` for security product relays.
- The Secrets Manager secret and KMS key both require resource policies allowing the SES service principal to access them. See [Permission policies for SMTP relay](https://docs.aws.amazon.com/ses/latest/dg/eb-policies.html#eb-policies-rule-action).

### Applicable to other security products

This pattern works with any third-party email security product that accepts SMTP relay connections. Replace the `ServerName` and `ServerPort` with the product's SMTP endpoint, and provide the appropriate credentials.

## Cleanup

Deleting a relay that is referenced in an active rule set action disrupts email routing — messages matching that rule action will fail. Before deleting:

1. Remove the relay action from all rule sets that reference it
2. Delete the relay
3. If using authenticated relay, the Secrets Manager secret continues to incur ~$0.40/month until deleted separately

```python
# Remove relay from all rule set actions first, then:
client.delete_relay(RelayId=relay_id)

# If using Secrets Manager, delete the secret separately:
# aws secretsmanager delete-secret --secret-id <arn> --force-delete-without-recovery
```

## List and Get

```python
# List all relays
relays = client.list_relays()
for r in relays['Relays']:
    print(r['RelayId'], r['RelayName'])

# Get details
relay = client.get_relay(RelayId=relay_id)
print(relay['ServerName'], relay['ServerPort'])
print(relay['Authentication'])
```

## Delete

```python
# Remove relay from all rule set actions before deleting
client.delete_relay(RelayId=relay_id)
```

See [Cleanup](#cleanup) for the full procedure.
