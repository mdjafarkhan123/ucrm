// The marketing-email consent control on a public form (Marketing M1). Mirrors the service-SMS pattern in
// sms-consent.ts: an optional, unchecked box shown only when email is collected, naming the business, what the
// emails are about, that frequency varies, that they can unsubscribe, and that consent is not a condition of
// purchase (CAN-SPAM / GDPR expectations). The page shows these words and the server stores them, so the recorded
// evidence is exactly what the customer saw. Final wording still needs compliance review before live Marketing.

export const EMAIL_MARKETING_CONSENT_LABEL = 'Send me occasional offers and updates by email';

export function emailMarketingConsentDescription(businessName: string): string {
	return (
		`I agree to receive marketing emails from ${businessName} with offers, news and updates. ` +
		'Message frequency varies. You can unsubscribe at any time. Consent is not a condition of purchase.'
	);
}

export function emailMarketingConsentDisclosure(businessName: string): string {
	return `${EMAIL_MARKETING_CONSENT_LABEL}. ${emailMarketingConsentDescription(businessName)}`;
}
