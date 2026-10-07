import { json } from '@sveltejs/kit';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import type { z } from 'zod';

// Jafar business management B3: the parts every approval route shares.

const LEAD_NOT_FOUND = 'This Lead no longer exists.';

/** The request body checked against `schema`, or the response to send back instead. */
export async function readBody<Schema extends z.ZodType>(
	request: Request,
	schema: Schema
): Promise<{ data: z.infer<Schema> } | { response: Response }> {
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return { response: validationError({ form: 'Request body must be valid JSON.' }) };
	}
	const parsed = schema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return { response: validationError(fieldErrors) };
	}
	return { data: parsed.data };
}

/**
 * What the database answered. Its own refusals (errcode 22023, e.g. "This business asked not to be contacted.")
 * are already in words for Jafar; 'lead_not_found' means the Lead was deleted meanwhile.
 */
export function approvalResponse(
	result: { data: unknown; error: { code?: string; message?: string } | null },
	what: string
) {
	if (result.error) {
		if (result.error.code === '22023')
			return validationError({ form: result.error.message ?? 'That change is not allowed.' }, 409);
		console.error(`Could not ${what}.`, result.error);
		return databaseError();
	}
	if (result.data === 'lead_not_found') return notFound(LEAD_NOT_FOUND);
	return json({ result: result.data });
}

export { LEAD_NOT_FOUND };
