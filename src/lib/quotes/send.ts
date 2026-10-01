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
