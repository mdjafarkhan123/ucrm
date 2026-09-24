# Dedicated IP Addresses Guide

By default, SES sends from shared IP pools. Dedicated IPs give you your own sending IPs with independent reputation.

## Shared vs Dedicated vs Managed Dedicated

| Type | Reputation | Warmup | Management | Best For |
|------|-----------|--------|------------|----------|
| **Shared** (default) | Shared with other SES customers | None needed | Fully managed by AWS | Most customers, low-medium volume |
| **Dedicated (Standard)** | You own it | Manual warmup required | You manage | High volume, specific IP requirements |
| **Managed Dedicated** | You own it | Automatic warmup | AWS manages scaling and warmup | High volume, want dedicated without operational overhead |

## When to Use Dedicated IPs

- Sending > 100K emails/day consistently
- Regulatory requirements for IP isolation
- Need predictable IP reputation independent of other senders
- Brand reputation requirements

**Do NOT use dedicated IPs if:**
- Sending low volume (< 10K/day) — not enough volume to build reputation
- Just starting out — shared pool reputation is better than a cold dedicated IP

## Requesting Dedicated IPs

Dedicated IPs are requested through AWS Support or the SES console. See [SES pricing](https://aws.amazon.com/ses/pricing/) for current dedicated IP costs.

## How Throttling Works with Dedicated IPs

SES enforces throttling at two levels. Understanding this prevents unexpected rate limiting.

### Account-Level TPS (Applies to Everyone)

Your account has a TPS (transactions per second) limit that acts as a **hard ceiling** across all sending — shared pool, dedicated pool, and managed pool combined. This is enforced first, before any pool-level checks.

If you're hitting your account TPS limit, request an increase through the SES console or AWS Support.

### Pool-Level Throttling

| IP Type | Pool-Level Throttling | What to Know |
|---------|----------------------|-------------|
| **Standard Dedicated** | Yes — based on number of IPs and their warmup status | Pool capacity = sum of individual IP capacities. If your pool capacity exceeds your account TPS limit, the account limit wins. You may need to request an account TPS increase as you add IPs. |
| **Managed Dedicated** | Not a concern — auto-scales with spillover | Traffic automatically spills over to shared IPs when pool capacity is exceeded. You only need to worry about your account TPS limit. |
| **Shared** | Not applicable | AWS manages shared pool capacity. |

**Key takeaway:**
- **Standard DIP customers:** Monitor both your account TPS limit AND your pool capacity. Adding more IPs increases pool capacity but doesn't increase your account TPS limit — request an increase separately if needed.
- **Managed DIP customers:** Only monitor your account TPS limit. Pool capacity is handled automatically.

## IP Pools

Group dedicated IPs into pools and assign pools to configuration sets:

```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

# Create an IP pool
client.create_dedicated_ip_pool(
    PoolName='transactional-pool',
    ScalingMode='STANDARD'  # or 'MANAGED' for managed dedicated
)

# Assign pool to a configuration set
client.put_configuration_set_delivery_options(
    ConfigurationSetName='transactional-config',
    SendingPoolName='transactional-pool'
)
```

## Warmup (Standard Dedicated IPs Only)

New dedicated IPs have zero reputation. ISPs will reject or rate-limit email from unknown IPs.

**Warmup schedule (approximate):**

| Day | Recommended Volume |
|-----|-------------------|
| 1-2 | 200/day |
| 3-4 | 500/day |
| 5-7 | 1,000/day |
| 8-14 | 5,000/day |
| 15-21 | 20,000/day |
| 22-30 | 50,000/day |
| 30+ | Full volume |

**During warmup:**
- SES may spill excess traffic to shared IPs (this is normal)
- Send to your most engaged recipients first
- Monitor bounce rates closely — cold IPs are more sensitive

**Managed dedicated IPs** handle warmup automatically — no manual schedule needed.

## Monitoring IP Reputation

```python
# List your dedicated IPs
response = client.get_dedicated_ips()
for ip in response['DedicatedIps']:
    print(f"IP: {ip['Ip']}, Pool: {ip['PoolName']}, Warmup: {ip['WarmupStatus']}")
```

Check Microsoft SNDS (Smart Network Data Services) for IP reputation with Microsoft/Outlook domains.

### Release Dedicated IPs

There is no API to release an individual dedicated IP. To release a dedicated IP, contact AWS Support or use the SES console.

Before releasing, list your dedicated IPs to identify which ones to release:

**AWS CLI:**
```bash
aws sesv2 get-dedicated-ips --region us-east-1
```

**Python:**
```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

response = client.get_dedicated_ips()
for ip in response['DedicatedIps']:
    print(f"IP: {ip['Ip']}, Pool: {ip['PoolName']}, Warmup: {ip['WarmupStatus']}")
```

> **Note:** Releasing a dedicated IP is permanent. You cannot reclaim the same IP address. Before releasing, confirm you no longer need the IP's established reputation.

### Delete IP Pool

After releasing the dedicated IPs from a pool, delete the pool itself.

**AWS CLI:**
```bash
aws sesv2 delete-dedicated-ip-pool \
    --pool-name transactional-pool \
    --region us-east-1
```

**Python:**
```python
client.delete_dedicated_ip_pool(
    PoolName='transactional-pool'
)
```

> **Note:** Releasing a dedicated IP is permanent. You cannot reclaim the same IP address. Before releasing, confirm you no longer need the IP's established reputation.
