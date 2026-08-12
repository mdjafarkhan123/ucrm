import { redirect } from '@sveltejs/kit';
import type { EmailOtpType } from '@supabase/supabase-js';

function safeNext(value: string | null) {
	return value && value.startsWith('/') && !value.startsWith('//') ? value : '/reset-password';
}

export async function GET(event) {
	const next = safeNext(event.url.searchParams.get('next'));
	const tokenHash = event.url.searchParams.get('token_hash');
	const type = event.url.searchParams.get('type') as EmailOtpType | null;
	const code = event.url.searchParams.get('code');

	let error: Error | null = null;
	if (tokenHash && type) {
		({ error } = await event.locals.supabase.auth.verifyOtp({ token_hash: tokenHash, type }));
	} else if (code) {
		try {
			({ error } = await event.locals.supabase.auth.exchangeCodeForSession(code));
		} catch (caught) {
			error = caught instanceof Error ? caught : new Error('Unable to complete the authentication code exchange.');
		}
	} else {
		error = new Error('Missing authentication confirmation parameters.');
	}

	if (error) {
		console.error('Contractor auth confirmation failed.', error);
		throw redirect(303, `/reset-password?error=invalid-link`);
	}

	event.cookies.set('contractor_password_recovery', '1', {
		path: '/',
		httpOnly: true,
		secure: event.url.protocol === 'https:',
		sameSite: 'lax',
		maxAge: 600
	});

	throw redirect(303, next);
}
