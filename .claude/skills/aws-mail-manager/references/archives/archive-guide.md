---
description: "Manage email archives in Amazon SES Mail Manager. Create archives, search stored email, export to S3, and configure retention policies."
---

# Amazon SES Mail Manager Archive Guide

Mail Manager archives provide durable, searchable email storage. Use them for compliance, legal hold, eDiscovery, or retaining a copy of all inbound email.

## Prerequisites

- boto3 installed: `pip install boto3`
- AWS credentials configured: `aws configure`
- Amazon SES Mail Manager enabled in your account/region

## Key Facts

- Archives are standalone resources — no dependencies on other Mail Manager resources
- Email is stored in the archive when a rule set action targets it
- `TargetArchive` in rule actions requires the short archive ID (`a-xxxx`), not the full ARN — API enforces 66-char limit
- Search and export are async operations — start a job, poll for completion, fetch results
- Deletion is async — `delete_archive` sets state to `PENDING_DELETION`, not immediate removal
- Archive names persist through `PENDING_DELETION` — reusing a name before deletion completes will fail
- Archives can be encrypted with a customer-managed KMS key

## CloudFormation Warning

In CloudFormation, `!GetAtt MyArchive.ArchiveId` returns the full ARN (known CloudFormation behavior), not the short ID. Extract the ID:

```yaml
# Extract "a-xxxx" from "arn:aws:ses:...:mailmanager-archive/a-xxxx"
TargetArchive: !Select
  - 1
  - !Split
    - "/"
    - !GetAtt MyArchive.ArchiveArn
```

Also use unique archive names to avoid collisions after stack rollbacks:

```yaml
ArchiveName: !Sub "${AWS::StackName}-archive-${AWS::AccountId}"
```

## Create an Archive

```python
import boto3

client = boto3.client('mailmanager', region_name='us-east-1')

archive = client.create_archive(
    ArchiveName='compliance-archive',
    Retention={'RetentionPeriod': 'SEVEN_YEARS'},
    # Optional: encrypt with a customer-managed AWS KMS key for additional control.
    # Archives use AWS managed encryption by default.
    # KmsKeyArn='arn:aws:kms:us-east-1:123456789012:key/...'
)
archive_id = archive['ArchiveId']
print(f"Archive ID: {archive_id}")
```

Retention options: `THREE_MONTHS`, `SIX_MONTHS`, `NINE_MONTHS`, `ONE_YEAR`, `EIGHTEEN_MONTHS`, `TWO_YEARS`, `THIRTY_MONTHS`, `THREE_YEARS`, `FOUR_YEARS`, `FIVE_YEARS`, `SIX_YEARS`, `SEVEN_YEARS`, `EIGHT_YEARS`, `NINE_YEARS`, `TEN_YEARS`, `PERMANENT`

**Cost note:** Archives incur storage charges based on email volume and retention period. Longer retention periods accumulate more stored email. Delete archives when no longer needed to stop charges.

## Use Archive as a Rule Set Action

Reference the archive ID (not ARN) in a rule set action. The API enforces a 66-character limit on `TargetArchive`.

```python
# Use archive_id directly, not the full ARN
client.create_rule_set(
    RuleSetName='archive-all',
    Rules=[
        {
            'Name': 'store-everything',
            'Actions': [
                {
                    'Archive': {
                        'TargetArchive': archive_id,  # such as 'a-xxxxxxxxxxxx'
                        'ActionFailurePolicy': 'CONTINUE'
                    }
                }
            ]
        }
    ]
)
```

## Search an Archive

Search is async. The pattern is: start → poll → fetch results.

```python
import time

# 1. Start the search
response = client.start_archive_search(
    ArchiveId=archive_id,
    FromTimestamp=1700000000,   # epoch seconds — start of date range
    ToTimestamp=1700086400,     # epoch seconds — end of date range
    MaxResults=100,             # 1-1000
    Filters={
        'Include': [
            {
                'StringExpression': {
                    'Evaluate': {'Attribute': 'FROM'},
                    'Operator': 'CONTAINS',
                    'Values': ['@example.com']
                }
            }
        ],
        'Unless': [
            {
                'BooleanExpression': {
                    'Evaluate': {'Attribute': 'HAS_ATTACHMENTS'},
                    'Operator': 'IS_FALSE'
                }
            }
        ]
    }
)
search_id = response['SearchId']

# 2. Poll until complete
while True:
    status = client.get_archive_search(SearchId=search_id)
    if status['Status']['CompletionTimestamp']:
        print(f"Search complete. State: {status['Status']['State']}")
        break
    print("Searching...")
    time.sleep(2)

# 3. Fetch results
results = client.get_archive_search_results(SearchId=search_id)
for msg in results['Rows']:
    print(
        msg['ArchivedMessageId'],
        msg['Envelope']['From'],
        msg['Envelope']['To'],
        msg['ReceivedTimestamp']
    )
```

### Search Filter Reference

Filters have `Include` and `Unless` arrays. Each condition is a union — use exactly ONE key:

**StringExpression** — search by header fields:
```python
{'StringExpression': {'Evaluate': {'Attribute': 'FROM'}, 'Operator': 'CONTAINS', 'Values': ['@example.com']}}
```
Attributes: `TO`, `FROM`, `CC`, `SUBJECT`, `ENVELOPE_TO`, `ENVELOPE_FROM`
Operator: always `CONTAINS`

**BooleanExpression** — filter by attachment presence:
```python
{'BooleanExpression': {'Evaluate': {'Attribute': 'HAS_ATTACHMENTS'}, 'Operator': 'IS_TRUE'}}
```

### Convert dates to epoch seconds

```python
from datetime import datetime, timezone

start = datetime(2024, 1, 1, tzinfo=timezone.utc)
end = datetime(2024, 1, 31, 23, 59, 59, tzinfo=timezone.utc)

from_ts = int(start.timestamp())
to_ts = int(end.timestamp())
```

## Access a Specific Message

```python
# Get a pre-signed download URL (valid for a limited time)
url_response = client.get_archive_message(ArchivedMessageId=archived_message_id)
download_url = url_response['MessageDownloadLink']

# Get the text content of a message (no attachments)
content = client.get_archive_message_content(ArchivedMessageId=archived_message_id)
print(content['Body']['Text'])
```

## Export an Archive

Export emails to S3 for bulk processing or long-term storage outside Mail Manager.

```python
# 1. Start export
export = client.start_archive_export(
    ArchiveId=archive_id,
    FromTimestamp=1700000000,
    ToTimestamp=1700086400,
    ExportDestinationConfiguration={
        'S3': {'S3Location': 's3://amzn-s3-demo-bucket-export/exports/'}
    },
    IncludeMetadata=True,   # include JSON metadata files alongside EML files
    MaxResults=10000
)
export_id = export['ExportId']

# 2. Poll until complete
while True:
    status = client.get_archive_export(ExportId=export_id)
    if status['Status']['CompletionTimestamp']:
        print("Export complete")
        break
    time.sleep(10)
```

The IAM role used by Mail Manager needs `s3:PutObject` on the destination bucket.

## Update Archive Retention

```python
client.update_archive(
    ArchiveId=archive_id,
    Retention={'RetentionPeriod': 'TEN_YEARS'}
)
```

## List and Get

```python
# List all archives
archives = client.list_archives()
for a in archives['Archives']:
    print(a['ArchiveId'], a['ArchiveName'], a['ArchiveState'])

# Get details
archive = client.get_archive(ArchiveId=archive_id)
print(archive['Retention'])
print(archive['ArchiveState'])  # ACTIVE or PENDING_DELETION
```

## Delete

**Warning:** Deleting an archive permanently removes all stored emails after the deletion completes. Export any needed emails before deleting. See [Export an Archive](#export-an-archive).

```python
# Sets state to PENDING_DELETION — not immediate
client.delete_archive(ArchiveId=archive_id)

# Verify deletion is in progress
response = client.get_archive(ArchiveId=archive_id)
print(response["ArchiveState"])  # PENDING_DELETION
```

## Cleanup

To stop incurring storage charges, delete archives that are no longer needed. Before deleting:

1. Export any emails you need to retain — see [Export an Archive](#export-an-archive)
2. Remove the archive from any rule set actions that reference it
3. Delete the archive (enters `PENDING_DELETION` state)

**Warning:** Deleting an archive permanently removes all stored emails after the deletion completes. Archive names remain claimed during `PENDING_DELETION` (up to 30 days).

```python
# Export first if needed, then delete
client.delete_archive(ArchiveId=archive_id)
```

## Summary

Archives provide durable, searchable email storage for compliance and operational needs. Key points to remember: use the short archive ID (not ARN) in rule actions, search and export are async operations, and deletion is also async with names persisting through `PENDING_DELETION`. For the full cleanup procedure, refer to the [Cleanup Guide](../cleanup/cleanup-guide.md).
