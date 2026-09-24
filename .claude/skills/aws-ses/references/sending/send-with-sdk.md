# Email Patterns with the SES V2 SDK

> Examples use Python. For Java, see `references/java-examples.md`.

All sending patterns using the SES V2 API (`sesv2` client). Always use V2, never V1.

## Prerequisites

Before you begin, confirm you have the following:

- An AWS account with Amazon SES access
- AWS CLI or SDK installed and configured with credentials (Python: `pip install boto3`)
- A verified email identity (domain or email address) in Amazon SES
- A configuration set created (see [configuration-sets.md](../configuration/configuration-sets.md))

## Simple Message (Text + HTML)

```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

response = client.send_email(
    FromEmailAddress='sender@example.com',
    Destination={
        'ToAddresses': ['to@example.com'],
        'CcAddresses': ['cc@example.com'],       # Optional
        'BccAddresses': ['bcc@example.com']       # Optional
    },
    Content={
        'Simple': {
            'Subject': {'Data': 'Subject line', 'Charset': 'UTF-8'},
            'Body': {
                'Text': {'Data': 'Plain text body', 'Charset': 'UTF-8'},
                'Html': {'Data': '<h1>HTML body</h1>', 'Charset': 'UTF-8'}
            },
            'Headers': [                          # Optional custom headers
                {'Name': 'X-Custom-Header', 'Value': 'custom-value'}
            ]
        }
    },
    ConfigurationSetName='my-config-set',
    TenantName='my-tenant'                        # Recommended
)
print(f"MessageId: {response['MessageId']}")
```

## Raw Message (Attachments, Custom MIME)

For attachments or full control over the MIME structure, use raw email:

```python
import boto3
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication

client = boto3.client('sesv2', region_name='us-east-1')

msg = MIMEMultipart('mixed')
msg['Subject'] = 'Email with attachment'
msg['From'] = 'sender@example.com'
msg['To'] = 'recipient@example.com'

# Text body
msg.attach(MIMEText('Please see the attached file.', 'plain'))

# HTML body
msg.attach(MIMEText('<p>Please see the attached file.</p>', 'html'))

# Attachment
with open('report.pdf', 'rb') as f:
    attachment = MIMEApplication(f.read(), _subtype='pdf')
    attachment.add_header('Content-Disposition', 'attachment', filename='report.pdf')
    msg.attach(attachment)

response = client.send_email(
    FromEmailAddress='sender@example.com',
    Destination={'ToAddresses': ['recipient@example.com']},
    Content={'Raw': {'Data': msg.as_string()}},
    ConfigurationSetName='my-config-set'
)
```

## Templated Message

Create a template once, send with personalized data:

### Create Template

```python
client.create_email_template(
    TemplateName='welcome-email',
    TemplateContent={
        'Subject': 'Welcome, {{name}}!',
        'Text': 'Hello {{name}}, welcome to {{company}}.',
        'Html': '<h1>Hello {{name}}</h1><p>Welcome to {{company}}.</p>'
    }
)
```

### Send with Template

```python
import json

response = client.send_email(
    FromEmailAddress='sender@example.com',
    Destination={'ToAddresses': ['user@example.com']},
    Content={
        'Template': {
            'TemplateName': 'welcome-email',
            'TemplateData': json.dumps({
                'name': 'Jane Doe',
                'company': 'Example Corp'
            })
        }
    },
    ConfigurationSetName='my-config-set'
)
```

## Bulk Templated Message

Send to multiple recipients with per-recipient personalization:

```python
import json

response = client.send_bulk_email(
    FromEmailAddress='sender@example.com',
    DefaultContent={
        'Template': {
            'TemplateName': 'welcome-email',
            'TemplateData': json.dumps({'company': 'Example Corp'})  # Default values
        }
    },
    BulkEmailEntries=[
        {
            'Destination': {'ToAddresses': ['janedoe@example.com']},
            'ReplacementEmailContent': {
                'ReplacementTemplate': {
                    'ReplacementTemplateData': json.dumps({'name': 'Jane Doe'})
                }
            }
        },
        {
            'Destination': {'ToAddresses': ['bob@example.com']},
            'ReplacementEmailContent': {
                'ReplacementTemplate': {
                    'ReplacementTemplateData': json.dumps({'name': 'Bob'})
                }
            }
        }
    ],
    ConfigurationSetName='my-config-set'
)

# Check per-recipient results
for i, result in enumerate(response['BulkEmailEntryResults']):
    status = result['Status']
    print(f"Recipient {i}: {status}")
    if status != 'SUCCESS':
        print(f"  Error: {result.get('Error', 'Unknown')}")
```

**Bulk limits:** Up to 50 recipients per `send_bulk_email` call.

## Reply-To and Return Path

```python
response = client.send_email(
    FromEmailAddress='sender@example.com',
    ReplyToAddresses=['support@example.com'],
    FeedbackForwardingEmailAddress='bounce-handler@example.com',
    Destination={'ToAddresses': ['recipient@example.com']},
    Content={
        'Simple': {
            'Subject': {'Data': 'Hello'},
            'Body': {'Text': {'Data': 'Reply goes to support@example.com'}}
        }
    },
    ConfigurationSetName='my-config-set'
)
```

## Message Tags

Add custom tags for tracking and segmentation:

```python
response = client.send_email(
    FromEmailAddress='sender@example.com',
    Destination={'ToAddresses': ['recipient@example.com']},
    Content={
        'Simple': {
            'Subject': {'Data': 'Tagged email'},
            'Body': {'Text': {'Data': 'This email has tracking tags.'}}
        }
    },
    EmailTags=[
        {'Name': 'campaign', 'Value': 'spring-2026'},
        {'Name': 'type', 'Value': 'transactional'}
    ],
    ConfigurationSetName='my-config-set'
)
```

Tags appear in event notifications and Amazon CloudWatch metrics.

## Error Handling

```python
from botocore.exceptions import ClientError

try:
    response = client.send_email(
        FromEmailAddress='sender@example.com',
        Destination={'ToAddresses': ['recipient@example.com']},
        Content={
            'Simple': {
                'Subject': {'Data': 'Hello'},
                'Body': {'Text': {'Data': 'Test'}}
            }
        },
        ConfigurationSetName='my-config-set'
    )
except ClientError as e:
    error_code = e.response['Error']['Code']
    if error_code == 'MessageRejected':
        print("Message rejected — check identity verification and sandbox status")
    elif error_code == 'MailFromDomainNotVerifiedException':
        print("MAIL FROM domain not verified")
    elif error_code == 'ConfigurationSetDoesNotExistException':
        print("Configuration set not found")
    elif error_code == 'AccountSendingPausedException':
        print("Account sending is paused — check reputation dashboard")
    else:
        raise
```

## Retry Strategy

SES API errors fall into two categories:

| Error Type | Retry? | Examples |
|-----------|--------|---------|
| **Client errors (4xx)** | No — fix the request | `MessageRejected`, `ConfigurationSetDoesNotExistException`, `MailFromDomainNotVerifiedException` |
| **Throttling (429)** | Yes — exponential backoff | `ThrottlingException`, `TooManyRequestsException` |
| **Server errors (5xx)** | Yes — exponential backoff | `InternalServiceErrorException` |

**Retry pattern:**

```python
import time
from botocore.exceptions import ClientError

def send_with_retry(client, params, max_retries=3):
    for attempt in range(max_retries + 1):
        try:
            return client.send_email(**params)
        except ClientError as e:
            code = e.response['Error']['Code']
            if code in ('ThrottlingException', 'TooManyRequestsException') or e.response['ResponseMetadata']['HTTPStatusCode'] >= 500:
                if attempt < max_retries:
                    wait = 2 ** attempt  # 1s, 2s, 4s
                    time.sleep(wait)
                    continue
            raise
```

**Note:** SES does not support idempotency keys. If a send call times out but SES accepted the message, retrying may send a duplicate. For critical transactional email, track `MessageId` on success and check before retrying.

## Domain Warmup

New sending domains (even on shared IPs) need gradual volume increases to build reputation with mailbox providers.

| Day | Recommended Daily Volume |
|-----|------------------------|
| 1-3 | Up to 200 |
| 4-7 | Up to 1,000 |
| 8-14 | Up to 5,000 |
| 15-21 | Up to 20,000 |
| 22-30 | Up to 50,000 |
| 30+ | Full volume |

**Tips:**
- Send to your most engaged recipients first during warmup
- Monitor bounce and complaint rates closely — stop and investigate if either spikes
- Domain warmup is separate from IP warmup (relevant for dedicated IPs)
- Transactional email (password resets, confirmations) is typically well-suited for warmup — high engagement signals


## Clean Up

To avoid ongoing charges, delete the resources you created in this guide.

### Delete Email Template

**AWS CLI:**
```bash
aws sesv2 delete-email-template \
    --template-name welcome-email \
    --region us-east-1
```

**Python:**
```python
client.delete_email_template(
    TemplateName='welcome-email'
)
```

### Delete Test Identity

**AWS CLI:**
```bash
aws sesv2 delete-email-identity \
    --email-identity sender@example.com \
    --region us-east-1
```

**Python:**
```python
client.delete_email_identity(
    EmailIdentity='sender@example.com'
)
```

> **Note:** Deleting a template or identity does not affect emails you already sent.
