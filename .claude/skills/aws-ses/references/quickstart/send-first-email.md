# Quickstart: Send Your First Email with Amazon SES

Send an email using the SES V2 API in under 10 lines of code.

## Prerequisites

1. **Install the AWS SDK:**
   - Python: `pip install boto3`
   - Node.js: `npm install @aws-sdk/client-sesv2`
   - Java: Add `software.amazon.awssdk:sesv2` to Maven/Gradle
2. **AWS credentials configured** — Via environment variables, shared credentials file, or AWS Identity and Access Management (IAM) role
3. **Verified identity** — A verified email address or domain in SES (see [verify-domain-identity.md](../identity/verify-domain-identity.md))
4. **Sandbox awareness** — New accounts are in sandbox mode and can only send to verified email addresses. Use SES simulator addresses for testing (see below).

## Testing with Simulator Addresses

SES provides simulator addresses that work in sandbox mode without recipient verification. **Use these for all development and testing.**

| Recipient Address | Result |
|-------------------|--------|
| `success@simulator.amazonses.com` | Successful delivery |
| `bounce@simulator.amazonses.com` | Hard bounce |
| `complaint@simulator.amazonses.com` | Spam complaint |
| `ooto@simulator.amazonses.com` | Out-of-office auto-reply |
| `suppressionlist@simulator.amazonses.com` | Suppression list rejection |

**Never test with fake addresses at real providers** (such as `test@gmail.com`). This causes bounces that damage your sender reputation.

## Python (boto3)

```python
import boto3
from botocore.exceptions import ClientError

client = boto3.client('sesv2', region_name='us-east-1')

try:
    response = client.send_email(
        FromEmailAddress='sender@example.com',
        Destination={'ToAddresses': ['success@simulator.amazonses.com']},
        Content={
            'Simple': {
                'Subject': {'Data': 'Hello from Amazon SES'},
                'Body': {'Text': {'Data': 'This email was sent using Amazon SES V2 API.'}}
            }
        }
    )
    print(f"Message sent: {response['MessageId']}")
except ClientError as e:
    print(f"Send failed: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
```

## Node.js (AWS SDK v3)

```javascript
import { SESv2Client, SendEmailCommand } from '@aws-sdk/client-sesv2';

const client = new SESv2Client({ region: 'us-east-1' });

try {
    const response = await client.send(new SendEmailCommand({
        FromEmailAddress: 'sender@example.com',
        Destination: { ToAddresses: ['success@simulator.amazonses.com'] },
        Content: {
            Simple: {
                Subject: { Data: 'Hello from Amazon SES' },
                Body: { Text: { Data: 'This email was sent using Amazon SES V2 API.' } }
            }
        }
    }));
    console.log(`Message sent: ${response.MessageId}`);
} catch (error) {
    console.error(`Send failed: ${error.name} - ${error.message}`);
}
```

## Java (AWS SDK v2)

```java
import software.amazon.awssdk.services.sesv2.SesV2Client;
import software.amazon.awssdk.services.sesv2.model.*;
import software.amazon.awssdk.regions.Region;

SesV2Client client = SesV2Client.builder().region(Region.US_EAST_1).build();

try {
    SendEmailResponse response = client.sendEmail(SendEmailRequest.builder()
        .fromEmailAddress("sender@example.com")
        .destination(Destination.builder().toAddresses("success@simulator.amazonses.com").build())
        .content(EmailContent.builder()
            .simple(Message.builder()
                .subject(Content.builder().data("Hello from Amazon SES").build())
                .body(Body.builder()
                    .text(Content.builder().data("This email was sent using Amazon SES V2 API.").build())
                    .build())
                .build())
            .build())
        .build());
    System.out.println("Message sent: " + response.messageId());
} catch (SesV2Exception e) {
    System.err.println("Send failed: " + e.awsErrorDetails().errorCode() + " - " + e.getMessage());
}
```

## With HTML Body

Replace the `Body` section to include both text and HTML:

```python
'Body': {
    'Text': {'Data': 'Plain text fallback for email clients that do not render HTML.'},
    'Html': {'Data': '<h1>Hello</h1><p>This email was sent using Amazon SES V2 API.</p>'}
}
```

## Production Setup (Recommended)

For production sending, set up a **tenant** and **configuration set** BEFORE sending. Without them, you lose workload isolation (one bad mail stream affects your entire account) and observability (no per-stream metrics or event notifications).

Both are required for production — not either/or. **You must create these resources first**, or the `send_email` call will fail with an error.

### Step 1: Create a configuration set

A configuration set enables event tracking, CloudWatch metrics, and suppression management. Without one, you have no visibility into bounces, complaints, or deliveries at the per-stream level.

Follow the [configuration set guide](../configuration/configuration-sets.md) to create one, then come back here.

### Step 2: Create a tenant and associate resources

A tenant isolates this workload's reputation. If this mail stream develops bounce or complaint issues, enforcement applies only to this tenant — your other mail streams continue sending.

Follow the [tenant setup guide](../tenants/tenant-setup.md) to create a tenant and associate your identity and configuration set with it. You can reuse your existing verified identity and the configuration set you just created — no need to create new ones per tenant.

### Step 3: Send with tenant and configuration set

Once both resources exist and the tenant has the identity + config set associated, add them to your send call:

```python
response = client.send_email(
    FromEmailAddress='sender@example.com',
    Destination={'ToAddresses': ['success@simulator.amazonses.com']},
    Content={
        'Simple': {
            'Subject': {'Data': 'Hello from Amazon SES'},
            'Body': {'Text': {'Data': 'Sent with tenant isolation and tracking.'}}
        }
    },
    ConfigurationSetName='my-config-set',  # Enables event tracking and metrics
    TenantName='my-tenant'                 # Isolates this workload's reputation
)
```

**Common errors if you skip setup:**
- `NotFoundException` — the configuration set or tenant doesn't exist. Create it first.
- `AccessDeniedException: Tenant not associated with resources` — the tenant exists but the identity or config set isn't associated with it. Run `create_tenant_resource_association` first.

## What Happens Next

1. SES accepts the message and returns a `MessageId`
2. SES processes the message (DKIM signing, tracking headers)
3. SES delivers to the recipient's mail server
4. If delivery fails, SES retries for up to 14 hours (for temporary failures)
5. Bounces and complaints are sent to your configuration set's event destinations

## Next Steps

- [Set up tenants](../tenants/tenant-setup.md) — workload isolation and per-tenant reputation monitoring
- [Set up a configuration set](../configuration/configuration-sets.md) — event tracking, metrics, suppression
- [Verify a domain](../identity/verify-domain-identity.md) — DKIM/SPF/DMARC authentication
- [Validate email addresses](../validation/email-validation.md) — reduce bounces before sending

## Clean Up

To avoid ongoing charges, delete the resources created in this guide.

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

### Delete Configuration Set (If Created)

**AWS CLI:**
```bash
aws sesv2 delete-configuration-set \
    --configuration-set-name my-config-set \
    --region us-east-1
```

**Python:**
```python
client.delete_configuration_set(
    ConfigurationSetName='my-config-set'
)
```

> **Note:** If you created a tenant during the production setup section, delete it with `delete-tenant`. Deleting a tenant automatically removes its resource associations. See the [tenant setup guide](../tenants/tenant-setup.md) for details.
