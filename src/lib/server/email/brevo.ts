import { PLATFORM_CONTACT_EMAIL } from '$lib/account/standing';
import { getEmailEnv } from './env';

type SendTransactionalEmailParams = {
	to: { email: string; name?: string };
	subject: string;
	htmlContent: string;
	textContent: string;
};

const BREVO_SEND_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';

// Inboxes show this name instead of the "noreply" start of the address. Replies go to a mailbox someone reads.
export const SYSTEM_FROM_NAME = 'Uplift';

export function systemEmailSender(fromEmail: string) {
	return {
		sender: { name: SYSTEM_FROM_NAME, email: fromEmail },
		replyTo: { name: SYSTEM_FROM_NAME, email: PLATFORM_CONTACT_EMAIL }
	};
}

export async function sendTransactionalEmail(params: SendTransactionalEmailParams) {
	const { BREVO_API_KEY, SYSTEM_FROM_EMAIL } = getEmailEnv();

	const response = await fetch(BREVO_SEND_ENDPOINT, {
		method: 'POST',
		headers: {
			'content-type': 'application/json',
			accept: 'application/json',
			'api-key': BREVO_API_KEY
		},
		body: JSON.stringify({
			...systemEmailSender(SYSTEM_FROM_EMAIL),
			to: [params.to],
			subject: params.subject,
			htmlContent: params.htmlContent,
			textContent: params.textContent
		})
	});

	if (!response.ok) {
		const body = await response.text().catch(() => '');
		throw new Error(`Brevo request failed with status ${response.status}: ${body.slice(0, 300)}`);
	}
}
