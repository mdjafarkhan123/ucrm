# Configuration Sets Guide

> Examples shown in Python, Node.js, and AWS CLI.

Configuration sets are named groups of rules applied to emails you send. They enable event tracking, suppression management, and IP pool assignment. **Never send email without a configuration set.**

## Why Configuration Sets Are Required

Without a configuration set, you lose per-stream event notifications, per-stream Amazon CloudWatch metrics, and config-set-level suppression management. Account-level reputation metrics (bounce rate, complaint rate) and the account-level suppression list still apply — but you have no granularity across mail streams and no way to receive real-time event notifications for bounces, complaints, or deliveries.

## Prerequisites

Before you begin, confirm you have the following:

- An AWS account with Amazon SES access
- AWS CLI or SDK installed and configured with credentials
- A verified email identity (domain or email address) in Amazon SES

## Step 1: Create a Configuration Set

**Python:**
```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

client.create_configuration_set(
    ConfigurationSetName='my-app-production',
    SendingOptions={'SendingEnabled': True},
    ReputationOptions={'ReputationMetricsEnabled': True},
    SuppressionOptions={
        'SuppressedReasons': ['BOUNCE', 'COMPLAINT']
    }
)
```

**Node.js:**
```javascript
import { SESv2Client, CreateConfigurationSetCommand } from '@aws-sdk/client-sesv2';

const client = new SESv2Client({ region: 'us-east-1' });

await client.send(new CreateConfigurationSetCommand({
    ConfigurationSetName: 'my-app-production',
    SendingOptions: { SendingEnabled: true },
    ReputationOptions: { ReputationMetricsEnabled: true },
    SuppressionOptions: { SuppressedReasons: ['BOUNCE', 'COMPLAINT'] }
}));
```

**AWS CLI:**
```bash
aws sesv2 create-configuration-set \
    --configuration-set-name my-app-production \
    --sending-options SendingEnabled=true \
    --reputation-options ReputationMetricsEnabled=true \
    --suppression-options SuppressedReasons=BOUNCE,COMPLAINT \
    --region us-east-1
```

## Step 2: Add Event Destinations

Event destinations tell SES where to send notifications about email events.

### CloudWatch (Metrics)

```python
client.create_configuration_set_event_destination(
    ConfigurationSetName='my-app-production',
    EventDestinationName='cloudwatch-metrics',
    EventDestination={
        'Enabled': True,
        'MatchingEventTypes': ['SEND', 'DELIVERY', 'BOUNCE', 'COMPLAINT', 'REJECT', 'DELIVERY_DELAY'],
        'CloudWatchDestination': {
            'DimensionConfigurations': [{
                'DimensionName': 'ses:configuration-set',
                'DimensionValueSource': 'MESSAGE_TAG',
                'DefaultDimensionValue': 'default'
            }]
        }
    }
)
```

### Amazon SNS (Notifications)

```python
client.create_configuration_set_event_destination(
    ConfigurationSetName='my-app-production',
    EventDestinationName='sns-bounces-complaints',
    EventDestination={
        'Enabled': True,
        'MatchingEventTypes': ['BOUNCE', 'COMPLAINT'],
        'SnsDestination': {
            'TopicArn': 'arn:aws:sns:us-east-1:123456789012:ses-notifications'
        }
    }
)
```

### Amazon EventBridge

```python
client.create_configuration_set_event_destination(
    ConfigurationSetName='my-app-production',
    EventDestinationName='eventbridge-all',
    EventDestination={
        'Enabled': True,
        'MatchingEventTypes': ['SEND', 'DELIVERY', 'BOUNCE', 'COMPLAINT', 'DELIVERY_DELAY', 'REJECT'],
        'EventBridgeDestination': {
            'EventBusArn': 'arn:aws:events:us-east-1:123456789012:event-bus/default'
        }
    }
)
```

## Step 3: Use the Configuration Set When Sending

Add `ConfigurationSetName` to every `send_email` call:

```python
response = client.send_email(
    FromEmailAddress='sender@example.com',
    Destination={'ToAddresses': ['recipient@example.com']},
    Content={
        'Simple': {
            'Subject': {'Data': 'Hello'},
            'Body': {'Text': {'Data': 'Sent with tracking.'}}
        }
    },
    ConfigurationSetName='my-app-production'
)
```

For SMTP, add the header:
```
X-SES-CONFIGURATION-SET: my-app-production
```

## Step 4: Set as Default for an Identity

Instead of specifying in every send call, set a default configuration set on your identity:

```python
client.put_email_identity_configuration_set_attributes(
    EmailIdentity='example.com',
    ConfigurationSetName='my-app-production'
)
```

All email sent from this identity will use this configuration set unless overridden.

## Event Types Reference

| Event | When It Fires |
|-------|---------------|
| `SEND` | SES accepted the message |
| `DELIVERY` | Recipient's mail server accepted the message |
| `BOUNCE` | Recipient's server rejected the message |
| `COMPLAINT` | Recipient marked the email as spam |
| `REJECT` | SES rejected the message (virus/malware detected in content) |
| `OPEN` | Recipient opened the email (requires open tracking enabled) |
| `CLICK` | Recipient clicked a link (requires click tracking enabled) |
| `DELIVERY_DELAY` | Delivery was delayed (temporary failure, SES is retrying) |
| `RENDERING_FAILURE` | Template rendering failed |
| `SUBSCRIPTION` | Subscription preference change |

## Example Event Payloads

### Bounce Notification (SNS)

When SES receives a bounce, the SNS notification contains:

```json
{
  "notificationType": "Bounce",
  "bounce": {
    "bounceType": "Permanent",
    "bounceSubType": "General",
    "bouncedRecipients": [
      {
        "emailAddress": "bounce@simulator.amazonses.com",
        "action": "failed",
        "status": "5.1.1",
        "diagnosticCode": "smtp; 550 5.1.1 user unknown"
      }
    ],
    "timestamp": "2026-03-16T12:00:00.000Z",
    "feedbackId": "0100018e-1234-5678-9abc-def012345678-000000"
  },
  "mail": {
    "timestamp": "2026-03-16T11:59:55.000Z",
    "source": "sender@example.com",
    "messageId": "0100018e-abcd-efgh-ijkl-mnopqrstuvwx-000000",
    "destination": ["bounce@simulator.amazonses.com"],
    "tags": {
      "ses:configuration-set": ["my-app-production"]
    }
  }
}
```

### Complaint Notification (SNS)

```json
{
  "notificationType": "Complaint",
  "complaint": {
    "complainedRecipients": [
      {"emailAddress": "complaint@simulator.amazonses.com"}
    ],
    "complaintFeedbackType": "abuse",
    "timestamp": "2026-03-16T12:05:00.000Z",
    "feedbackId": "0100018e-5678-9abc-def0-123456789abc-000000"
  },
  "mail": {
    "timestamp": "2026-03-16T12:00:00.000Z",
    "source": "sender@example.com",
    "messageId": "0100018e-abcd-efgh-ijkl-mnopqrstuvwx-000000",
    "destination": ["complaint@simulator.amazonses.com"]
  }
}
```

### Processing Bounces with AWS Lambda

```python
import json

def lambda_handler(event, context):
    """Process SES bounce/complaint notifications from SNS."""
    for record in event['Records']:
        message = json.loads(record['Sns']['Message'])
        notification_type = message['notificationType']

        if notification_type == 'Bounce':
            bounce = message['bounce']
            if bounce['bounceType'] == 'Permanent':
                for recipient in bounce['bouncedRecipients']:
                    email = recipient['emailAddress']
                    print(f"HARD BOUNCE: {email} — remove from mailing list")
                    # Add to your application's suppression list
                    # SES account-level suppression handles this automatically
                    # if configured, but you may want app-level tracking too

        elif notification_type == 'Complaint':
            for recipient in message['complaint']['complainedRecipients']:
                email = recipient['emailAddress']
                print(f"COMPLAINT: {email} — unsubscribe immediately")
                # Unsubscribe this address from all marketing email
                # Continuing to send to complainers triggers enforcement

        return {'statusCode': 200}
```

## Recommended Configuration

For most applications, create one configuration set with:
- **Suppression:** BOUNCE and COMPLAINT (auto-suppress addresses that bounce or complain)
- **Reputation metrics:** Enabled
- **Event destination:** CloudWatch for metrics + SNS or EventBridge for bounce/complaint notifications
- **Delivery delay events:** Enabled for visibility into deferred messages

## Multiple Configuration Sets

Use separate configuration sets for different mail streams:
- `transactional-config` — password resets, order confirmations
- `marketing-config` — newsletters, promotions
- `notification-config` — system alerts, monitoring

This gives you per-stream metrics and independent suppression management.

## Clean Up

To avoid ongoing charges, delete the resources created in this guide.

### Delete Event Destinations

**AWS CLI:**
```bash
aws sesv2 delete-configuration-set-event-destination \
    --configuration-set-name my-app-production \
    --event-destination-name cloudwatch-metrics \
    --region us-east-1
```

**Python:**
```python
client.delete_configuration_set_event_destination(
    ConfigurationSetName='my-app-production',
    EventDestinationName='cloudwatch-metrics'
)
```

### Delete Configuration Set

**AWS CLI:**
```bash
aws sesv2 delete-configuration-set \
    --configuration-set-name my-app-production \
    --region us-east-1
```

**Python:**
```python
client.delete_configuration_set(
    ConfigurationSetName='my-app-production'
)
```

> **Note:** Delete event destinations before deleting the configuration set. Deleting a configuration set also removes its event destinations, but explicit cleanup is recommended.
