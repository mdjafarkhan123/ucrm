# Email Validation Guide

Amazon SES Email Validation checks email addresses for deliverability risk before you send. It reduces bounces, protects your sender reputation, and prevents enforcement actions.

## Why Validate

- Bounce rate > 5% triggers SES enforcement (PAUSE, THROTTLE, or SHUTDOWN)
- Invalid addresses are the #1 cause of high bounce rates
- Spam traps and disposable addresses damage sender reputation
- Validating at point of collection prevents bad data from entering your pipeline

## Prerequisites

Before you begin, confirm you have the following:

- An AWS account with Amazon SES access
- AWS CLI or SDK installed and configured with credentials
- IAM permissions for `ses:GetEmailAddressInsights` and `iam:CreateServiceLinkedRole`

## Three Validation Modes

### 1. API Validation (`GetEmailAddressInsights`)

Validate individual addresses on demand. Use for:
- Sign-up forms and subscription flows
- Periodic batch cleaning of existing databases
- Pre-send validation in your application logic

### 2. Auto Validation

Automatically screens all outbound email. SES filters based on a configurable delivery likelihood threshold:
- **High** — Only delivers to highest-confidence addresses
- **Medium** — Includes medium-confidence addresses

Operates without code changes. Enable in the SES console or via API.

### 3. Email Validation Dashboard

View validation metrics and results in the SES console.

## API Validation: Step by Step

### Validate a Single Address

> **Cost:** The Email Validation API incurs a per-request charge. See [Amazon SES pricing](https://aws.amazon.com/ses/pricing/) for current rates. Consider validating only at the point of address collection rather than on every send.

**Python:**
```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

response = client.get_email_address_insights(
    EmailAddress='user@example.com'
)

validation = response['MailboxValidation']
print(f"Valid: {validation['IsValid']['ConfidenceVerdict']}")

for check, result in validation['Evaluations'].items():
    print(f"  {check}: {result['ConfidenceVerdict']}")
```

**Node.js:**
```javascript
import { SESv2Client, GetEmailAddressInsightsCommand } from '@aws-sdk/client-sesv2';

const client = new SESv2Client({ region: 'us-east-1' });

const response = await client.send(new GetEmailAddressInsightsCommand({
    EmailAddress: 'user@example.com'
}));

const validation = response.MailboxValidation;
console.log(`Valid: ${validation.IsValid.ConfidenceVerdict}`);

for (const [check, result] of Object.entries(validation.Evaluations)) {
    console.log(`  ${check}: ${result.ConfidenceVerdict}`);
}
```

**AWS CLI:**
```bash
aws sesv2 get-email-address-insights --email-address user@example.com --region us-east-1
```

### Response Format

```json
{
    "MailboxValidation": {
        "IsValid": {
            "ConfidenceVerdict": "HIGH"
        },
        "Evaluations": {
            "HasValidSyntax": {"ConfidenceVerdict": "HIGH"},
            "HasValidDnsRecords": {"ConfidenceVerdict": "MEDIUM"},
            "MailboxExists": {"ConfidenceVerdict": "MEDIUM"},
            "IsRoleAddress": {"ConfidenceVerdict": "LOW"},
            "IsDisposable": {"ConfidenceVerdict": "LOW"},
            "IsRandomInput": {"ConfidenceVerdict": "LOW"}
        }
    }
}
```

### Interpreting Results

**IsValid Confidence:**
| Verdict | Meaning | Action |
|---------|---------|--------|
| `HIGH` | High delivery likelihood | Safe to send |
| `MEDIUM` | Moderate delivery likelihood | Send with caution, monitor bounces |
| `LOW` | Low delivery likelihood | Sending is very unlikely to succeed — high bounce risk |

**Individual Evaluations:**

| Check | What It Tests | HIGH Means |
|-------|--------------|------------|
| `HasValidSyntax` | RFC-compliant email format | Syntax is correct |
| `HasValidDnsRecords` | Domain exists and can receive email | DNS is configured |
| `MailboxExists` | Specific mailbox exists | Mailbox confirmed |
| `IsRoleAddress` | Role-based (admin@, info@, support@) | IS a role address (lower engagement) |
| `IsDisposable` | Temporary/throwaway domain | IS disposable (don't send) |
| `IsRandomInput` | Randomly generated pattern | IS random (likely fake) |

**Note:** For `IsRoleAddress`, `IsDisposable`, and `IsRandomInput`, HIGH means the address IS that type (a negative signal).

## Batch Validation Pattern

For cleaning existing email lists:

```python
import boto3
import csv

client = boto3.client('sesv2', region_name='us-east-1')

def validate_list(input_file, output_file):
    with open(input_file) as infile, open(output_file, 'w', newline='') as outfile:
        reader = csv.reader(infile)
        writer = csv.writer(outfile)
        writer.writerow(['email', 'valid', 'confidence', 'disposable', 'role_address'])

        for row in reader:
            email = row[0].strip()
            try:
                response = client.get_email_address_insights(EmailAddress=email)
                v = response['MailboxValidation']
                writer.writerow([
                    email,
                    v['IsValid']['ConfidenceVerdict'],
                    v['Evaluations']['MailboxExists']['ConfidenceVerdict'],
                    v['Evaluations']['IsDisposable']['ConfidenceVerdict'],
                    v['Evaluations']['IsRoleAddress']['ConfidenceVerdict']
                ])
            except Exception as e:
                writer.writerow([email, 'ERROR', str(e), '', ''])

validate_list('emails.csv', 'validation_results.csv')
```

## AWS Identity and Access Management (IAM) Permissions Required

```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": "ses:GetEmailAddressInsights",
        "Resource": "*"
    },
    {
        "Effect": "Allow",
        "Action": "iam:CreateServiceLinkedRole",
        "Resource": "arn:aws:iam::123456789012:role/aws-service-role/ses.amazonaws.com/AWSServiceRoleForAmazonSES",
        "Condition": {
            "StringLike": {
                "iam:AWSServiceName": "ses.amazonaws.com"
            }
        }
    }]
}
```

## Best Practices

1. **Validate at point of collection** — check addresses when users sign up, not after
2. **Reject LOW confidence** — do not add these to your sending pipeline
3. **Flag disposable addresses** — block or require additional verification
4. **Re-validate periodically** — mailboxes change over time; validate existing lists quarterly
5. **Enable Auto Validation** — as a safety net, enable auto-validation to filter risky addresses automatically
6. **Combine with suppression lists** — validation catches bad addresses; suppression lists catch addresses that bounced or complained

## Clean Up

The Email Validation API does not create persistent resources. However, if you created test resources while following this guide, clean them up.

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

> **Note:** The Email Validation API incurs per-request charges but does not create resources that persist after the API call. Remove any IAM policies created specifically for email validation if they are no longer needed.

## Further Reading

- [AWS Blog: How to Improve Email Sender Reputation with SES Email Validation](https://aws.amazon.com/blogs/messaging-and-targeting/how-to-improve-email-sender-reputation-with-amazon-ses-email-validation/)
- [SES Developer Guide: Email Validation](https://docs.aws.amazon.com/ses/latest/dg/email-validation.html)
- [SES Developer Guide: Email Validation API](https://docs.aws.amazon.com/ses/latest/dg/email-validation-api.html)
- [SES Developer Guide: Auto Validation](https://docs.aws.amazon.com/ses/latest/dg/email-validation-auto.html)
