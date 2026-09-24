# Sending Email via SMTP

Use the SES SMTP interface when your application or mail server sends email via SMTP rather than an API call (WordPress, legacy systems, Postfix, etc.).

## SMTP Endpoints

| Region | Endpoint |
|--------|----------|
| us-east-1 | `email-smtp.us-east-1.amazonaws.com` |
| us-west-2 | `email-smtp.us-west-2.amazonaws.com` |
| eu-west-1 | `email-smtp.eu-west-1.amazonaws.com` |
| ap-southeast-2 | `email-smtp.ap-southeast-2.amazonaws.com` |

Full list: https://docs.aws.amazon.com/ses/latest/dg/regions.html

**Ports:** 587 (STARTTLS, recommended), 465 (TLS Wrapper), 25 (STARTTLS, often blocked by ISPs)

## Prerequisites

Before you begin, confirm you have the following:

- An AWS account with Amazon SES access
- A verified email identity (domain or email address) in Amazon SES
- An SMTP library for your language (Python `smtplib` is built-in; Node.js requires `nodemailer`)

## Step 1: Create SMTP Credentials

SMTP credentials are derived from AWS Identity and Access Management (IAM) credentials. Create them in the SES console:

1. Open the SES console
2. Go to **SMTP settings**
3. Choose **Create SMTP credentials**
4. Download the username and password

**Or generate programmatically** from an IAM access key using the signing algorithm documented in the SES Developer Guide.

> **Security:** Store SMTP credentials securely using AWS Secrets Manager or your application's secret management system. Do not hard-code credentials in source code.

## Step 2: Send via SMTP

**Python (smtplib):**
```python
import smtplib
from email.mime.text import MIMEText

SMTP_HOST = 'email-smtp.us-east-1.amazonaws.com'
SMTP_PORT = 587
SMTP_USER = 'YOUR_SMTP_USERNAME'
SMTP_PASS = 'YOUR_SMTP_PASSWORD'

msg = MIMEText('This email was sent via SES SMTP.')
msg['Subject'] = 'Hello from SES SMTP'
msg['From'] = 'sender@example.com'
msg['To'] = 'recipient@example.com'

# Add configuration set header
msg['X-SES-CONFIGURATION-SET'] = 'my-config-set'

# Add tenant header (recommended)
msg['X-SES-TENANT'] = 'my-tenant'

with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
    server.starttls()
    server.login(SMTP_USER, SMTP_PASS)
    server.sendmail(msg['From'], [msg['To']], msg.as_string())

print('Email sent via SMTP')
```

**Node.js (nodemailer):**
```javascript
import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransport({
    host: 'email-smtp.us-east-1.amazonaws.com',
    port: 587,
    secure: false,
    auth: {
        user: 'YOUR_SMTP_USERNAME',
        pass: 'YOUR_SMTP_PASSWORD'
    }
});

await transporter.sendMail({
    from: 'sender@example.com',
    to: 'recipient@example.com',
    subject: 'Hello from SES SMTP',
    text: 'This email was sent via SES SMTP.',
    headers: {
        'X-SES-CONFIGURATION-SET': 'my-config-set',
        'X-SES-TENANT': 'my-tenant'
    }
});
```

## SES-Specific SMTP Headers

| Header | Purpose |
|--------|---------|
| `X-SES-CONFIGURATION-SET` | Specify configuration set |
| `X-SES-TENANT` | Specify tenant |
| `X-SES-MESSAGE-TAGS` | Add message tags (`key1=value1, key2=value2`) |
| `X-SES-FROM-ARN` | Sending authorization (cross-account sending) |

## SMTP vs API

| Consideration | SMTP | API (V2 SDK) |
|---------------|------|-------------|
| Best for | Legacy systems, mail servers, WordPress | New applications, programmatic sends |
| Authentication | SMTP credentials (IAM-derived) | IAM credentials / roles |
| Bulk sending | One message at a time | `SendBulkEmail` for batch |
| Templates | Not supported via SMTP | Native template support |
| Error handling | SMTP error codes | SDK exceptions with details |


## Clean Up

To avoid ongoing charges, delete the resources created in this guide.

### Delete SMTP Credentials

SMTP credentials are derived from IAM credentials. Delete the IAM user created for SMTP sending.

**AWS CLI:**

First, delete the access keys associated with the IAM user, then delete the user:

```bash
# List access keys for the SMTP user
aws iam list-access-keys \
    --user-name ses-smtp-user

# Delete the access key
aws iam delete-access-key \
    --user-name ses-smtp-user \
    --access-key-id AKIAIOSFODNN7EXAMPLE

# Detach any policies
aws iam detach-user-policy \
    --user-name ses-smtp-user \
    --policy-arn arn:aws:iam::aws:policy/AmazonSesSendingAccess

# Delete the IAM user
aws iam delete-user \
    --user-name ses-smtp-user
```

**Python:**

```python
import boto3

iam_client = boto3.client('iam')

# List and delete access keys
keys = iam_client.list_access_keys(UserName='ses-smtp-user')
for key in keys['AccessKeyMetadata']:
    iam_client.delete_access_key(
        UserName='ses-smtp-user',
        AccessKeyId=key['AccessKeyId']
    )

# Detach policies
attached = iam_client.list_attached_user_policies(UserName='ses-smtp-user')
for policy in attached['AttachedPolicies']:
    iam_client.detach_user_policy(
        UserName='ses-smtp-user',
        PolicyArn=policy['PolicyArn']
    )

# Delete the IAM user
iam_client.delete_user(UserName='ses-smtp-user')
```

### Delete Test Identity

If you created an email identity for testing, delete it:

**AWS CLI:**

```bash
aws sesv2 delete-email-identity \
    --email-identity sender@example.com \
    --region us-east-1
```

**Python:**

```python
ses_client = boto3.client('sesv2', region_name='us-east-1')

ses_client.delete_email_identity(
    EmailIdentity='sender@example.com'
)
```

> **Note:** Before deleting the IAM user, you must first delete their access keys and any attached policies. The examples in this section handle this in the correct order.
