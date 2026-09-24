---
description: "Troubleshoot common Amazon SES Mail Manager issues. Resolve ingress point provisioning, traffic policy blocks, rule set matching, TLS policy, and mTLS problems."
---

# Troubleshooting Guide

Common issues when working with Mail Manager and how to resolve them.

## Ingress Point Issues

### Ingress point stuck in PROVISIONING

The ingress point typically takes 2-5 minutes to provision. If it stays in PROVISIONING for more than 10 minutes:

1. Check the ingress point status:
```python
response = client.get_ingress_point(IngressPointId='inp-xxxx')
print(response['Status'])
```

2. If status is `FAILED`, the provisioning failed. Delete and recreate:
```python
client.delete_ingress_point(IngressPointId='inp-xxxx')
# Wait for deletion, then recreate
```

3. Common causes of provisioning failure:
   - Invalid traffic policy or rule set ID
   - Service quota reached (check Service Quotas console)
   - For AUTH type: invalid password format or inaccessible Secrets Manager secret

### Ingress point shows ACTIVE but email isn't arriving

1. Verify your MX record points to the ingress point's A Record:
```bash
dig MX yourdomain.com
```

2. Confirm the A Record value matches:
```python
response = client.get_ingress_point(IngressPointId='inp-xxxx')
print(f"A Record: {response['ARecord']}")
```

3. DNS propagation can take up to 48 hours. Check with multiple DNS resolvers:
```bash
dig MX yourdomain.com @8.8.8.8
dig MX yourdomain.com @1.1.1.1
```

4. For AUTH endpoints, verify the sender is using correct credentials:
   - Username = ingress point ID (such as `inp-xxxxxxxxxxxx`)
   - Password = the password set during creation
   - Port 587 with STARTTLS (not port 465 with implicit TLS)

### SMTP connection refused or timeout

- Open endpoints: only port 25
- Authenticated endpoints: ports 25 and 587
- STARTTLS is required on all connections unless `TlsPolicy: OPTIONAL` is set on the ingress point
- Check that the sender's IP is not blocked by your traffic policy
- For VPC endpoints: verify the VPC endpoint is active and security groups allow inbound on the correct port

### TLS policy mismatch

If clients fail to connect with TLS errors:

1. Check the ingress point's TLS policy:
```python
response = client.get_ingress_point(IngressPointId='inp-xxxx')
print(f"TLS Policy: {response.get('IngressPointTlsPolicy', 'not set')}")
```

2. If `TlsPolicy` is `REQUIRED` or `FIPS`, the client must support STARTTLS. Plaintext connections are rejected.
3. If `TlsPolicy` is `FIPS`, the client must use FIPS-validated cryptographic modules.
4. `FIPS` cannot be changed after creation — to switch, delete and recreate the ingress point.
5. For private ingress points, the TLS policy must match the VPC endpoint service type (FIPS endpoint requires FIPS TLS policy).

### mTLS client certificate rejected

1. Verify the client certificate is signed by a CA in the ingress point's trust store
2. Check that the client certificate has not expired
3. Check that the client certificate is not on the CRL (certificate revocation list) if one was provided
4. If the CRL has expired, the associated CA certificate is also removed from the trust store — provide an updated CRL
5. mTLS is only available for public ingress endpoints — VPC endpoints do not support mTLS

## Traffic Policy Issues

### Traffic policy blocks all connections

1. Check the `DefaultAction`:
```python
policy = client.get_traffic_policy(TrafficPolicyId='tp-xxxx')
print(f"Default: {policy['DefaultAction']}")
for stmt in policy['PolicyStatements']:
    print(f"  {stmt['Action']}: {stmt['Conditions']}")
```

2. Common mistake: `DefaultAction: DENY` with no ALLOW statements, or ALLOW statements with conditions that don't match any traffic.

3. `MINIMUM_TLS_VERSION` matches connections AT or ABOVE the version. If you use it in a DENY statement, you're denying good connections. Use it in an ALLOW statement with `DefaultAction: DENY`.

### Policy changes not taking effect

Traffic policy updates take effect immediately for new connections but do not affect connections already in progress.

## Rule Set Issues

### Rules not matching as expected

1. Rules are evaluated in order — first match wins. Check rule ordering:
```python
rule_set = client.get_rule_set(RuleSetId='rs-xxxx')
for i, rule in enumerate(rule_set['Rules']):
    print(f"Rule {i}: {rule.get('Name', '(unnamed)')}")
    print(f"  Conditions: {rule.get('Conditions', 'none (matches all)')}")
```

2. A rule with no conditions matches ALL messages. If this rule appears before more specific rules, the specific rules never execute.

3. Conditions within a rule are ANDed. All conditions must match for the rule to fire.

### Update deleted my rules

`update_rule_set` replaces ALL rules. Always fetch current rules first:
```python
current = client.get_rule_set(RuleSetId='rs-xxxx')
existing_rules = current['Rules']
# Modify existing_rules, then:
client.update_rule_set(RuleSetId='rs-xxxx', Rules=existing_rules)
```

### Send to internet action fails silently

1. Check the IAM role has `ses:SendRawEmail` permission
2. In Amazon SES sandbox mode, both sender AND recipient must be verified identities
3. Check Amazon SES sending quotas — you may be throttled
4. If `ActionFailurePolicy` is `DROP` (the default), the message is silently discarded on failure. Set to `CONTINUE` to let subsequent actions run.

## Archive Issues

### Archive search returns no results

1. Verify the time range covers when the email was received (epoch seconds):
```python
from datetime import datetime, timezone
print(int(datetime(2024, 1, 1, tzinfo=timezone.utc).timestamp()))
```

2. Archive search filters only support `CONTAINS` operator — exact match won't work
3. Search is async — make sure you're polling until `CompletionTimestamp` is set before fetching results

### Archive name collision on creation

Archive names persist through `PENDING_DELETION` (up to 30 days). If a previous archive with the same name was deleted, you must use a different name or wait for deletion to complete.

```python
# Check existing archives including those pending deletion
archives = client.list_archives()
for a in archives['Archives']:
    print(f"{a['ArchiveName']}: {a['ArchiveState']}")
```

## CloudFormation Issues

### TargetArchive validation error (66-char limit)

`!GetAtt Archive.ArchiveId` returns the full ARN (known CloudFormation behavior). Extract the short ID:
```yaml
TargetArchive: !Select
  - 1
  - !Split
    - "/"
    - !GetAtt MyArchive.ArchiveArn
```

### Stack rollback leaves orphaned resources

Archive and other resources may enter `PENDING_DELETION` after rollback, claiming the name. Use unique names:
```yaml
ArchiveName: !Sub "${AWS::StackName}-archive-${AWS::AccountId}"
```

## IAM Issues

### "Access Denied" on Mail Manager operations

Mail Manager IAM actions use the `ses:` prefix, not `mailmanager:`. Example actions:
- `ses:CreateIngressPoint`
- `ses:CreateTrafficPolicy`
- `ses:CreateRuleSet`
- `ses:CreateArchive`

For development, you can use a broad SES policy (note: this covers all SES actions, not only Mail Manager):
```json
{
  "Effect": "Allow",
  "Action": [
    "ses:Create*",
    "ses:Get*",
    "ses:List*",
    "ses:Delete*",
    "ses:Update*",
    "ses:StartArchive*"
  ],
  "Resource": "*"
}
```

`"Resource": "*"` is required here because Mail Manager operations do not currently support resource-level ARN restrictions. For production, scope to only the specific actions your workflow requires. See the [Getting Started Guide](../setup/getting-started.md) for a minimal scoped policy example.

### Send to internet action gets "Access Denied"

The IAM role for the Send action needs:
- Trust policy allowing `ses.amazonaws.com` to assume the role
- Permission for `ses:SendRawEmail` on the identity and configuration set resources
- If using a configuration set, include both `identity/*` and `configuration-set/*` in the resource ARNs
