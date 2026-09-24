# Tenant Setup Guide

> Examples shown in Python, Node.js, and AWS CLI.

Tenants are the recommended architecture for ALL Amazon SES customers — not just ISVs or multi-tenant platforms. Even with a single workload, tenants protect your sending by providing per-stream reputation monitoring and enforcement isolation.

## Why Tenants Should Be Your Default

Tenants give each mail stream its own reputation boundary. If one stream develops issues, enforcement applies only to that tenant — your other mail streams continue sending uninterrupted.

Key benefits:
- Per-tenant bounce and complaint metrics
- Automated enforcement policies (Standard, Strict, or None)
- Amazon EventBridge notifications for reputation findings and status changes
- Clear workload isolation for troubleshooting

**Set up tenants from day one.** Don't wait until you have a problem.

## When to Use Multiple Tenants

| Scenario | Tenant Strategy |
|----------|----------------|
| Single app, one mail stream | 1 tenant for the app |
| Single app, separate transactional + marketing | 1 tenant per mail type |
| ISV/SaaS with downstream customers | 1 tenant per customer |
| Enterprise with multiple business units | 1 tenant per business unit |
| Regulatory requirements | 1 tenant per compliance boundary |

## Prerequisites

Before you begin, confirm you have the following:

- An AWS account with Amazon SES access
- AWS CLI or SDK installed and configured with credentials
- A verified email identity (domain or email address) in Amazon SES (see [verify-domain-identity.md](../identity/verify-domain-identity.md))
- A configuration set created (see [configuration-sets.md](../configuration/configuration-sets.md))

## Step-by-Step: Create Your First Tenant

### 1. Create the Tenant

**Python:**
```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

response = client.create_tenant(TenantName='my-app-transactional')
print(f"Tenant created: {response}")
```

**Node.js:**
```javascript
import { SESv2Client, CreateTenantCommand } from '@aws-sdk/client-sesv2';

const client = new SESv2Client({ region: 'us-east-1' });
const response = await client.send(new CreateTenantCommand({
    TenantName: 'my-app-transactional'
}));
console.log('Tenant created:', response);
```

**AWS CLI:**
```bash
aws sesv2 create-tenant --tenant-name my-app-transactional --region us-east-1
```

### 2. Associate Resources

A tenant **cannot send email** without at least one associated identity and one associated configuration set. If you attempt to send with a tenant that's missing either, the API returns:

```
AccessDeniedException: Tenant not associated with resources [<missing-resource-ARNs>].
```

**Why associations exist:** Associations are an authorization gate — they control which identities and configuration sets a tenant is allowed to use when sending. They do not create or own the resources.

**Key point: resources are shared.** You do not need to create a new identity or configuration set for each tenant. The same identity and configuration set can be associated with multiple tenants. For most setups, you have one verified domain and one or a few configuration sets, and you associate them with every tenant.

| Scenario | Identity | Configuration Set |
|----------|----------|-------------------|
| **Fastest setup** | Associate your existing verified domain with the tenant | Associate your existing config set with the tenant |
| **Per-tenant metrics** | Same shared identity | Create a config set per tenant for independent CloudWatch metrics |
| **ISV with customer domains** | One identity per customer domain | One config set per customer |

**Minimum required:** 1 verified identity + 1 configuration set per tenant.

```python
# Associate a domain identity (can be shared across tenants)
client.create_tenant_resource_association(
    TenantName='my-app-transactional',
    ResourceArn='arn:aws:ses:us-east-1:123456789012:identity/example.com'
)

# Associate a configuration set (can be shared across tenants)
client.create_tenant_resource_association(
    TenantName='my-app-transactional',
    ResourceArn='arn:aws:ses:us-east-1:123456789012:configuration-set/transactional-config'
)
```

### 3. Set Enforcement Policy

Enforcement policies control what happens when reputation metrics exceed thresholds.

| Policy | Behavior | Recommended For |
|--------|----------|----------------|
| **Standard** | Auto-pauses on high-severity findings | Most workloads (recommended) |
| **Strict** | Auto-pauses on any finding (including low-severity) | High-risk tenants |
| **None** | No auto-enforcement; findings still visible | Initial monitoring period |

```python
client.update_reputation_entity_policy(
    ReputationEntityType='RESOURCE',
    ReputationEntityReference='arn:aws:ses:us-east-1:123456789012:tenant/my-app-transactional',
    ReputationEntityPolicy='arn:aws:ses:us-east-1:aws:reputation-policy/standard'
)
```

**Recommendation:** Start with `None` while onboarding, then switch to `Standard` once your mail streams are stable.

### 4. Send Email with Tenant

Add `TenantName` and `ConfigurationSetName` to your SendEmail call:

```python
response = client.send_email(
    FromEmailAddress='noreply@example.com',
    Destination={'ToAddresses': ['recipient@example.com']},
    Content={
        'Simple': {
            'Subject': {'Data': 'Order Confirmation'},
            'Body': {'Text': {'Data': 'Your order has been confirmed.'}}
        }
    },
    ConfigurationSetName='transactional-config',
    TenantName='my-app-transactional'
)
```

**SMTP:** Add the `X-SES-TENANT` header:
```
X-SES-TENANT: my-app-transactional
```

### 5. Monitor Tenant Health

**Check tenant status:**
```python
response = client.get_tenant(TenantName='my-app-transactional')
tenant = response['Tenant']
print(f"Sending status: {tenant.get('SendingStatus')}")
```

**Check reputation findings:**
```python
findings = client.list_recommendations(
    Filter={'RESOURCE_ARN': 'arn:aws:ses:us-east-1:123456789012:tenant/my-app-transactional'}
)
for finding in findings.get('Recommendations', []):
    print(f"Type: {finding['Type']}, Impact: {finding['Impact']}, Status: {finding['Status']}")
```

**Amazon CloudWatch metrics:** SES publishes per-tenant metrics under `AWS/SES` namespace with `TenantId` and `TenantName` dimensions.

### 6. Set Up EventBridge Notifications

Get notified when tenant status changes or reputation findings are detected:

```python
import boto3

events_client = boto3.client('events', region_name='us-east-1')

# Rule for tenant sending status changes
events_client.put_rule(
    Name='ses-tenant-status-changes',
    EventPattern='{"source": ["aws.ses"], "detail-type": ["Sending Status Disabled", "Sending Status Enabled"]}',
    State='ENABLED'
)

# Add SNS topic as target
events_client.put_targets(
    Rule='ses-tenant-status-changes',
    Targets=[{
        'Id': 'sns-target',
        'Arn': 'arn:aws:sns:us-east-1:123456789012:ses-alerts'
    }]
)
```

## ISV / Multi-Tenant Platform Pattern

For ISVs sending on behalf of downstream customers:

1. **One tenant per customer** — isolates reputation per customer
2. **Standard enforcement policy** — auto-pauses bad customers without affecting good ones
3. **Shared identity** — your sending domain, associated to all tenants
4. **Per-tenant configuration set** — enables per-customer metrics
5. **EventBridge alerts** — get notified when any customer tenant hits reputation issues

```python
def onboard_customer(customer_name, domain_arn, account_id, region='us-east-1'):
    client = boto3.client('sesv2', region_name=region)

    # Create tenant
    client.create_tenant(TenantName=f'customer-{customer_name}')

    # Create config set for this customer
    client.create_configuration_set(ConfigurationSetName=f'config-{customer_name}')

    # Associate resources
    client.create_tenant_resource_association(
        TenantName=f'customer-{customer_name}',
        ResourceArn=domain_arn
    )
    client.create_tenant_resource_association(
        TenantName=f'customer-{customer_name}',
        ResourceArn=f'arn:aws:ses:{region}:{account_id}:configuration-set/config-{customer_name}'
    )

    # Set enforcement policy
    # Start with None for monitoring, switch to Standard once stable
    return f'customer-{customer_name}'
```

## Tenant Sending Statuses

| Status | Meaning | Can Send? |
|--------|---------|-----------|
| `Enabled` | Normal operation | Yes |
| `Paused` | Manually paused by you | No |
| `Enforced` | Auto-paused by SES due to reputation issues | No |
| `Reinstated` | Sending reactivated after pause (grace period) | Yes |

## Pause / Resume a Tenant

```python
# Pause
client.update_reputation_entity_customer_managed_status(
    ReputationEntityType='RESOURCE',
    ReputationEntityReference='arn:aws:ses:us-east-1:123456789012:tenant/tenantId',
    SendingStatus='DISABLED'
)

# Resume
client.update_reputation_entity_customer_managed_status(
    ReputationEntityType='RESOURCE',
    ReputationEntityReference='arn:aws:ses:us-east-1:123456789012:tenant/tenantId',
    SendingStatus='ENABLED'
)
```

## Common Tenant Errors

| Error | HTTP | Cause | Fix |
|-------|------|-------|-----|
| `NotFoundException: The requested tenant <name> does not exist.` | 404 | Tenant name is wrong or tenant not created | Check tenant name, create if needed |
| `MessageRejected: Sending disabled for <tenant-ARN>.` | 400 | Tenant is paused (manually or by enforcement) | Check tenant status, resume if appropriate |
| `AccessDeniedException: Tenant not associated with resources [<ARNs>].` | 403 | Identity or config set not associated with tenant | Associate the missing resources |

## Limits

- Default: 10,000 tenants per account (up to 300,000 with approval)
- Tenants are regional — not replicated across AWS regions
- Must specify associated configuration set when sending
- Combined activity of all tenants still affects overall account reputation

## Clean Up

To avoid ongoing charges, delete the resources created in this guide.

### Delete the Tenant

Deleting a tenant automatically removes its resource associations. The associated resources themselves (identities, configuration sets) are not deleted.

**AWS CLI:**
```bash
aws sesv2 delete-tenant \
    --tenant-name my-app-transactional \
    --region us-east-1
```

**Python:**
```python
client.delete_tenant(TenantName='my-app-transactional')
```

## Further Reading

- [AWS Blog: Implement Tenants in SES — Part 2: Assessment and Planning](https://aws.amazon.com/blogs/messaging-and-targeting/implement-tenants-in-your-amazon-ses-environment-part-2-assessment-and-planning/)
- [Amazon SES Developer Guide: Sending Email with Tenants](https://docs.aws.amazon.com/ses/latest/dg/sending-email-tenants.html)
- [SES Developer Guide: Tenants](https://docs.aws.amazon.com/ses/latest/dg/tenants.html)
