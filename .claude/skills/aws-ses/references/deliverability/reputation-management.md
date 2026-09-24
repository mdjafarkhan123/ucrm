# Reputation Management Guide

Your sender reputation determines whether emails reach the inbox or spam folder. SES monitors reputation and enforces thresholds to protect email deliverability.

## Key Thresholds

| Metric | Threshold | Consequence |
|--------|-----------|-------------|
| Bounce rate | > 5% | Enforcement (PAUSE/THROTTLE/SHUTDOWN) |
| Complaint rate | > 0.1% | Enforcement |

These are measured over a rolling window. Stay well below these thresholds.

## Virtual Deliverability Manager (VDM)

VDM provides a dashboard and advisor for monitoring deliverability.

### To enable VDM

```python
import boto3

client = boto3.client('sesv2', region_name='us-east-1')

client.put_account_vdm_attributes(
    VdmAttributes={
        'VdmEnabled': 'ENABLED',
        'DashboardAttributes': {'EngagementMetrics': 'ENABLED'},
        'GuardianAttributes': {'OptimizedSharedDelivery': 'ENABLED'}
    }
)
```

### To check account reputation

```python
response = client.get_account()
print(f"Sending enabled: {response['SendingEnabled']}")
print(f"Production access: {response['ProductionAccessEnabled']}")

enforcement = response.get('EnforcementStatus', 'HEALTHY')
print(f"Enforcement status: {enforcement}")
```

## Monitoring with Amazon CloudWatch

SES publishes these metrics to CloudWatch under the `AWS/SES` namespace:

| Metric | What It Measures |
|--------|-----------------|
| `Send` | Emails sent |
| `Delivery` | Emails delivered |
| `Bounce` | Emails bounced |
| `Complaint` | Spam complaints received |
| `Reject` | Emails rejected (virus/malware detected in content) |
| `Open` | Emails opened (if tracking enabled) |
| `Click` | Links clicked (if tracking enabled) |

### To create a bounce rate alarm

```python
cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')

cloudwatch.put_metric_alarm(
    AlarmName='SES-BounceRate-High',
    MetricName='Reputation.BounceRate',
    Namespace='AWS/SES',
    Statistic='Average',
    Period=3600,
    EvaluationPeriods=1,
    Threshold=0.05,
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=['arn:aws:sns:us-east-1:123456789012:ses-alerts']
)
```

## Enforcement Actions

When thresholds are exceeded, SES may take these actions:

| Action | Effect | Recovery |
|--------|--------|----------|
| **PAUSE** | Sending temporarily stopped | Fix the issue, SES may auto-resume or require support case |
| **THROTTLE** | Sending rate reduced | Improve metrics to return to normal rate |
| **SHUTDOWN** | Account permanently disabled for sending | File support case; requires detailed remediation plan |

**With tenants:** Only the problematic tenant is enforced, not the entire account.

## Best Practices

1. **Enable VDM** from day one
2. **Set up CloudWatch alarms** for bounce rate (> 3%) and complaint rate (> 0.05%) — alert BEFORE you hit enforcement thresholds
3. **Use suppression lists** to auto-suppress bounced/complained addresses
4. **Use Email Validation** to check addresses before sending
5. **Separate mail streams** with configuration sets and tenants
6. **Monitor Gmail Postmaster Tools** — Gmail FBL can trigger enforcement even when SES metrics look healthy
7. **Warm up new domains/IPs gradually** — don't blast full volume on day one


## Clean Up

To avoid ongoing charges, delete the resources created in this guide.

### To disable VDM

**AWS CLI:**
```bash
aws sesv2 put-account-vdm-attributes \
    --vdm-attributes VdmEnabled=DISABLED \
    --region us-east-1
```

**Python:**
```python
client.put_account_vdm_attributes(
    VdmAttributes={'VdmEnabled': 'DISABLED'}
)
```

### To delete Amazon CloudWatch alarms

**AWS CLI:**
```bash
aws cloudwatch delete-alarms \
    --alarm-names SES-BounceRate-High \
    --region us-east-1
```

**Python:**
```python
cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')
cloudwatch.delete_alarms(AlarmNames=['SES-BounceRate-High'])
```

> **Note:** Disabling VDM stops the dashboard and advisor features. Re-enable at any time with no data loss.
