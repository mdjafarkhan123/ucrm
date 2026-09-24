# Verify Domain Identity with DKIM, SPF, and DMARC

Complete guide to setting up a domain for sending email through Amazon SES with full email authentication.

> Examples shown in Python, Node.js, and AWS CLI.

## Why This Matters

Gmail, Yahoo, and other major mailbox providers reject or spam-filter email that lacks proper authentication. Configuring DKIM, SPF, and DMARC is required for production email sending.

## Overview

| Authentication | What It Does | Required? |
|---|---|---|
| **DKIM** | Cryptographically signs emails to prove they came from your domain | Yes — SES configures automatically via Easy DKIM |
| **SPF** | Declares which servers can send from your MAIL FROM domain | Yes — requires custom MAIL FROM domain |
| **DMARC** | Policy that tells receivers what to do when DKIM/SPF fail | Strongly recommended — required by Gmail/Yahoo for bulk senders |

## Prerequisites

Before you begin, confirm you have the following:

- An AWS account with Amazon SES access
- AWS CLI or SDK installed and configured with credentials
- DNS management access for your domain (to add CNAME, MX, and TXT records)
- Access to the SES console or CLI

## Step 1: Create and Verify Domain Identity

**Python:**
```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

response = client.create_email_identity(
    EmailIdentity='example.com',
    DkimSigningAttributes={
        'DomainSigningAttributesOrigin': 'AWS_SES'  # Easy DKIM
    }
)

# Extract DKIM tokens for DNS configuration
dkim_tokens = response['DkimAttributes']['Tokens']
print("Add these CNAME records to your DNS:")
for token in dkim_tokens:
    print(f"  {token}._domainkey.example.com -> {token}.dkim.amazonses.com")
```

**Node.js:**
```javascript
import { SESv2Client, CreateEmailIdentityCommand } from '@aws-sdk/client-sesv2';

const client = new SESv2Client({ region: 'us-east-1' });

const response = await client.send(new CreateEmailIdentityCommand({
    EmailIdentity: 'example.com',
    DkimSigningAttributes: {
        DomainSigningAttributesOrigin: 'AWS_SES'
    }
}));

const tokens = response.DkimAttributes.Tokens;
console.log('Add these CNAME records to your DNS:');
tokens.forEach(token => {
    console.log(`  ${token}._domainkey.example.com -> ${token}.dkim.amazonses.com`);
});
```

**AWS CLI:**
```bash
aws sesv2 create-email-identity \
    --email-identity example.com \
    --dkim-signing-attributes DomainSigningAttributesOrigin=AWS_SES \
    --region us-east-1
```

## Step 2: Add DKIM DNS Records

Add 3 CNAME records to your domain's DNS:

| Type | Name | Value |
|------|------|-------|
| CNAME | `{token1}._domainkey.example.com` | `{token1}.dkim.amazonses.com` |
| CNAME | `{token2}._domainkey.example.com` | `{token2}.dkim.amazonses.com` |
| CNAME | `{token3}._domainkey.example.com` | `{token3}.dkim.amazonses.com` |

Replace `{token1}`, `{token2}`, `{token3}` with the tokens from Step 1.

**DNS propagation takes up to 72 hours** but typically completes within minutes to a few hours.

## Step 3: Check Verification Status

```python
identity = client.get_email_identity(EmailIdentity='example.com')
print(f"Verification: {identity['VerifiedForSendingStatus']}")
print(f"DKIM status: {identity['DkimAttributes']['Status']}")
# Status should be 'SUCCESS' when CNAME records are detected
```

## Step 4: Configure Custom MAIL FROM Domain

A custom MAIL FROM domain enables SPF alignment. Without it, SPF checks against `amazonses.com`, not your domain.

```python
client.put_email_identity_mail_from_attributes(
    EmailIdentity='example.com',
    MailFromDomain='mail.example.com',
    BehaviorOnMxFailure='USE_DEFAULT_VALUE'
)
```

**Add these DNS records:**

| Type | Name | Value |
|------|------|-------|
| MX | `mail.example.com` | `10 feedback-smtp.us-east-1.amazonses.com` |
| TXT | `mail.example.com` | `"v=spf1 include:amazonses.com -all"` |

**Important:** The MX record region must match your SES region:
- `us-east-1` → `feedback-smtp.us-east-1.amazonses.com`
- `us-west-2` → `feedback-smtp.us-west-2.amazonses.com`
- `eu-west-1` → `feedback-smtp.eu-west-1.amazonses.com`

## Step 5: Configure DMARC

Add a DMARC TXT record to your domain:

| Type | Name | Value |
|------|------|-------|
| TXT | `_dmarc.example.com` | `"v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@example.com"` |

**DMARC policy options:**
- `p=none` — Monitor only (start here)
- `p=quarantine` — Spam-filter failures
- `p=reject` — Reject failures (strongest protection)

**Recommendation:** Start with `p=none` to collect reports, then move to `p=quarantine` or `p=reject` once you've confirmed all legitimate sending is properly authenticated.

## Step 6: Verify Everything

```python
identity = client.get_email_identity(EmailIdentity='example.com')

print(f"Verified: {identity['VerifiedForSendingStatus']}")
print(f"DKIM: {identity['DkimAttributes']['Status']}")
print(f"MAIL FROM: {identity.get('MailFromAttributes', {}).get('MailFromDomain', 'Not configured')}")
print(f"MAIL FROM status: {identity.get('MailFromAttributes', {}).get('MailFromDomainStatus', 'N/A')}")
```

## Common Issues

**SPF does NOT inherit from parent domains.** `example.com` having SPF does NOT mean `mail.example.com` has SPF. Each domain/subdomain needs its own SPF record.

**SPF applies to MAIL FROM, not From header.** SPF checks the envelope sender (MAIL FROM domain), not the visible From address. This is a common misconception.

**DKIM verification stuck in PENDING.** DNS propagation can take up to 72 hours. Verify your CNAME records are correctly configured using `dig` or `nslookup`.

**DMARC requires either DKIM or SPF alignment.** With SES Easy DKIM, your DKIM domain aligns with your From domain. With a custom MAIL FROM domain, your SPF also aligns. Having both gives you full DMARC alignment.

## DNS Record Summary

After completing all steps, your DNS should have:

| Record | Name | Value |
|--------|------|-------|
| CNAME | `{token1}._domainkey.example.com` | `{token1}.dkim.amazonses.com` |
| CNAME | `{token2}._domainkey.example.com` | `{token2}.dkim.amazonses.com` |
| CNAME | `{token3}._domainkey.example.com` | `{token3}.dkim.amazonses.com` |
| MX | `mail.example.com` | `10 feedback-smtp.{region}.amazonses.com` |
| TXT | `mail.example.com` | `"v=spf1 include:amazonses.com -all"` |
| TXT | `_dmarc.example.com` | `"v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"` |

## Clean Up

To avoid ongoing charges, delete the resources created in this guide.

### Delete Verified Identity

**AWS CLI:**
```bash
aws sesv2 delete-email-identity \
    --email-identity example.com \
    --region us-east-1
```

**Python:**
```python
client.delete_email_identity(
    EmailIdentity='example.com'
)
```

> **Note:** After deleting a domain identity, remove the DKIM, SPF, and DMARC DNS records you added during verification. Leaving orphaned DNS records does not incur charges but is a best practice for DNS hygiene.
