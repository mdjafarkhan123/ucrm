import { getEmailEnv } from './env';

type SendTransactionalEmailParams = {
	to: { email: string; name?: string };
	subject: string;
	htmlContent: string;
	textContent: string;
};

const BREVO_SEND_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';

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
			sender: { email: SYSTEM_FROM_EMAIL },
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
