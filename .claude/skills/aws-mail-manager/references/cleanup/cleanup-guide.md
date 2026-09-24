---
description: "Safely delete Amazon SES Mail Manager resources. Teardown script and dependency order for ingress points, rule sets, traffic policies, relays, and archives."
---

# Amazon SES Mail Manager Resource Cleanup

## Prerequisites

- boto3 installed: `pip install boto3`
- AWS credentials configured with permissions for `ses:Delete*`, `ses:List*`, and `ses:Get*` operations
- Know which resources to delete (use the list operations in the [teardown script](#teardown-script) to discover them)

## ⚠️ Important

When you delete an ingress point, the endpoint stops accepting email. Email sent to the deleted endpoint's hostname returns a bounce. Confirm before deleting ingress points in production.

## Dependency Order — Delete in Reverse

Resources must be deleted in reverse dependency order. Deleting a traffic policy or rule set that is still attached to an active ingress point will fail.

```
1. Ingress Points      ← delete first (depends on traffic policy + rule set)
2. Rule Sets           ← delete after all ingress points referencing them are gone
3. Traffic Policies    ← delete after all ingress points referencing them are gone
4. Relays              ← delete after rule sets referencing them are gone
5. Archives            ← async deletion (PENDING_DELETION state)
6. Address Lists       ← delete last (no dependents)
```

## Teardown Script

```python
import boto3

REGION = "us-east-1"
client = boto3.client("mailmanager", region_name=REGION)


def list_all(list_fn, key, **kwargs):
    """Generic paginator for Mail Manager list operations."""
    items = []
    next_token = None
    while True:
        params = {"PageSize": 100, **kwargs}
        if next_token:
            params["NextToken"] = next_token
        response = list_fn(**params)
        items.extend(response.get(key, []))
        next_token = response.get("NextToken")
        if not next_token:
            break
    return items


# Step 1: Delete ingress points first
# WARNING: Deleting an ingress point immediately stops all email delivery.
# Email sent to this endpoint after deletion will bounce.
ingress_points = list_all(client.list_ingress_points, "IngressPoints")
for ip in ingress_points:
    ip_id = ip["IngressPointId"]
    name = ip["IngressPointName"]
    print(f"Deleting ingress point: {name} ({ip_id})")
    client.delete_ingress_point(IngressPointId=ip_id)

# Step 2: Delete rule sets
rule_sets = list_all(client.list_rule_sets, "RuleSets")
for rs in rule_sets:
    rs_id = rs["RuleSetId"]
    print(f"Deleting rule set: {rs['RuleSetName']} ({rs_id})")
    client.delete_rule_set(RuleSetId=rs_id)

# Step 3: Delete traffic policies
policies = list_all(client.list_traffic_policies, "TrafficPolicies")
for tp in policies:
    tp_id = tp["TrafficPolicyId"]
    print(f"Deleting traffic policy: {tp['TrafficPolicyName']} ({tp_id})")
    client.delete_traffic_policy(TrafficPolicyId=tp_id)

# Step 4: Delete relays
relays = list_all(client.list_relays, "Relays")
for relay in relays:
    relay_id = relay["RelayId"]
    print(f"Deleting relay: {relay['RelayName']} ({relay_id})")
    client.delete_relay(RelayId=relay_id)

# Step 5: Delete archives (async — sets state to PENDING_DELETION)
# WARNING: Archive deletion permanently removes all stored emails.
# Export any needed emails before deleting (see archive-guide.md).
archives = list_all(client.list_archives, "Archives")
for archive in archives:
    archive_id = archive["ArchiveId"]
    print(f"Deleting archive: {archive['ArchiveName']} ({archive_id})")
    client.delete_archive(ArchiveId=archive_id)
    # Note: archive is NOT immediately gone — state becomes PENDING_DELETION

# Step 6: Delete address lists
address_lists = list_all(client.list_address_lists, "AddressLists")
for al in address_lists:
    al_id = al["AddressListId"]
    print(f"Deleting address list: {al['AddressListName']} ({al_id})")
    client.delete_address_list(AddressListId=al_id)

print("Cleanup complete.")
```

## Deleting Individual Resources

### Ingress Point

```python
# Close the ingress point first (stops accepting connections gracefully)
client.update_ingress_point(
    IngressPointId="inp-xxxx",
    StatusToUpdate="CLOSED",
)

# Then delete
client.delete_ingress_point(IngressPointId="inp-xxxx")
```

### Rule Set

```python
# Returns an error if any ingress point still references this rule set
client.delete_rule_set(RuleSetId="rs-xxxx")
```

### Traffic Policy

```python
# Returns an error if any ingress point still references this policy
client.delete_traffic_policy(TrafficPolicyId="tp-xxxx")
```

### Archive

```python
# WARNING: Archive deletion permanently removes all stored emails.
# Export any needed emails before deleting (see archive-guide.md).
# Deletion is async — archive enters PENDING_DELETION state.
# Archived emails are retained until the deletion completes.
client.delete_archive(ArchiveId="a-xxxx")

# Check status
response = client.get_archive(ArchiveId="a-xxxx")
print(response["ArchiveState"])  # PENDING_DELETION
```

### Add-on Instances and Subscriptions

```python
# Delete instance before subscription
client.delete_addon_instance(AddonInstanceId="ai-xxxx")
client.delete_addon_subscription(AddonSubscriptionId="as-xxxx")
```

## DNS Cleanup

After deleting an ingress point, remove or update the MX record for your domain. Leaving an MX record pointing to a deleted ingress point will cause email to bounce.

```bash
# Verify the ingress point hostname is no longer resolving
dig MX yourdomain.com
```

## Common Errors During Cleanup

| Error | Cause | Fix |
|-------|-------|-----|
| `ResourceNotFoundException` | Resource already deleted or wrong ID | Check IDs with list operations first |
| `ConflictException` | Ingress point still references the resource | Delete ingress points first |
| `ValidationException` on archive delete | Archive already in `PENDING_DELETION` | No action needed — already being deleted |
