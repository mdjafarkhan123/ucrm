# Suppression Lists Guide

Suppression lists prevent SES from sending to addresses that previously bounced or complained. They protect your sender reputation automatically.

## Three Levels of Suppression

| Level | Scope | Managed By |
|-------|-------|------------|
| **Global** | All SES customers | AWS (automatic) |
| **Account-level** | Your entire account | You (configure per account) |
| **Config-set-level** | A specific configuration set | You (configure per config set) |

## How They Work Together

When you send an email, SES checks suppression lists in this order:
1. **Global suppression list** — addresses that bounced across all SES customers
2. **Account-level suppression** — addresses you've suppressed for your account
3. **Config-set-level suppression** — addresses suppressed for the specific config set

If the address is on any list, SES does not attempt delivery. The event generated depends on the suppression source:

| Suppression Source | Event Type | Subtype | Counts Toward Bounce Rate? |
|-------------------|------------|---------|---------------------------|
| Account-level suppression | `BOUNCE` | `bounceSubType: OnAccountSuppressionList` | No |
| Global suppression | `BOUNCE` | `bounceSubType: Suppressed` | Yes |
| Tenant suppression | `BOUNCE` | `bounceSubType: OnTenantSuppressionList` | No |

**Note:** The `REJECT` event type is NOT related to suppression. REJECT is only generated when SES detects virus/malware in email content.

## Enable Account-Level Suppression

```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

client.put_account_suppression_attributes(
    SuppressedReasons=['BOUNCE', 'COMPLAINT']
)
```

This auto-suppresses any address that bounces or generates a complaint.

## Enable Config-Set-Level Suppression

```python
client.create_configuration_set(
    ConfigurationSetName='marketing-config',
    SuppressionOptions={
        'SuppressedReasons': ['BOUNCE', 'COMPLAINT']
    }
)
```

Or update an existing config set:

```python
client.put_configuration_set_suppression_options(
    ConfigurationSetName='marketing-config',
    SuppressedReasons=['BOUNCE', 'COMPLAINT']
)
```

## Manage Suppressed Addresses

### List suppressed addresses:
```python
response = client.list_suppressed_destinations(
    Reasons=['BOUNCE', 'COMPLAINT'],
    StartDate='2026-01-01T00:00:00Z',
    EndDate='2026-12-31T23:59:59Z'
)
for item in response['SuppressedDestinationSummaries']:
    print(f"{item['EmailAddress']} - {item['Reason']} ({item['LastUpdateTime']})")
```

### Manually add an address:
```python
client.put_suppressed_destination(
    EmailAddress='bad-address@example.com',
    Reason='BOUNCE'
)
```

### Remove an address (allow sending again):
```python
client.delete_suppressed_destination(
    EmailAddress='recovered-address@example.com'
)
```

## Recommendation

Enable both BOUNCE and COMPLAINT suppression at the account level as a baseline. Use config-set-level suppression for finer control (for example, different suppression rules for marketing vs transactional).

## Clean Up

To remove suppression configuration created in this guide:

### Disable Account-Level Suppression

**AWS CLI:**
```bash
aws sesv2 put-account-suppression-attributes \
    --suppressed-reasons \
    --region us-east-1
```

**Python:**
```python
client.put_account_suppression_attributes(
    SuppressedReasons=[]
)
```

### Remove Suppressed Addresses

**AWS CLI:**
```bash
aws sesv2 delete-suppressed-destination \
    --email-address bad-address@example.com \
    --region us-east-1
```

**Python:**
```python
client.delete_suppressed_destination(
    EmailAddress='bad-address@example.com'
)
```

> **Note:** Disabling account-level suppression does not remove individual suppressed addresses. Remove them separately if needed. Removing suppression means SES will attempt delivery to previously suppressed addresses, which may result in bounces.
