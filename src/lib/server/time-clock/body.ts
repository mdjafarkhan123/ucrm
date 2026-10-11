import { validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { emptyTimerCommandSchema } from '$lib/server/validation/time-clock.schema';

// Stop, Clock in and Clock out carry nothing: they always mean the signed-in person's own timer. No body or
// an empty object passes (null); anything else is refused with the response to send, so a caller that
// thinks it can name a timer or a person finds out.
export async function refuseTimerCommandBody(request: Request): Promise<Response | null> {
	const text = await request.text();
	if (!text.trim()) return null;

	let body: unknown;
	try {
		body = JSON.parse(text);
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = emptyTimerCommandSchema.safeParse(body);
	return parsed.success ? null : validationError(zodFieldErrors(parsed.error));
}
