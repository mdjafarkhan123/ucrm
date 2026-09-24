# Troubleshooting Common SES Issues

## Error: MessageRejected

**Causes:**
- Identity not verified — verify the sending domain or email address
- Sandbox mode — recipient email address must also be verified
- Account sending paused — check your reputation dashboard
- Suppressed address — the recipient is on your suppression list

**Fix:** Check `GetEmailIdentity` for verification status and `GetAccount` for sandbox/pause status.

## Error: ConfigurationSetDoesNotExistException

The configuration set name in your send call doesn't match any configuration set in your account.

**Fix:** Check for typos. Configuration set names are case-sensitive. Verify the config set exists in the same region.

## Error: AccountSendingPausedException

Your account or tenant sending has been paused by SES enforcement due to reputation issues.

**Fix:** Check the SES console reputation dashboard. Review bounce and complaint rates. File a support case if you believe the pause is in error.

## "Throttling" That Isn't Throttling

**Common pattern:** Customer believes SES is throttling their sends, but SES logs show zero throttling events.

**What's actually happening:** The customer's application is pre-emptively rate limiting itself. Messages are being dropped BEFORE reaching SES APIs.

**How to diagnose:**
1. Check your application's rate limiting / retry configuration
2. Check SES Amazon CloudWatch metrics for `Throttle` events — if zero, SES isn't throttling you
3. Your transactions per second (TPS) limit is a ceiling, not a guaranteed rate. SES does not throttle below the limit.

**Burst vs sustained TPS:** A 1000 TPS limit allows bursts but not sustained 1000 TPS. SES applies per-second rate limiting. If you need higher sustained throughput, request a quota increase.

## Emails Landing in Spam

**Common causes:**
1. **No DomainKeys Identified Mail (DKIM)** — configure Easy DKIM on your domain
2. **No Sender Policy Framework (SPF) alignment** — set up a custom MAIL FROM domain
3. **No Domain-based Message Authentication, Reporting, and Conformance (DMARC)** — add a DMARC TXT record
4. **New domain with no reputation** — warm up gradually, start with transactional email
5. **High complaint rate** — review email content and recipient consent
6. **Sending to purchased lists** — never do this

**Fix:** Verify all three authentication methods are configured. See [verify-domain-identity.md](../identity/verify-domain-identity.md).

## Delivery Delays (Gmail 421 Responses)

**What's happening:** The receiving server (commonly Gmail) is returning temporary 421 responses. SES retries delivery for up to 14 hours. If the receiving server continues rejecting, SES eventually bounces the message.

**Key facts:**
- SES sends "Delivery Delay" events after 4+ hours (if you configured delivery delay event notifications)
- Gmail throttles by DKIM/SPF domain, not by IP
- Very low retry success rate when Gmail is actively throttling
- Root cause is usually: new domain, no reputation, or sudden volume spike

**Fix:** Enable delivery delay events in your configuration set. Ramp up sending volume gradually for new domains. Monitor Gmail Postmaster Tools for domain reputation.

## High Bounce Rate (> 5%)

**Impact:** SES will PAUSE, THROTTLE, or SHUTDOWN your account/tenant.

**Common causes:**
- Sending to stale email lists
- No email validation before sending
- Sending to purchased/scraped addresses
- No suppression list configured

**Fix:**
1. Enable account-level and config-set-level suppression for BOUNCE and COMPLAINT
2. Use Email Validation API to check addresses before adding to your list
3. Remove addresses that hard-bounced — they will never succeed
4. Implement double opt-in for new subscribers

## High Complaint Rate (> 0.1%)

**Impact:** Same as high bounce — enforcement action.

**Note:** Gmail Feedback Loop (FBL) can trigger enforcement even when your SES metrics look healthy. Gmail reports complaints externally through its own feedback loop, and SES may see these with a delay.

**Fix:**
1. Include a clear unsubscribe link in every marketing email
2. Honor unsubscribe requests immediately
3. Only send to recipients who opted in
4. Segment transactional vs marketing email using separate configuration sets

## Sandbox Limitations

**In sandbox mode:**
- Can only send to verified email addresses (To, CC, BCC)
- Daily sending quota is limited (typically 200 emails/day)
- Sending rate limited to 1 email/second

**Fix:** Request production access via the SES console. You'll need to describe your use case, explain how you handle bounces/complaints, and confirm you have recipient consent.

## DKIM Verification Stuck in PENDING

DNS propagation can take up to 72 hours. Check your CNAME records:

```bash
dig CNAME {token}._domainkey.example.com
```

If the record exists but SES still shows PENDING, wait. If records are missing, re-add them to DNS.

## MAIL FROM Domain Verification Failed

**Common issue:** The MX record for your custom MAIL FROM domain points to the wrong region.

Each SES region has its own SMTP feedback endpoint:
- `us-east-1` → `feedback-smtp.us-east-1.amazonses.com`
- `us-west-2` → `feedback-smtp.us-west-2.amazonses.com`
- `eu-west-1` → `feedback-smtp.eu-west-1.amazonses.com`

**Also:** SPF does NOT inherit from parent domains. `example.com` having SPF does NOT give `mail.example.com` SPF. You must add the TXT record specifically for your MAIL FROM subdomain.
