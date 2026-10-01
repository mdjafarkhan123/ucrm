// How a person says they sent a quote themselves. The database keeps the same list in
// `private.quote_external_send_channel_label`, which writes the history line — the two must agree.
export const QUOTE_EXTERNAL_SEND_CHANNELS = [
	{ value: 'in_person', label: 'In person' },
	{ value: 'phone', label: 'Phone call' },
	{ value: 'text_message', label: 'Text message' },
	{ value: 'own_email', label: 'My own email' },
	{ value: 'printed', label: 'Printed or posted copy' },
	{ value: 'other', label: 'Other' }
] as const;

export type QuoteExternalSendChannel = (typeof QUOTE_EXTERNAL_SEND_CHANNELS)[number]['value'];

export const QUOTE_EXTERNAL_SEND_CHANNEL_VALUES = QUOTE_EXTERNAL_SEND_CHANNELS.map(
	(channel) => channel.value
) as [QuoteExternalSendChannel, ...QuoteExternalSendChannel[]];

export const QUOTE_SEND_NOTE_MAX = 500;

// The two ways a Draft quote leaves Draft: UCRM emails it, or a person says they already sent it.
export type QuoteSendChoice =
	| { method: 'email' }
	| { method: 'external'; channel: QuoteExternalSendChannel; note: string | null };

// Why a quote's latest email did not reach the customer. The database decides this in
// `private.quote_email_delivery_failure`, from the email itself — the two lists must agree.
export type QuoteDeliveryFailureReason = 'bounced' | 'not_accepted' | 'blocked' | 'not_sent';

export type QuoteDeliveryFailure = {
	reason: QuoteDeliveryFailureReason;
	failed_at: string;
	// Null for a member who may not see this client.
	recipient_email: string | null;
};

const DELIVERY_FAILURE_ENDINGS: Record<QuoteDeliveryFailureReason, string> = {
	bounced: 'bounced. That address does not accept mail.',
	not_accepted: 'was not accepted by their mailbox.',
	blocked: 'was blocked by their mail server.',
	not_sent: 'could not be sent.'
};

// One sentence saying what happened to the email, in the same words the alert and the quote history use.
export function quoteDeliveryFailureSentence(failure: QuoteDeliveryFailure) {
	const to = failure.recipient_email
		? `The quote email to ${failure.recipient_email}`
		: 'The quote email';
	return `${to} ${DELIVERY_FAILURE_ENDINGS[failure.reason]}`;
}
