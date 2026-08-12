import { json } from '@sveltejs/kit';
import {
	passwordResetRequestSchema,
	passwordUpdateSchema,
	zodAuthFieldErrors
} from '$lib/server/validation/auth.schema';

export async function POST(event) {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Enter the email address for your contractor account.' }, { status: 400 });
	}

	const parsed = passwordResetRequestSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the highlighted field.', field_errors: zodAuthFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const { error } = await event.locals.supabase.auth.resetPasswordForEmail(parsed.data.email, {
		redirectTo: `${event.url.origin}/auth/confirm?next=/reset-password`
	});
	if (error) console.error('Contractor password reset request failed.', error);

	// Keep this response identical for existing and unknown addresses.
	return json({ ok: true });
}

export async function PATCH(event) {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please enter and confirm your new password.' }, { status: 400 });
	}

	const parsed = passwordUpdateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the highlighted fields.', field_errors: zodAuthFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const user = await event.locals.getUser();
	if (!user) return json({ error: 'Your password-reset link is invalid or has expired.' }, { status: 401 });

	const { password, password_confirmation: _, current_password } = parsed.data;
	if (!current_password && event.cookies.get('contractor_password_recovery') !== '1') {
		return json({ error: 'Confirm your current password before changing it.' }, { status: 403 });
	}
	const { error } = await event.locals.supabase.auth.updateUser({
		password,
		...(current_password ? { current_password } : {})
	});
	if (error) {
		console.error('Contractor password update failed.', error);
		return json({ error: 'We could not update your password. Check your current password and try again.' }, { status: 400 });
	}
	if (!current_password) {
		event.cookies.delete('contractor_password_recovery', { path: '/' });
	}

	return json({ ok: true });
}
