import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import type { z } from 'zod';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';

// Every draft command is the same six steps: check the permission, read the body, validate it, call the
// one database function allowed to write these rows, translate its refusal, and answer with no-store.
// Written once here so a new rail dialog is a schema and four lines of route, and so none of them can
// quietly skip the revision check or cache their own answer.
export async function runQuoteCommand<Schema extends z.ZodTypeAny>(
	event: RequestEvent,
	schema: Schema,
	command: (
		input: z.infer<Schema>,
		quoteId: string
	) => { name: string; args: Record<string, unknown> }
) {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = schema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { name, args } = command(parsed.data, event.params.id as string);
	// The generated types name every function individually; this helper is the one place that speaks to
	// all of them, so the client is widened here rather than the call at each route. It stays a method
	// call on purpose: pulling `rpc` out into its own variable loses the client it belongs to, and
	// supabase-js throws on its own internals the moment it is called that way.
	const supabase = event.locals.supabase as unknown as {
		rpc: (
			fn: string,
			params: Record<string, unknown>
		) => Promise<{ data: unknown; error: { code?: string; message?: string } | null }>;
	};
	const { data, error } = await supabase.rpc(name, args);

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
}
