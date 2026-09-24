---
description: "Standalone Python and CDK code examples for Amazon SES Mail Manager. Pipeline setup, routing, archive search, address list import, and SMTP relay replacement."
---

# Amazon SES Mail Manager Code Examples

Standalone Python scripts demonstrating common Mail Manager workflows.
Each script is self-contained and runnable with `pip install boto3`.

| Example | What it shows |
|---------|---------------|
| [01-setup-pipeline](01-setup-pipeline/setup_pipeline.py) | Create archive + traffic policy + rule set + ingress point end-to-end |
| [02-route-by-recipient](02-route-by-recipient/route_by_recipient.py) | Rule set with multiple recipient-based routing rules; safe update pattern |
| [03-archive-and-search](03-archive-and-search/archive_search.py) | Async archive search, message content retrieval, S3 export |
| [04-address-list-import](04-address-list-import/address_list_import.py) | Create address list, add members, bulk CSV import via pre-signed URL |
| [05-update-rule-set](05-update-rule-set/update_failure_policy.py) | Safely update ActionFailurePolicy on existing rules (fetch-modify-replace pattern) |
| [06-smtp-relay-replacement](06-smtp-relay-replacement/smtp-relay-replacement.yaml) | CloudFormation: AUTH ingress point as SMTP relay replacement with Secrets Manager |
| [07-cdk-inbound-pipeline](07-cdk-inbound-pipeline/) | CDK (TypeScript): OPEN ingress point with archive + S3 + send to internet |

## Prerequisites

```bash
pip install boto3 requests
```

Configure AWS credentials (`aws configure`, environment variables, or IAM role) before running.

## Key Patterns Demonstrated

- Resource creation in dependency order (archive/policy/rule-set before ingress point)
- Polling for ingress point `ACTIVE` status before updating DNS — avoids bounced email
- Fetching current rules before calling `update_rule_set` (replace-all semantics)
- Setting `ActionFailurePolicy: CONTINUE` so one failed action doesn't drop the message
- Async search/export: start → poll → fetch
- Two-step address list import: create job → PUT to pre-signed URL → start job
