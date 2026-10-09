import type { SupabaseClient } from '@supabase/supabase-js';
import type { RequestEvent } from '@sveltejs/kit';
import type { z } from 'zod';
import type { Database } from '$lib/database.types';
import { validationError } from '$lib/server/api/errors';

// Jafar business management C2: what the calendar routes share.

type Client = SupabaseClient<Database>;

/** The body checked against a schema, or the response that refuses it with each field's message. */
export async function parseBody<Schema extends z.ZodType>(
	event: RequestEvent,
	schema: Schema
): Promise<{ ok: true; data: z.infer<Schema> } | { ok: false; response: Response }> {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return { ok: false, response: validationError({ form: 'Request body must be valid JSON.' }) };
	}
	const parsed = schema.safeParse(body);
	if (parsed.success) return { ok: true, data: parsed.data };
	const fieldErrors: Record<string, string> = {};
	for (const issue of parsed.error.issues)
		fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
	return { ok: false, response: validationError(fieldErrors) };
}

/**
 * Saves the browser's time zone as Jafar's when he has none yet, so "9am on the day" reminders mean his 9am from
 * the first thing he books. Never overwrites a chosen one.
 */
export async function adoptTimeZone(client: Client, zone: string | undefined) {
	if (!zone) return;
	const { data, error } = await client.rpc('owner_calendar_preferences');
	if (error) throw error;
	if ((data as { time_zone: string | null }).time_zone) return;
	const saved = await client.rpc('owner_calendar_save_preferences', { target_time_zone: zone });
	if (saved.error) throw saved.error;
}

/** The database's own refusals are already in plain words. */
export function isPlainRefusal(
	error: { code?: string } | null
): error is { code: string; message: string } {
	return error?.code === '22023';
}
