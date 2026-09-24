---
description: "Manage email allow and deny lists in Amazon SES Mail Manager. Create address lists, bulk import via CSV/JSON, and use in rule set conditions."
---

# Amazon SES Mail Manager Address List Guide

Address lists are managed collections of email addresses or domains used in rule set conditions for allow/block list matching. They support individual address management and bulk import via CSV or JSON.

> **Note:** The email addresses and domains in this guide (such as `spammer@example.com`, `@example.net`) are fictitious examples for illustration purposes only.

## Prerequisites

- boto3 installed: `pip install boto3`
- For bulk import: `pip install requests`
- AWS credentials configured: `aws configure`
- Amazon SES Mail Manager enabled in your account/region

## Key Facts

- Address lists are standalone resources — no dependencies on other Mail Manager resources
- Used in rule set conditions via `BooleanExpression` with `IsInAddressList` — checks if a message attribute (SENDER, RECIPIENT, etc.) matches any entry in the list
- Bulk import requires a two-step process: create job (get pre-signed URL) → upload data → start job
- Import jobs are async — poll `get_address_list_import_job` for completion

## Create an Address List

```python
import boto3

client = boto3.client('mailmanager', region_name='us-east-1')

response = client.create_address_list(
    AddressListName='blocked-senders'
)
address_list_id = response['AddressListId']
print(f"Address List ID: {address_list_id}")
```

## Add Individual Addresses

```python
# Add a single address
client.register_member_to_address_list(
    AddressListId=address_list_id,
    Address='spammer@example.com'
)

# Add a domain (matches any address at that domain)
client.register_member_to_address_list(
    AddressListId=address_list_id,
    Address='@example.net'
)
```

## Remove an Address

```python
client.deregister_member_from_address_list(
    AddressListId=address_list_id,
    Address='spammer@example.com'
)
```

## List Members

```python
# List all members
members = client.list_members_of_address_list(AddressListId=address_list_id)
for m in members['Members']:
    print(m['Address'], m['CreatedTimestamp'])

# Filter by prefix
filtered = client.list_members_of_address_list(
    AddressListId=address_list_id,
    Filter={'AddressFilter': {'AddressPrefix': '@example'}}
)
```

## Check if an Address is a Member

```python
try:
    member = client.get_member_of_address_list(
        AddressListId=address_list_id,
        Address='spammer@example.com'
    )
    print("Address is in the list:", member['Address'])
except client.exceptions.ResourceNotFoundException:
    print("Address not in list")
```

## Bulk Import

Import large address lists via CSV or JSON. The process is: create job → upload to pre-signed URL → start job → poll for completion.

### CSV format

One address per line:
```
spammer@example.com
@example.net
phishing@example.org
```

### JSON format

```json
["spammer@example.com", "@example.net", "phishing@example.org"]
```

### Import workflow

```python
import requests  # pip install requests

# 1. Create the import job — get a pre-signed upload URL
job = client.create_address_list_import_job(
    AddressListId=address_list_id,
    Name='bulk-deny-list-import-2024-01',
    ImportDataFormat={'ImportDataType': 'CSV'}  # or 'JSON'
)
job_id = job['JobId']
presigned_url = job['PreSignedUrl']

# 2. Upload your data to the pre-signed URL
with open('deny-list.csv', 'rb') as f:
    upload_response = requests.put(presigned_url, data=f)
    upload_response.raise_for_status()

# 3. Start the import job
client.start_address_list_import_job(JobId=job_id)

# 4. Poll until complete
import time
while True:
    status = client.get_address_list_import_job(JobId=job_id)
    state = status['Status']
    print(f"Import status: {state}")
    if state in ('COMPLETED', 'FAILED', 'STOPPED'):
        break
    time.sleep(5)

if state == 'COMPLETED':
    print(f"Imported {status['ImportedItemsCount']} addresses")
else:
    print(f"Import failed: {status.get('FailureInfo')}")
```

## List Import Jobs

```python
jobs = client.list_address_list_import_jobs(AddressListId=address_list_id)
for job in jobs['ImportJobs']:
    print(job['JobId'], job['Status'], job.get('ImportedItemsCount'))
```

## Stop an In-Progress Import

```python
client.stop_address_list_import_job(JobId=job_id)
```

## Using Address Lists in Rule Conditions

Address lists are checked using `BooleanExpression` with `IsInAddressList`. This evaluates whether an email attribute (sender, recipient, etc.) matches any entry in the address list:

```python
# In a rule set condition — check if SENDER is in a specific address list
{
    'BooleanExpression': {
        'Evaluate': {
            'IsInAddressList': {
                'AddressLists': [address_list_id],  # exactly one address list
                'Attribute': 'SENDER'  # RECIPIENT, MAIL_FROM, SENDER, FROM, TO, or CC
            }
        },
        'Operator': 'IS_TRUE'  # or IS_FALSE to negate
    }
}
```

A practical pattern — block senders on your deny list:

```python
client.create_rule_set(
    RuleSetName='deny-list-enforcement',
    Rules=[
        {
            'Name': 'blocked-senders',
            'Conditions': [
                {
                    'BooleanExpression': {
                        'Evaluate': {
                            'IsInAddressList': {
                                'AddressLists': [blocked_senders_list_id],
                                'Attribute': 'SENDER'
                            }
                        },
                        'Operator': 'IS_TRUE'
                    }
                }
            ],
            'Actions': [{'Drop': {}}]
        }
    ]
)
```

## List and Get

```python
# List all address lists
lists = client.list_address_lists()
for al in lists['AddressLists']:
    print(al['AddressListId'], al['AddressListName'])

# Get details
address_list = client.get_address_list(AddressListId=address_list_id)
print(address_list['AddressListName'])
print(address_list['CreatedTimestamp'])
```

## Delete

Before deleting an address list, remove it from any rule set conditions and traffic policy statements that reference it. Deleting an address list that is still referenced will cause those conditions to fail.

```python
# Note: remove the address list from any rule conditions before deleting
client.delete_address_list(AddressListId=address_list_id)
```
