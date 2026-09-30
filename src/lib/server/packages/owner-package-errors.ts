import { json } from '@sveltejs/kit';

// The draft commands raise plain-English messages: P0002 for a package or draft that is gone, and the
// constraint codes for a refused change. Anything else is unexpected and rethrown.
export function ownerPackageCommandError(error: { code?: string; message: string }) {
	if (error.code === 'P0002') return json({ error: error.message }, { status: 404 });
	if (error.code && ['23503', '23505', '23514'].includes(error.code)) {
		return json({ error: error.message }, { status: 409 });
	}
	return null;
}
