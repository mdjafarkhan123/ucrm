---
description: "Step-by-step guide to set up Amazon SES Mail Manager from scratch. Create a traffic policy, rule set, archive, and ingress point for inbound email processing."
---

# Getting Started with Mail Manager

This guide walks through setting up a complete Mail Manager pipeline from scratch: a traffic policy, rule set, and ingress point that receives email and routes it to an archive.

## Prerequisites

- AWS account with SES Mail Manager enabled
- boto3 installed: `pip install boto3`
- AWS credentials configured: `aws configure`
- A domain you control (to update MX records)

## Supported Regions

Mail Manager is available in all commercial AWS regions where Amazon SES is offered (27 regions as of December 2025). This includes all major US, Europe, Asia Pacific, Middle East, Africa, Canada, and South America regions. For the latest list, see [SES Mail Manager region availability](https://aws.amazon.com/about-aws/whats-new/2025/12/ses-mail-manager-10-regions/).

## Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:CreateArchive",
        "ses:CreateTrafficPolicy",
        "ses:CreateRuleSet",
        "ses:CreateIngressPoint",
        "ses:GetIngressPoint",
        "ses:ListTrafficPolicies",
        "ses:ListRuleSets",
        "ses:ListIngressPoints",
        "ses:ListArchives",
        "ses:DeleteArchive",
        "ses:DeleteTrafficPolicy",
        "ses:DeleteRuleSet",
        "ses:DeleteIngressPoint"
      ],
      "Resource": "*"
    }
  ]
}
```

Mail Manager IAM actions use the `ses:` prefix (such as `ses:CreateIngressPoint`, `ses:CreateTrafficPolicy`, `ses:CreateRuleSet`), not a separate `mailmanager:` prefix. `"Resource": "*"` is required here because Mail Manager operations do not currently support resource-level ARN restrictions. Follow the principle of least privilege by scoping to only the specific actions your workflow requires, as shown above.

## Step 1: Create an Archive (optional but recommended)

Create the archive first — it has no dependencies and you'll reference its **ID** in the rule set.

```python
import boto3

client = boto3.client('mailmanager', region_name='us-east-1')

archive = client.create_archive(
    ArchiveName='my-email-archive',
    Retention={'RetentionPeriod': 'ONE_YEAR'}
)
archive_id = archive['ArchiveId']
# TargetArchive in rule actions uses the archive ID, NOT the full ARN
print(f"Archive ID: {archive_id}")
```

Retention options: `THREE_MONTHS`, `SIX_MONTHS`, `NINE_MONTHS`, `ONE_YEAR`, `EIGHTEEN_MONTHS`, `TWO_YEARS`, `THIRTY_MONTHS`, `THREE_YEARS`, `FOUR_YEARS`, `FIVE_YEARS`, `SIX_YEARS`, `SEVEN_YEARS`, `EIGHT_YEARS`, `NINE_YEARS`, `TEN_YEARS`, `PERMANENT`

**Cost note:** Archives incur storage charges based on email volume and retention period. Ingress points incur per-message processing charges. Delete these resources when no longer needed to stop charges. See [Cleanup](#cleanup).

## Step 2: Create a Traffic Policy

Traffic policies are connection-level filters. This example allows all connections (permissive default for getting started):

```python
traffic_policy = client.create_traffic_policy(
    TrafficPolicyName='my-traffic-policy',
    DefaultAction='ALLOW',
    PolicyStatements=[]  # No statements = DefaultAction applies to everything
)
traffic_policy_id = traffic_policy['TrafficPolicyId']
print(f"Traffic Policy ID: {traffic_policy_id}")
```

For a more restrictive policy that only accepts email for your domain:

```python
traffic_policy = client.create_traffic_policy(
    TrafficPolicyName='my-domain-only-policy',
    DefaultAction='DENY',
    PolicyStatements=[
        {
            'Action': 'ALLOW',
            'Conditions': [
                {
                    'StringExpression': {
                        'Evaluate': {'Attribute': 'RECIPIENT'},
                        'Operator': 'ENDS_WITH',
                        'Values': ['@example.com']
                    }
                }
            ]
        }
    ]
)
```

## Step 3: Create a Rule Set

Rule sets process the full message. This example archives all email:

```python
rule_set = client.create_rule_set(
    RuleSetName='my-rule-set',
    Rules=[
        {
            'Name': 'archive-all',
            'Actions': [
                {
                    'Archive': {
                        'TargetArchive': archive_id,  # use archive ID, NOT ARN
                        'ActionFailurePolicy': 'CONTINUE'
                    }
                }
            ]
            # No Conditions = matches all messages
        }
    ]
)
rule_set_id = rule_set['RuleSetId']
print(f"Rule Set ID: {rule_set_id}")
```

## Step 4: Create an Ingress Point

Now create the ingress point, referencing the traffic policy and rule set:

```python
ingress = client.create_ingress_point(
    IngressPointName='my-ingress-point',
    Type='OPEN',  # OPEN | AUTH | MTLS
    TrafficPolicyId=traffic_policy_id,
    RuleSetId=rule_set_id,
    TlsPolicy='REQUIRED'  # REQUIRED | OPTIONAL | FIPS
    # Default: FIPS in US/CA regions, REQUIRED elsewhere.
    # FIPS requires FIPS-validated cryptography (US/CA only, immutable).
    # OPTIONAL allows plaintext connections (OPEN endpoints only).
)
ingress_point_id = ingress['IngressPointId']
print(f"Ingress Point ID: {ingress_point_id}")
```

## Step 5: Wait for ACTIVE Status

The ingress point takes a few minutes to provision. Poll until it's ready:

```python
import time

while True:
    status = client.get_ingress_point(IngressPointId=ingress_point_id)
    state = status['Status']
    print(f"Status: {state}")
    if state == 'ACTIVE':
        hostname = status['ARecord']
        print(f"Ingress hostname: {hostname}")
        break
    elif state == 'FAILED':
        raise Exception("Ingress point provisioning failed")
    time.sleep(10)
```

## Step 6: Update Your MX Record

Once the ingress point is ACTIVE, update your domain's MX record to point to the ingress hostname:

```
example.com.  MX  10  <ingress-hostname>.mailmanager.us-east-1.amazonaws.com.
```

Replace `<ingress-hostname>` with the `ARecord` value from `get_ingress_point()`.

DNS propagation typically takes a few minutes to a few hours.

## Verify the Setup

List all your resources to confirm everything is in place:

```python
print("Traffic Policies:", client.list_traffic_policies()['TrafficPolicies'])
print("Rule Sets:", client.list_rule_sets()['RuleSets'])
print("Ingress Points:", client.list_ingress_points()['IngressPoints'])
print("Archives:", client.list_archives()['Archives'])
```

## Cleanup

To delete the resources created in this guide and stop incurring charges, delete in reverse dependency order:

```python
# Step 0: Update DNS — remove or redirect the MX record BEFORE deleting
# the ingress point. A dangling MX record causes inbound email to bounce.
# Allow time for DNS propagation before proceeding.

# Step 1: Delete ingress point (stops email delivery immediately)
client.delete_ingress_point(IngressPointId=ingress_point_id)

# Step 2: Delete rule set
client.delete_rule_set(RuleSetId=rule_set_id)

# Step 3: Delete traffic policy
client.delete_traffic_policy(TrafficPolicyId=traffic_policy_id)

# Step 4: Delete archive (async — enters PENDING_DELETION)
# WARNING: This permanently removes all archived email. Export first.
client.delete_archive(ArchiveId=archive_id)
```

For the full teardown procedure, see the [Cleanup Guide](../cleanup/cleanup-guide.md).

## Next Steps

- Add spam filtering: see [Traffic Policy Guide](../traffic-policies/traffic-policy-guide.md)
- Route email to different destinations: see [Rule Set Guide](../rule-sets/rule-set-guide.md)
- Search archived email: see [Archive Guide](../archives/archive-guide.md)
- Build allow/block lists: see [Address List Guide](../address-lists/address-list-guide.md)
