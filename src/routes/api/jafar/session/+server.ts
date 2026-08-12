import { json } from '@sveltejs/kit';
import { clearOwnerSession, setOwnerSession, verifyOwnerCredentials } from '$lib/server/auth/owner';
import { ownerLoginSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

export async function POST(event) {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please enter your email and password.' }, { status: 400 });
	}

	const parsed = ownerLoginSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		if (!verifyOwnerCredentials(parsed.data.email, parsed.data.password)) {
			return json({ error: 'The email or password is not correct.' }, { status: 401 });
		}

		setOwnerSession(event, parsed.data.email);
		return json({ ok: true });
	} catch (error) {
		console.error('Platform owner login is unavailable.', error);
		return json({ error: 'Platform owner login is not configured.' }, { status: 503 });
	}
}

export function DELETE(event) {
	clearOwnerSession(event);
	return json({ ok: true });
}
