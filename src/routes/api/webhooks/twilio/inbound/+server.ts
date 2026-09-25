import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseTwilioProvisioningStore } from '$lib/server/communications/twilio-provisioning-store';
import {
	classifySmsConsentEvent,
	collectTwilioValidationTokens,
	getTwilioInboundWebhookUrl,
	parseTwilioInboundMedia,
	parseTwilioInboundParams,
	twilioMediaFileName,
	validateTwilioSignature
} from '$lib/server/communications/twilio-webhook';

type InboundMessageRow = { id: string; organization_id: string };

const NO_STORE = { 'cache-control': 'no-store' } as const;
const EMPTY_TWIML_HEADERS = { ...NO_STORE, 'content-type': 'text/xml' } as const;

// Empty TwiML: Twilio needs a valid response, and Advanced Opt-Out (when OptOutType is present) has
// already sent its own keyword confirmation -- a <Message> verb here would send a second, unwanted reply.
const accepted = () => new Response('<Response/>', { status: 200, headers: EMPTY_TWIML_HEADERS });
// Signature could not be proven -- forged AccountSid, wrong/expired token, or a bad signature. Never say why.
const forbidden = () => new Response(null, { status: 403, headers: NO_STORE });
// The event is real but not yet durably stored: fail so Twilio resends rather than dropping it silently.
const retryLater = () => new Response(null, { status: 500, headers: NO_STORE });

export const POST: RequestHandler = async ({ request }) => {
	// Twilio inbound messages are application/x-www-form-urlencoded; the signature covers ALL POST params.
	let params: Record<string, string>;
	try {
		const form = await request.formData();
		params = {};
		for (const [key, value] of form.entries()) {
			if (typeof value === 'string') params[key] = value;
		}
	} catch {
		return forbidden();
	}

	const identifiers = parseTwilioInboundParams(params);
	if (!identifiers) return forbidden();

	const client = getOwnerSupabaseClient();
	const store = createSupabaseTwilioProvisioningStore(client);

	// AccountSid-lookup-then-validate: read from the *unvalidated* form only as a key to load that
	// subaccount's Auth Token(s). A forged AccountSid loads the wrong (or no) token, so validation fails.
	const account = await store.getAccountBySubaccountSid(identifiers.AccountSid);
	if (!account) return forbidden();

	const tokens = await collectTwilioValidationTokens(store, account.id, {
		organizationId: account.organizationId,
		subaccountSid: account.subaccountSid
	});

	const valid = validateTwilioSignature(
		tokens,
		request.headers.get('x-twilio-signature'),
		getTwilioInboundWebhookUrl(),
		params
	);
	if (!valid) return forbidden();

	// STOP/START/HELP is processed the same identity-resolution pass as an ordinary reply (an unresolved
	// or brand-new sender must still be protected), so the message is always recorded first.
	const { data: inboundMessage, error: messageError } = await client.rpc(
		'record_communication_sms_inbound_message',
		{
			target_organization_id: account.organizationId,
			target_provider_message_id: identifiers.MessageSid,
			target_from_number: identifiers.From,
			target_body: identifiers.Body,
			target_num_media: identifiers.NumMedia
		}
	);
	if (messageError) {
		console.error('Could not record an inbound Twilio SMS; asking the provider to retry.', {
			code: messageError.code
		});
		return retryLater();
	}

	// A retry of an already-recorded message (on-conflict do-nothing) returns null here -- its attachments
	// were either already inserted on the first delivery or never will be, the same accepted tradeoff the
	// SES inbound worker makes for its own attachment insert.
	const inserted = inboundMessage as InboundMessageRow | null;
	if (inserted?.id) {
		const mediaItems = parseTwilioInboundMedia(params, identifiers.NumMedia);
		if (mediaItems.length > 0) {
			const attachmentRows = mediaItems.map((item, index) => ({
				organization_id: inserted.organization_id,
				inbound_message_id: inserted.id,
				file_name: twilioMediaFileName(index, item.contentType),
				mime_type: item.contentType,
				byte_size: 0,
				status: 'pending_import' as const,
				provider: 'twilio' as const,
				provider_download_token: item.mediaUrl
			}));
			const { error: attachmentError } = await client
				.from('communication_inbound_attachments')
				.insert(attachmentRows);
			if (attachmentError) {
				console.error('Could not record inbound MMS attachments.', attachmentError);
			}
		}
	}

	const consentEvent = classifySmsConsentEvent(identifiers);
	if (consentEvent) {
		const { error: consentError } = await client.rpc(
			'record_communication_sms_consent_event_from_reply',
			{
				target_organization_id: account.organizationId,
				target_provider_message_id: identifiers.MessageSid,
				target_from_number: identifiers.From,
				target_event_kind: consentEvent.kind,
				target_confirmed_by_provider: consentEvent.confirmedByProvider
			}
		);
		if (consentError) {
			console.error('Could not record SMS consent evidence; asking the provider to retry.', {
				code: consentError.code
			});
			return retryLater();
		}
	}

	return accepted();
};
