# Preserving contractor mailboxes when moving authoritative DNS to Cloudflare

Research date: 2026-08-29  
Scope: Existing GoDaddy/Hostinger-hosted mailboxes, a Cloudflare authoritative-DNS cutover, Brevo sending and inbound parsing, and comparison with HighLevel's LC Email DNS pattern.  
Evidence standard: first-party provider documentation and the SMTP standard only.

## Conclusion

Yes. A contractor can keep receiving `name@contractor.com` in the existing GoDaddy, Microsoft 365, Hostinger, Google Workspace, or other mailbox after the domain's authoritative DNS moves to Cloudflare. Changing nameservers changes **where DNS is managed**; it does not itself migrate or cancel the mailbox service. The existing mailbox continues to work only if its complete DNS configuration is recreated accurately in Cloudflare before the nameserver cutover and the mailbox subscription remains active.

The safe UCRM topology with Brevo is:

- `contractor.com` root MX records remain pointed at the contractor's existing mailbox provider.
- A dedicated sending domain/subdomain is authenticated for Brevo outbound mail.
- A **different** receiving subdomain, such as `reply.contractor.com`, gets Brevo's two inbound MX records.

The Brevo MX records on `reply.contractor.com` route only addresses ending in `@reply.contractor.com`; they do not replace or interfere with the root MX records used by `person@contractor.com`. This is also consistent with HighLevel's official warning that subdomain MX records do not interfere with root-domain mail, although HighLevel's own Mailgun-backed record layout must not be copied literally onto Brevo.

## 1. What changing to Cloudflare nameservers does

The registrar and authoritative DNS host are separate roles. A domain may remain registered at GoDaddy or Hostinger while Cloudflare becomes the place that answers authoritative DNS queries. GoDaddy says that when custom nameservers are selected, DNS is managed at the other company; Hostinger likewise says changing nameservers moves DNS-zone management to the new provider. Neither source says the mailbox subscription is automatically migrated or cancelled. [GoDaddy nameserver guidance](https://www.godaddy.com/en-uk/help/change-my-domain-nameservers-664), [Hostinger nameserver guidance](https://www.hostinger.com/support/1696789-how-to-change-nameservers-at-hostinger/)

Mail delivery depends on the live MX records. GoDaddy defines MX records as telling mail services where to deliver mail, and Hostinger explicitly supports keeping Hostinger Email while DNS is managed at Cloudflare by publishing Hostinger's MX values in the Cloudflare zone. [GoDaddy MX guidance](https://www.godaddy.com/en-uk/help/whats-an-mx-record-324), [Hostinger MX guidance](https://support.hostinger.com/en/articles/4443666-how-to-manage-mx-records)

Therefore:

- Moving nameservers alone does not delete the contractor's mailbox or stored mail.
- Missing or wrong records in the new authoritative zone can make new mail, sending authentication, mail-client discovery, or the website fail.
- Cancelling the old email/hosting product is a separate commercial action and may terminate the mailbox even if DNS is correct. UCRM must not assume that moving DNS authorizes cancellation of any contractor service.

## 2. Records that must be preserved

Cloudflare's automatic scan is only a convenience. Cloudflare says the scan is not guaranteed to find all existing records and requires users to review and manually add missing records before changing nameservers. Hostinger makes the same point for a Cloudflare setup, specifically calling out missing MX and DKIM records. [Cloudflare full-zone setup](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/), [Cloudflare quick-scan limitations](https://developers.cloudflare.com/dns/zone-setups/reference/dns-quick-scan/), [Hostinger Cloudflare setup](https://www.hostinger.com/support/4741545-how-to-use-cloudflare-in-hostinger/)

Before cutover, inventory and reproduce every record required by the current services, including where present:

- root-domain MX records, with exact priorities and destinations;
- SPF TXT, DKIM TXT/CNAME selectors, and DMARC TXT;
- mailbox verification TXT records;
- `autodiscover`, `mail`, `webmail`, `smtp`, `imap`, and related CNAME/A/AAAA records;
- SRV records used by Microsoft 365 or another collaboration/mail service;
- website apex, `www`, and all business subdomains;
- CAA and any third-party verification records.

Do not create a second independent SPF TXT record at the same hostname. If another sender must be authorized at that exact hostname, its mechanism must be incorporated into the one valid SPF policy after checking lookup limits. Separate subdomains can have separate SPF policies.

## 3. Root mail and subdomain mail are separate routing names

SMTP delivery looks up the MX record associated with the recipient address's domain name. RFC 5321 requires the lookup for that name and then uses its MX destinations. Thus `employee@contractor.com` queries MX for `contractor.com`, while an alias such as `opaque-token@reply.contractor.com` queries MX for `reply.contractor.com`. [RFC 5321, section 5.1](https://www.rfc-editor.org/rfc/rfc5321#section-5.1)

HighLevel's own current setup guide confirms the operational consequence: MX records placed on a subdomain such as `replies.companyname.com` do not interfere with the root domain's Google Workspace mail, whereas adding Mailgun MX records at the root would conflict with the existing root MX records. [HighLevel manual DNS setup](https://help.gohighlevel.com/support/solutions/articles/155000004427-manually-adding-dns-records-for-dedicated-sending-domains)

Safe example:

| Address/domain | MX destination | Purpose |
| --- | --- | --- |
| `person@contractor.com` / MX at `contractor.com` | Existing GoDaddy/Hostinger/Microsoft/Google mail servers | Contractor's normal mailbox |
| `token@reply.contractor.com` / MX at `reply.contractor.com` | `inbound1.sendinblue.com`, `inbound2.sendinblue.com` | UCRM-correlated replies parsed by Brevo |

Never replace the root MX records with Brevo inbound MX values unless the approved intent is to stop direct root-domain mailbox delivery and route all root mail to Brevo. That is not the proposed UCRM behavior.

## 4. The six-record discussion and the Brevo/HighLevel distinction

The six records currently proposed for `reply.test.upliftcontractor.com` are four Brevo verification/authentication records plus two Brevo inbound MX records. They are platform DNS setup, not mailbox accounts.

The earlier suggestion to standardize Brevo on HighLevel's single `mg.contractor.com` subdomain for both jobs is not supported by Brevo's official documentation. Brevo expressly says its inbound receiving domain or subdomain **must differ from the domain used for sending email**, recommends `reply.yourdomain.com`, and instructs publishing its two MX records there. Any address at that receiving domain is parsed and posted to the configured webhook. [Brevo inbound parse documentation](https://developers.brevo.com/docs/inbound-parse-webhooks)

HighLevel's LC Email implementation is different. Its current manual setup uses five records on its dedicated subdomain—two TXT, two Mailgun MX, and one CNAME—and describes that subdomain as serving its Mailgun-backed flow. Its general dedicated-domain guidance also warns that the subdomain must not already point at a different email server. [HighLevel manual DNS setup](https://help.gohighlevel.com/support/solutions/articles/155000004427-manually-adding-dns-records-for-dedicated-sending-domains), [HighLevel dedicated-domain setup](https://help.gohighlevel.com/support/solutions/articles/48001226115-dedicated-email-sending-domains-overview-setup)

UCRM should copy HighLevel's **product principle**—use dedicated subdomains and keep the root mailbox safe—not its provider-specific record count or single-subdomain topology. With Brevo, outbound and inbound readiness remain separate.

## 5. Cloudflare proxy constraints

MX and TXT records are inherently DNS-only in Cloudflare. A/AAAA/CNAME hostnames used by SMTP, IMAP, POP3, autodiscover, DKIM, or third-party verification must not be accidentally proxied when the provider needs the original DNS answer. Cloudflare states that its ordinary HTTP proxy does not proxy SMTP/IMAP/POP3 and advises setting mail-related records and MX targets to DNS-only. It also warns that CNAME flattening can prevent providers from reading DKIM or autodiscover CNAMEs correctly. [Cloudflare email troubleshooting](https://developers.cloudflare.com/dns/troubleshooting/email-issues/), [Cloudflare proxy use cases](https://developers.cloudflare.com/dns/proxy-status/use-cases/)

Do not enable Cloudflare Email Routing on the root domain as part of this onboarding. Cloudflare says Email Routing manages root MX records and can conflict with a different mail provider. Ordinary Cloudflare authoritative DNS is enough; Cloudflare does not need to sit in the SMTP path. [Cloudflare email troubleshooting](https://developers.cloudflare.com/dns/troubleshooting/email-issues/)

## 6. Safe nameserver-cutover procedure

1. **Identify the current services and owner.** Record the registrar, current authoritative nameservers, website host, mailbox provider/product, active mailbox addresses, and who can verify mailbox health. Confirm the email subscription will remain active after DNS moves.
2. **Capture the current live zone.** Export when possible and separately query the public records. Do not rely only on Cloudflare's quick scan. Preserve exact names, values, priorities, and TTLs for MX/TXT/CNAME/SRV/A/AAAA/CAA records.
3. **Create the Cloudflare zone without cutting over.** Import/enter all current records first. Start A/AAAA/CNAME records as DNS-only, as Cloudflare recommends for a low-risk activation. Keep all email-related records DNS-only. [Cloudflare downtime guidance](https://developers.cloudflare.com/fundamentals/performance/minimize-downtime/)
4. **Compare old and new zones.** Check especially root MX, SPF, every DKIM selector, DMARC, autodiscover/mail hostnames, SRV, apex/`www`, and verification records. Query the assigned Cloudflare nameservers directly before delegation if needed.
5. **Handle DNSSEC before nameservers.** If an old DS record exists, remove/disable it at the registrar and wait for its TTL to expire before changing nameservers. Cloudflare warns that switching while the old DS remains cached causes validating resolvers to return `SERVFAIL`. After Cloudflare is authoritative and stable, enable Cloudflare DNSSEC and publish its new DS record at the registrar. [Cloudflare DNSSEC migration guidance](https://developers.cloudflare.com/dns/dnssec/)
6. **Change only the authoritative nameservers.** Do not transfer or cancel the registration, hosting, or email product as part of this step. Nameserver propagation may expose clients to old or new authority during the transition, so both zones should serve equivalent critical records.
7. **Verify externally before adding UCRM records.** Check NS and DNSSEC status, root MX against the mailbox provider's expected values, website resolution, a real inbound message to an existing root mailbox, and an outbound message from it. Also verify SPF/DKIM/DMARC and mail-client discovery where used. Cloudflare recommends comparing public MX results with the mail provider's expected values. [Cloudflare email troubleshooting](https://developers.cloudflare.com/dns/troubleshooting/email-issues/)
8. **Add Brevo subdomain records without touching root MX.** Authenticate the outbound sending domain according to Brevo's returned records. Configure a different receiving subdomain and add its two Brevo inbound MX records. Verify both names independently.
9. **Run end-to-end canaries.** Test existing root mailbox inbound/outbound, UCRM outbound, `Reply-To` routing through the Brevo inbound webhook, and conversation correlation. Retain the old DNS-zone snapshot and a documented reversal path until the observation window passes.

## 7. Primary failure modes and controls

| Failure | Effect | Control |
| --- | --- | --- |
| Trusting Cloudflare quick scan | Missing MX/DKIM/SRV or an obscure business record | Export, query, compare, and manually reconcile before delegation |
| Replacing root MX with Brevo/Cloudflare routing | Existing `@contractor.com` mail no longer reaches the old inbox | Root MX is protected configuration; Brevo inbound MX only on `reply.` |
| Keeping stale DNSSEC DS through the cutover | DNS `SERVFAIL`, potentially affecting web and mail | Remove old DS, wait TTL, cut over, then enable Cloudflare DNSSEC |
| Proxying a mail hostname or verification CNAME | SMTP/IMAP/POP/verification failure | DNS-only for all mail/service records and MX targets |
| Enabling Cloudflare Email Routing | Root MX conflict with existing mailbox provider | Leave it disabled unless a separately approved mailbox-routing migration exists |
| Cancelling old hosting/email because DNS moved | Mailbox product or stored mail may be lost | Treat DNS hosting, registration, web hosting, and email as separate assets |
| Copying HighLevel's Mailgun record design to Brevo | Provider verification or inbound webhook setup fails | Follow Brevo's required separate sending and receiving domains |

## Recommendation for contractor onboarding

Treat control of a contractor's full DNS zone as high-impact custody, not merely convenience. Build onboarding as an audited migration with a pre-cutover record inventory, immutable snapshot, provider-specific validation, explicit mailbox-preservation check, DNSSEC check, staged cutover, and tested rollback. UCRM may automate the Brevo records after the zone is safely on Cloudflare, but automation must refuse to overwrite root MX/SPF/DMARC or an occupied subdomain without an impact preview and Jafar's approved policy.

