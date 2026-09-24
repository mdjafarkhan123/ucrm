---
description: "Build rule sets in Amazon SES Mail Manager. Define conditions and actions to archive, relay, bounce, drop, or invoke Lambda on inbound email."
---

# Rule Set Guide

Rule sets process the full email message after it has been received. Each rule set contains an ordered list of rules. Each rule has optional conditions and required actions. Rules are evaluated in order — when a rule's conditions match, its actions run.

## Prerequisites

- boto3 installed: `pip install boto3`
- AWS credentials configured: `aws configure`
- Amazon SES Mail Manager enabled in your account/region

## Key Facts

- Evaluated after the full message body is received (unlike traffic policies)
- Rules are evaluated in order; by default, processing stops after the first matching rule's actions complete
- Use `ActionFailurePolicy: CONTINUE` on actions to continue to the next rule on failure
- A rule with no conditions matches all messages
- Conditions within a rule are ANDed together
- Both conditions and actions are union types — each object must contain exactly ONE key
- `update_rule_set` replaces ALL rules — always fetch current rules before updating

## Create a Rule Set

```python
import boto3

client = boto3.client('mailmanager', region_name='us-east-1')

response = client.create_rule_set(
    RuleSetName='my-rule-set',
    Rules=[
        {
            'Name': 'rule-name',          # optional but recommended
            'Conditions': [...],           # optional — omit to match all
            'Unless': [...],               # optional — inverse conditions
            'Actions': [...]               # required — 1 to 10 actions
        }
    ]
)
rule_set_id = response['RuleSetId']
```

## Condition Types

Each condition object must contain exactly ONE key.

### StringExpression

```python
# Match recipient
{'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@internal.example.com']}}

# Match subject
{'StringExpression': {'Evaluate': {'Attribute': 'SUBJECT'}, 'Operator': 'CONTAINS', 'Values': ['URGENT', 'ACTION REQUIRED']}}

# Match sender
{'StringExpression': {'Evaluate': {'Attribute': 'FROM'}, 'Operator': 'ENDS_WITH', 'Values': ['@example.org']}}
```

Attributes: `RECIPIENT`, `SENDER`, `FROM`, `TO`, `CC`, `SUBJECT`, `MAIL_FROM`, `HELO`
Operators: `EQUALS`, `NOT_EQUALS`, `STARTS_WITH`, `ENDS_WITH`, `CONTAINS`

### IpExpression

```python
# Match source IP (note: SOURCE_IP in rule sets, not SENDER_IP)
{'IpExpression': {'Evaluate': {'Attribute': 'SOURCE_IP'}, 'Operator': 'CIDR_MATCHES', 'Values': ['10.0.0.0/8']}}
```

Attribute: `SOURCE_IP`
Operators: `CIDR_MATCHES`, `NOT_CIDR_MATCHES`

### BooleanExpression

```python
# Check TLS
{'BooleanExpression': {'Evaluate': {'Attribute': 'TLS'}, 'Operator': 'IS_TRUE'}}

# Check for read receipt request
{'BooleanExpression': {'Evaluate': {'Attribute': 'READ_RECEIPT_REQUESTED'}, 'Operator': 'IS_TRUE'}}
```

Attributes: `READ_RECEIPT_REQUESTED`, `TLS`, `TLS_WRAPPED`
Operators: `IS_TRUE`, `IS_FALSE`

### NumberExpression

**Note:** Uses singular `Value` (not `Values`).

```python
# Match large messages
{'NumberExpression': {'Evaluate': {'Attribute': 'MESSAGE_SIZE'}, 'Operator': 'GREATER_THAN', 'Value': 10485760}}
```

Attribute: `MESSAGE_SIZE` (bytes)
Operators: `LESS_THAN`, `GREATER_THAN`, `EQUALS`, `LESS_THAN_OR_EQUAL`, `GREATER_THAN_OR_EQUAL`, `NOT_EQUALS`

### VerdictExpression

```python
# Require SPF pass
{'VerdictExpression': {'Evaluate': {'Attribute': 'SPF'}, 'Operator': 'EQUALS', 'Values': ['PASS']}}

# Check DKIM
{'VerdictExpression': {'Evaluate': {'Attribute': 'DKIM'}, 'Operator': 'NOT_EQUALS', 'Values': ['PASS']}}
```

Attributes: `SPF`, `DKIM`
Operators: `EQUALS`, `NOT_EQUALS`
Values: `PASS`, `FAIL`, `GRAY`, `PROCESSING_FAILED`

### DmarcExpression

**Note:** No `Evaluate` field — DmarcExpression is unique in this regard.

```python
# Check DMARC policy
{'DmarcExpression': {'Operator': 'EQUALS', 'Values': ['REJECT']}}

# Exclude DMARC none (i.e., policy is set)
{'DmarcExpression': {'Operator': 'NOT_EQUALS', 'Values': ['NONE']}}
```

Operators: `EQUALS`, `NOT_EQUALS`
Values: `NONE`, `QUARANTINE`, `REJECT`

## Action Types

Each action object must contain exactly ONE key.

### Drop — silently discard

```python
{'Drop': {}}
```

### Bounce — return a bounce response to the sender

Generates a non-delivery report (NDR) back to the sender. Requires an IAM role with `ses:SendBounce` permission.

```python
{'Bounce': {
    'SmtpReplyCode': '550',              # RFC 5321 reply code (4xx or 5xx)
    'StatusCode': '5.1.1',               # Enhanced status code (x.y.z)
    'DiagnosticMessage': 'Mailbox not found',  # Included in Diagnostic-Code header
    'Sender': 'postmaster@example.com',  # Bounce message sender
    'RoleArn': 'arn:aws:iam::123456789012:role/MailManagerBounceRole',
    'Message': 'The recipient address is not valid.',  # optional human-readable text
    'ActionFailurePolicy': 'CONTINUE'    # optional — CONTINUE or DROP
}}
```

### Archive — store in Mail Manager archive

**Note:** Use the archive ID (such as `a-xxxxxxxxxxxx`), NOT the full ARN. The API enforces a 66-character limit on `TargetArchive`.

```python
{'Archive': {
    'TargetArchive': 'a-xxxxxxxxxxxx',  # archive ID, NOT ARN
    'ActionFailurePolicy': 'CONTINUE'  # or 'DROP'
}}
```

### Relay — forward via SMTP relay

```python
{'Relay': {
    'Relay': 'r-xxxx',                  # relay resource ID (not ARN)
    'ActionFailurePolicy': 'CONTINUE',
    'MailFrom': 'PRESERVE'              # or 'REPLACE'
}}
```

### WriteToS3 — write raw email to S3

Amazon S3 encrypts all new objects by default with server-side encryption (SSE-S3). For additional control, configure the bucket with an AWS KMS customer managed key.

```python
{'WriteToS3': {
    'S3Bucket': 'amzn-s3-demo-bucket-email',
    'RoleArn': 'arn:aws:iam::123456789012:role/MailManagerS3Role',
    'S3Prefix': 'inbound/',             # optional
    'ActionFailurePolicy': 'CONTINUE'
}}
```

The IAM role must have `s3:PutObject` on the bucket.

### DeliverToMailbox — deliver to Amazon WorkMail

```python
{'DeliverToMailbox': {
    'MailboxArn': 'arn:aws:workmail:us-east-1:123456789012:organization/m-xxxx',
    'RoleArn': 'arn:aws:iam::123456789012:role/MailManagerWorkMailRole',
    'ActionFailurePolicy': 'CONTINUE'
}}
```

### ReplaceRecipient — rewrite the To address

```python
{'ReplaceRecipient': {
    'ReplaceWith': ['catchall@example.com']
}}
```

### AddHeader — inject a header

```python
{'AddHeader': {
    'HeaderName': 'X-Mail-Manager-Processed',
    'HeaderValue': 'true'
}}
```

### Send — re-send via SES

```python
{'Send': {
    'RoleArn': 'arn:aws:iam::123456789012:role/MailManagerSendRole'
}}
```

### PublishToSns — publish to SNS topic

```python
{'PublishToSns': {
    'TopicArn': 'arn:aws:sns:us-east-1:123456789012:email-notifications',
    'RoleArn': 'arn:aws:iam::123456789012:role/MailManagerSNSRole'
}}
```

### InvokeLambda — invoke an AWS Lambda function

Invokes a Lambda function to process the email. The payload format matches [Amazon SES Email Receiving notification contents](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-notifications-contents.html). For code examples, see [Lambda function examples](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-action-lambda-example-use-cases.html).

```python
{'InvokeLambda': {
    'FunctionArn': 'arn:aws:lambda:us-east-1:123456789012:function/ProcessEmail',
    'InvocationType': 'EVENT',           # EVENT (async) or REQUEST_RESPONSE (sync)
    'RoleArn': 'arn:aws:iam::123456789012:role/MailManagerLambdaRole',
    'ActionFailurePolicy': 'CONTINUE',   # optional
    'RetryTimeMinutes': 30               # optional — 0 to 2160 (36 hours)
}}
```

The IAM role must have `lambda:InvokeFunction` on the target function. Use `REQUEST_RESPONSE` when the Lambda needs to control rule processing (return `STOP_RULE_SET` to halt). Use `EVENT` for fire-and-forget processing.

## Common Rule Patterns

### Archive everything, then relay to internal server

```python
Rules=[
    {
        'Name': 'archive-and-relay',
        'Actions': [
            {'Archive': {'TargetArchive': archive_id, 'ActionFailurePolicy': 'CONTINUE'}},
            {'Relay': {'Relay': relay_id, 'ActionFailurePolicy': 'CONTINUE', 'MailFrom': 'PRESERVE'}}
        ]
    }
]
```

### Drop spam, archive legitimate email

```python
Rules=[
    {
        'Name': 'drop-spf-fail',
        'Conditions': [
            {'VerdictExpression': {'Evaluate': {'Attribute': 'SPF'}, 'Operator': 'EQUALS', 'Values': ['FAIL']}}
        ],
        'Actions': [{'Drop': {}}]
    },
    {
        'Name': 'archive-rest',
        'Actions': [
            {'Archive': {'TargetArchive': archive_id, 'ActionFailurePolicy': 'CONTINUE'}}
        ]
    }
]
```

### Route by recipient domain

```python
Rules=[
    {
        'Name': 'route-sales',
        'Conditions': [
            {'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@sales.example.com']}}
        ],
        'Actions': [{'Relay': {'Relay': sales_relay_id, 'ActionFailurePolicy': 'CONTINUE', 'MailFrom': 'PRESERVE'}}]
    },
    {
        'Name': 'route-support',
        'Conditions': [
            {'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@support.example.com']}}
        ],
        'Actions': [{'Relay': {'Relay': support_relay_id, 'ActionFailurePolicy': 'CONTINUE', 'MailFrom': 'PRESERVE'}}]
    },
    {
        'Name': 'drop-unmatched',
        'Actions': [{'Drop': {}}]
    }
]
```

### Tag and archive large attachments separately

```python
Rules=[
    {
        'Name': 'large-message',
        'Conditions': [
            {'NumberExpression': {'Evaluate': {'Attribute': 'MESSAGE_SIZE'}, 'Operator': 'GREATER_THAN', 'Value': 10485760}}
        ],
        'Actions': [
            {'AddHeader': {'HeaderName': 'X-Large-Message', 'HeaderValue': 'true'}},
            {'Archive': {'TargetArchive': large_msg_archive_id, 'ActionFailurePolicy': 'CONTINUE'}}
        ]
    },
    {
        'Name': 'normal-messages',
        'Actions': [
            {'Archive': {'TargetArchive': standard_archive_id, 'ActionFailurePolicy': 'CONTINUE'}}
        ]
    }
]
```

## Update a Rule Set

**Warning:** `update_rule_set` replaces ALL rules. Always fetch current rules first.

```python
# Fetch current rules
current = client.get_rule_set(RuleSetId=rule_set_id)
existing_rules = current['Rules']

# Prepend a new rule (evaluated first)
new_rule = {
    'Name': 'block-known-bad-sender',
    'Conditions': [
        {'StringExpression': {'Evaluate': {'Attribute': 'FROM'}, 'Operator': 'ENDS_WITH', 'Values': ['@example.net']}}
    ],
    'Actions': [{'Drop': {}}]
}

client.update_rule_set(
    RuleSetId=rule_set_id,
    Rules=[new_rule] + existing_rules
)
```

## List and Get

```python
# List all rule sets
rule_sets = client.list_rule_sets()
for rs in rule_sets['RuleSets']:
    print(rs['RuleSetId'], rs['RuleSetName'])

# Get details including all rules
rule_set = client.get_rule_set(RuleSetId=rule_set_id)
for rule in rule_set['Rules']:
    print(rule.get('Name'), len(rule.get('Actions', [])), 'actions')
```

## Delete

```python
# Note: remove the rule set from any ingress points before deleting.
# Deleting a rule set that is attached to an active ingress point returns a ConflictException.
client.delete_rule_set(RuleSetId=rule_set_id)
```

To delete all Mail Manager resources in the correct order, see the [Cleanup Guide](../cleanup/cleanup-guide.md).
