import { json } from '@sveltejs/kit';
import { contractorLoginSchema, zodAuthFieldErrors } from '$lib/server/validation/auth.schema';

export async function POST(event) {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please enter your email and password.' }, { status: 400 });
	}

	const parsed = contractorLoginSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodAuthFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const { error } = await event.locals.supabase.auth.signInWithPassword(parsed.data);
	if (error) {
		return json({ error: 'The email or password is not correct.' }, { status: 401 });
	}

	return json({ ok: true });
}

export async function DELETE(event) {
	const { error } = await event.locals.supabase.auth.signOut();
	if (error) {
		console.error('Contractor sign out failed.', error);
		return json({ error: 'We could not sign you out. Please try again.' }, { status: 500 });
	}

	return json({ ok: true });
}
