---
description: "Build event-driven AI email processing pipelines with Amazon SES Mail Manager. Route inbound email to S3, Lambda, and Amazon Bedrock for categorization."
---

# Event-Driven AI Processing Pipeline

Mail Manager can serve as the front-end for email-driven AI processing workflows. Inbound email arrives at the ingress point, passes through traffic policy filtering, and rule set actions route it to downstream services (S3, SNS, Lambda) where AI models analyze, categorize, or respond to the content.

## Prerequisites

- AWS account with Amazon SES Mail Manager enabled
- boto3 installed: `pip install boto3`
- AWS credentials configured with permissions for Mail Manager, Amazon S3, and AWS Lambda
- An Amazon Bedrock model enabled in your account (for AI processing)

## Architecture Pattern

```
Internet → Ingress Point → Traffic Policy → Rule Set
                                              ├── WriteToS3 (store raw email)
                                              ├── Archive (compliance copy)
                                              └── PublishToSns or S3 Event
                                                    ↓
                                              Lambda Function
                                                    ↓
                                              AI/ML Processing
                                              (Bedrock, Comprehend, etc.)
                                                    ↓
                                              Action (SNS, SQS, DynamoDB,
                                              Connect, etc.)
```

## How It Works

1. Mail Manager receives inbound email via an OPEN ingress point
2. Traffic policy filters connections (TLS, IP, recipient, add-on scanning)
3. Rule set actions run in order:
   - **WriteToS3** stores the raw MIME email in an S3 bucket
   - **Archive** keeps a compliance copy in Mail Manager's searchable archive
   - Optionally, **PublishToSns** sends a notification to trigger processing
4. An S3 event notification (or Amazon SNS subscription) triggers an AWS Lambda function
5. The AWS Lambda function parses the email and sends it to an AI model (such as Amazon Bedrock) for categorization, urgency assignment, or response generation
6. Results are routed to downstream systems (Amazon SNS topics per category, Amazon SQS queues, Amazon DynamoDB, Amazon Connect for outbound calls)

## Reference Implementation

The [Generative AI Email Categorization using SES Mail Manager](https://github.com/aws-samples/sample-gen-ai-email-categorization-using-ses-mail-manager) project on GitHub demonstrates this pattern end-to-end. It deploys:

- S3 bucket for inbound email storage
- S3 Lambda notification trigger on new objects
- Lambda function that parses MIME emails and calls Amazon Bedrock (Nova Micro) for categorization and urgency assignment
- Mail Manager traffic policy, rule set, and ingress point configured to write to S3
- SNS topics and SQS queues per category (such as tech support, billing, content)
- DynamoDB table for storing categorization results
- Third-party add-on integration for virus/spam scanning

The project is CDK-based (TypeScript) and deploys the full stack with:

```bash
cdk deploy \
  --parameters allowListedEmailAddress="support@example.com" \
  --parameters securityAddonARN="arn:aws:ses:us-east-1:123456789012:addon-instance/ai-xxxx"
```

## Key Configuration Decisions

### S3 trigger vs SNS trigger vs InvokeLambda

| Approach | Pros | Cons |
|----------|------|------|
| **S3 event → Lambda** | Email content is already in S3 for Lambda to read | One trigger per object, harder to fan out |
| **SNS → Lambda** | Can fan out to multiple subscribers, decoupled | Lambda receives notification metadata, must fetch email from S3 or archive separately |
| **InvokeLambda action** | Direct invocation from the rule set, no intermediate service. Supports sync (`REQUEST_RESPONSE`) and async (`EVENT`) modes with configurable retry (up to 36 hours) | Lambda payload uses SES Email Receiving format, not raw MIME |

The reference implementation uses S3 event notifications. For new pipelines, consider the `InvokeLambda` action for a more direct architecture — it invokes the Lambda directly from the rule set without needing an S3 bucket or SNS topic as an intermediary.

### Rule set action order

For AI processing pipelines, the recommended action order is:

1. **Archive** first — this helps create a compliance copy even if downstream processing fails
2. **WriteToS3** second — triggers the processing pipeline
3. **AddHeader** (optional) — tag the message for downstream routing

Set `ActionFailurePolicy: CONTINUE` on Archive so that S3 delivery proceeds even if archiving has a transient failure.

### Add-on scanning

Consider using a Mail Manager add-on (third-party security scanning service) as a traffic policy condition to drop malicious email before it reaches your AI pipeline. This prevents wasting compute on spam/malware and reduces the risk of prompt injection via email content.

### Cost considerations

This pattern incurs charges for:
- Mail Manager ingress point (per-message processing)
- Archive storage (based on email volume and retention period)
- S3 storage (raw email objects)
- Lambda invocations and duration
- Amazon Bedrock model inference calls

Delete resources when no longer needed. See [Cleanup](#cleanup).

## Mail Manager Configuration for This Pattern

```python
import boto3

client = boto3.client('mailmanager', region_name='us-east-1')

# Rule set: archive + write to S3 (triggers Lambda via S3 event)
rule_set = client.create_rule_set(
    RuleSetName='ai-email-pipeline',
    Rules=[
        {
            'Name': 'archive-and-process',
            'Actions': [
                {
                    'Archive': {
                        'TargetArchive': archive_id,
                        'ActionFailurePolicy': 'CONTINUE'
                    }
                },
                {
                    'WriteToS3': {
                        'S3Bucket': 'amzn-s3-demo-bucket-processing',
                        'RoleArn': s3_write_role_arn,
                        'S3Prefix': 'inbound/',
                        'ActionFailurePolicy': 'CONTINUE'
                    }
                }
            ]
        }
    ]
)
```

The Lambda function, Bedrock integration, and downstream routing are outside Mail Manager's scope — see the [reference implementation](https://github.com/aws-samples/sample-gen-ai-email-categorization-using-ses-mail-manager) for the complete solution.

## Cleanup

To tear down the Mail Manager components of this pipeline:

1. Delete the ingress point (stops email processing)
2. Delete the rule set
3. Delete the traffic policy
4. Delete the archive (async — enters `PENDING_DELETION`). **Warning:** this permanently removes all stored emails. Export any needed messages first.
5. Empty and delete the S3 bucket. **Warning:** this permanently removes all stored email objects.

For the full teardown procedure, see the [Cleanup Guide](../cleanup/cleanup-guide.md). The Lambda function, SNS topics, and other downstream resources are managed separately (or via `cdk destroy` if using the reference implementation).

## Related

- [Rule Set Guide](../rule-sets/rule-set-guide.md) — full action and condition reference
- [Archive Guide](../archives/archive-guide.md) — search and export for compliance
- [Getting Started Guide](../setup/getting-started.md) — basic pipeline setup
- [CDK Inbound Pipeline Example](../../examples/07-cdk-inbound-pipeline/) — CDK stack with archive + S3 + send actions
