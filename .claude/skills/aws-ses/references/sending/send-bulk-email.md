# Sending Bulk Email

Send to multiple recipients with per-recipient personalization using `SendBulkEmail`.

## When to Use Bulk Sending

- Newsletters, promotions, announcements to many recipients
- Onboarding email sequences
- Any scenario with the same template but different personalization per recipient

## Prerequisites

1. A verified identity (domain recommended for bulk)
2. A configuration set with event destinations
3. An email template created in SES
4. Production access (sandbox limits are too low for bulk)
5. Tenants configured for workload isolation

## Step 1: Create a Template

```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

client.create_email_template(
    TemplateName='newsletter-march-2026',
    TemplateContent={
        'Subject': '{{subject_line}}',
        'Html': '<h1>Hi {{name}},</h1><p>{{content}}</p><p><a href="{{unsubscribe_url}}">Unsubscribe</a></p>',
        'Text': 'Hi {{name}},\n\n{{content}}\n\nUnsubscribe: {{unsubscribe_url}}'
    }
)
```

## Step 2: Send Bulk Email

```python
import json

response = client.send_bulk_email(
    FromEmailAddress='newsletter@example.com',
    DefaultContent={
        'Template': {
            'TemplateName': 'newsletter-march-2026',
            'TemplateData': json.dumps({
                'subject_line': 'March Newsletter',
                'content': 'Default content here.',
                'unsubscribe_url': 'https://example.com/unsubscribe'
            })
        }
    },
    BulkEmailEntries=[
        {
            'Destination': {'ToAddresses': ['alice@example.com']},
            'ReplacementEmailContent': {
                'ReplacementTemplate': {
                    'ReplacementTemplateData': json.dumps({
                        'name': 'Alice',
                        'unsubscribe_url': 'https://example.com/unsubscribe?id=alice'
                    })
                }
            }
        },
        {
            'Destination': {'ToAddresses': ['bob@example.com']},
            'ReplacementEmailContent': {
                'ReplacementTemplate': {
                    'ReplacementTemplateData': json.dumps({
                        'name': 'Bob',
                        'unsubscribe_url': 'https://example.com/unsubscribe?id=bob'
                    })
                }
            }
        }
    ],
    ConfigurationSetName='marketing-config'
)

# Check results
for i, result in enumerate(response['BulkEmailEntryResults']):
    if result['Status'] == 'SUCCESS':
        print(f"Entry {i}: Sent (MessageId: {result.get('MessageId')})")
    else:
        print(f"Entry {i}: FAILED - {result.get('Error')}")
```

## Limits

- **50 recipients** per `SendBulkEmail` call
- For larger lists, batch into groups of 50 and call repeatedly
- Respect your account's TPS limit — throttle your batch calls accordingly

## Batch Processing Pattern

```python
import json
import time

def send_newsletter(recipients, template_name, default_data, config_set, batch_size=50):
    client = boto3.client('sesv2', region_name='us-east-1')
    results = []

    for i in range(0, len(recipients), batch_size):
        batch = recipients[i:i + batch_size]

        entries = []
        for r in batch:
            entries.append({
                'Destination': {'ToAddresses': [r['email']]},
                'ReplacementEmailContent': {
                    'ReplacementTemplate': {
                        'ReplacementTemplateData': json.dumps(r.get('data', {}))
                    }
                }
            })

        response = client.send_bulk_email(
            FromEmailAddress='newsletter@example.com',
            DefaultContent={
                'Template': {
                    'TemplateName': template_name,
                    'TemplateData': json.dumps(default_data)
                }
            },
            BulkEmailEntries=entries,
            ConfigurationSetName=config_set
        )

        results.extend(response['BulkEmailEntryResults'])
        time.sleep(0.1)  # Brief pause between batches

    return results
```

## Best Practices

1. **Always include an unsubscribe link** — required for compliance (CAN-SPAM, GDPR)
2. **Use separate config sets** for marketing vs transactional email
3. **Validate addresses first** — use Email Validation API before adding to bulk lists
4. **Monitor bounce/complaint rates** closely after bulk sends
5. **Warm up gradually** — don't send 100K emails on day one. Ramp up volume over days/weeks.
6. **Use tenants** — isolate bulk marketing from transactional email


## Clean Up

To avoid ongoing charges, delete the resources created in this guide.

### Delete Email Template

**AWS CLI:**
```bash
aws sesv2 delete-email-template \
    --template-name newsletter-march-2026 \
    --region us-east-1
```

**Python:**
```python
client.delete_email_template(
    TemplateName='newsletter-march-2026'
)
```

> **Note:** Deleting a template does not affect emails already sent using that template.
