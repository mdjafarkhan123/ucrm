// The service-SMS consent control on a public form (Part 4 Stage 5). HighLevel's A2P pattern: an optional,
// unchecked, non-marketing box that appears only once a phone number is entered, with the business named, what
// the texts are about, frequency, rates and STOP/HELP (the carrier call-to-action elements). The page shows these
// words and the server stores them, so the evidence is exactly what the visitor saw. Final wording still needs
// compliance review before live SMS (docs/website-chat-behavior-contract.md).

export const SERVICE_SMS_CONSENT_LABEL = 'Text me about my request';

export function serviceSmsConsentDescription(businessName: string): string {
	return (
		`I agree to receive text messages from ${businessName} about my request, quotes and appointments. ` +
		'Message frequency varies. Message and data rates may apply. Reply STOP to opt out or HELP for help. ' +
		'Consent is not a condition of purchase.'
	);
}

export function serviceSmsConsentDisclosure(businessName: string): string {
	return `${SERVICE_SMS_CONSENT_LABEL}. ${serviceSmsConsentDescription(businessName)}`;
}
