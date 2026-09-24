---
description: "Configure traffic policies in Amazon SES Mail Manager. Filter SMTP connections by sender IP, recipient, TLS version, and address list membership."
---

# Traffic Policy Guide

Traffic policies are connection-level filters evaluated **before** the message body is received. They control which SMTP connections are allowed or denied based on sender IP, recipient address, or TLS version.

## Prerequisites

- boto3 installed: `pip install boto3`
- AWS credentials configured: `aws configure`
- Amazon SES Mail Manager enabled in your account/region

## Key Facts

- Evaluated at SMTP connection time — before DATA phase
- Each policy has a `DefaultAction` (`ALLOW` or `DENY`) applied when no statement matches
- Statements are evaluated in order; first match wins
- Conditions within a statement are ANDed together
- Condition objects are union types — each must contain exactly ONE key

## Create a Traffic Policy

```python
import boto3

client = boto3.client('mailmanager', region_name='us-east-1')

response = client.create_traffic_policy(
    TrafficPolicyName='my-policy',
    DefaultAction='DENY',
    PolicyStatements=[
        {
            'Action': 'ALLOW',
            'Conditions': [
                # condition union objects go here
            ]
        }
    ]
)
policy_id = response['TrafficPolicyId']
```

## Condition Types

Each condition object must contain exactly ONE of these keys:

### StringExpression — filter by recipient

Only `RECIPIENT` is supported as the attribute in traffic policies.

```python
# Allow a specific domain
{'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@example.com']}}

# Allow a specific address
{'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'EQUALS', 'Values': ['admin@example.com']}}

# Block addresses containing a pattern
{'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'CONTAINS', 'Values': ['noreply']}}
```

Operators: `EQUALS`, `NOT_EQUALS`, `STARTS_WITH`, `ENDS_WITH`, `CONTAINS`

### IpExpression — filter by sender IP

```python
# Block a specific IP range
{'IpExpression': {'Evaluate': {'Attribute': 'SENDER_IP'}, 'Operator': 'CIDR_MATCHES', 'Values': ['192.0.2.0/24']}}

# Allow only known IP ranges
{'IpExpression': {'Evaluate': {'Attribute': 'SENDER_IP'}, 'Operator': 'CIDR_MATCHES', 'Values': ['10.0.0.0/8', '172.16.0.0/12']}}
```

Operators: `CIDR_MATCHES`, `NOT_CIDR_MATCHES`

### Ipv6Expression — filter by sender IPv6 address

```python
# Block an IPv6 range
{'Ipv6Expression': {'Evaluate': {'Attribute': 'SENDER_IPV6'}, 'Operator': 'CIDR_MATCHES', 'Values': ['2001:db8::/32']}}

# Allow only known IPv6 ranges
{'Ipv6Expression': {'Evaluate': {'Attribute': 'SENDER_IPV6'}, 'Operator': 'NOT_CIDR_MATCHES', 'Values': ['2001:db8:abcd::/48']}}
```

Attribute: `SENDER_IPV6`
Operators: `CIDR_MATCHES`, `NOT_CIDR_MATCHES`

### TlsExpression — enforce TLS requirements

**Important:** TlsExpression uses singular `Value` (not `Values`).

```python
# Require TLS 1.2 or higher
{'TlsExpression': {'Evaluate': {'Attribute': 'TLS_PROTOCOL'}, 'Operator': 'MINIMUM_TLS_VERSION', 'Value': 'TLS1_2'}}

# Require exactly TLS 1.3
{'TlsExpression': {'Evaluate': {'Attribute': 'TLS_PROTOCOL'}, 'Operator': 'IS', 'Value': 'TLS1_3'}}
```

Operators: `MINIMUM_TLS_VERSION`, `IS`
Values: `TLS1_2`, `TLS1_3`

### BooleanExpression — filter by add-on analysis or address list membership

Used with third-party add-ons (spam filters, threat analyzers) or address lists:

```python
# Block if add-on marks as spam
{'BooleanExpression': {'Evaluate': {'Analysis': {'Analyzer': 'arn:aws:mailmanager:...:addon-instance/ai-xxxx', 'ResultField': 'spam'}}, 'Operator': 'IS_TRUE'}}

# Block senders on a deny list (native address list integration)
{'BooleanExpression': {'Evaluate': {'IsInAddressList': {'Attribute': 'SENDER', 'AddressLists': ['al-xxxxxxxxxxxx']}}, 'Operator': 'IS_TRUE'}}

# Allow only recipients on an allow list
{'BooleanExpression': {'Evaluate': {'IsInAddressList': {'Attribute': 'RECIPIENT', 'AddressLists': ['al-xxxxxxxxxxxx']}}, 'Operator': 'IS_TRUE'}}
```

`IsInAddressList` attributes: `SENDER`, `RECIPIENT`
`Analysis` requires an add-on instance ARN and result field name.

## Common Policy Patterns

### Allow only your domain, deny everything else

```python
client.create_traffic_policy(
    TrafficPolicyName='domain-only',
    DefaultAction='DENY',
    PolicyStatements=[
        {
            'Action': 'ALLOW',
            'Conditions': [
                {'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@example.com']}}
            ]
        }
    ]
)
```

### Block known bad IP ranges

```python
client.create_traffic_policy(
    TrafficPolicyName='block-bad-ips',
    DefaultAction='ALLOW',
    PolicyStatements=[
        {
            'Action': 'DENY',
            'Conditions': [
                {'IpExpression': {'Evaluate': {'Attribute': 'SENDER_IP'}, 'Operator': 'CIDR_MATCHES', 'Values': ['192.0.2.0/24', '198.51.100.0/24']}}
            ]
        }
    ]
)
```

### Require TLS and restrict to your domain

Multiple conditions in a statement are ANDed:

```python
client.create_traffic_policy(
    TrafficPolicyName='tls-required-domain-only',
    DefaultAction='DENY',
    PolicyStatements=[
        {
            'Action': 'ALLOW',
            'Conditions': [
                {'StringExpression': {'Evaluate': {'Attribute': 'RECIPIENT'}, 'Operator': 'ENDS_WITH', 'Values': ['@example.com']}},
                {'TlsExpression': {'Evaluate': {'Attribute': 'TLS_PROTOCOL'}, 'Operator': 'MINIMUM_TLS_VERSION', 'Value': 'TLS1_2'}}
            ]
        }
    ]
)
```

### Set a maximum message size

```python
client.create_traffic_policy(
    TrafficPolicyName='size-limited',
    DefaultAction='ALLOW',
    MaxMessageSizeBytes=10485760,  # 10 MB
    PolicyStatements=[]
)
```

## Update a Traffic Policy

**Warning:** `update_traffic_policy` replaces ALL policy statements. Always fetch the current policy first.

```python
# Fetch current state
current = client.get_traffic_policy(TrafficPolicyId=policy_id)

# Add a new statement to existing ones
new_statements = current['PolicyStatements'] + [
    {
        'Action': 'DENY',
        'Conditions': [
            {'IpExpression': {'Evaluate': {'Attribute': 'SENDER_IP'}, 'Operator': 'CIDR_MATCHES', 'Values': ['203.0.113.0/24']}}
        ]
    }
]

client.update_traffic_policy(
    TrafficPolicyId=policy_id,
    PolicyStatements=new_statements
)
```

## List and Get

```python
# List all policies
policies = client.list_traffic_policies()
for p in policies['TrafficPolicies']:
    print(p['TrafficPolicyId'], p['TrafficPolicyName'])

# Get details
policy = client.get_traffic_policy(TrafficPolicyId=policy_id)
print(policy['DefaultAction'])
print(policy['PolicyStatements'])
```

## Delete

Before deleting a traffic policy, remove it from any ingress points that reference it. Deleting a traffic policy that is attached to an active ingress point will fail.

**Cost note:** Traffic policies do not incur charges on their own, but the ingress points they are attached to incur per-message processing charges. Delete unused ingress points to stop charges.

```python
# Note: cannot delete a policy that is attached to an active ingress point
client.delete_traffic_policy(TrafficPolicyId=policy_id)
```
