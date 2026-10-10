import type { SupabaseClient } from '@supabase/supabase-js';
import type { RequestEvent } from '@sveltejs/kit';
import type { z } from 'zod';
import type { Database } from '$lib/database.types';
import { validationError } from '$lib/server/api/errors';
import type { OwnerSession } from '$lib/server/auth/owner';
import { canUseJafarPath } from '$lib/jafar/team-access';

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
 * D3b: whose calendar this is -- the teammate's member id, or undefined for Jafar (the database's default) -- and
 * whether they may work on calls. Calls belong to Leads, so booking, moving, editing and closing one follows the
 * Leads & Deals area; Busy blocks are everyone's own and the database keeps each to its owner.
 */
export function calendarViewer(session: OwnerSession) {
	return {
		memberId: session.memberId ?? undefined,
		canSeeCalls: canUseJafarPath(session, '/api/jafar/leads'),
		canWorkCalls: canUseJafarPath(session, '/api/jafar/leads/x', 'PATCH')
	};
}

/** Refuses a teammate a call they may not work on. */
export const CALLS_REFUSED = 'Your access does not include changing calls.';

/**
 * Saves the browser's time zone as the person's own when they have none yet, so "9am on the day" reminders mean
 * their 9am from the first thing they book. Never overwrites a chosen one.
 */
export async function adoptTimeZone(
	client: Client,
	zone: string | undefined,
	memberId: string | undefined
) {
	if (!zone) return;
	const { data, error } = await client.rpc('owner_calendar_preferences', {
		viewer_member_id: memberId
	});
	if (error) throw error;
	if ((data as { time_zone: string | null }).time_zone) return;
	const saved = await client.rpc('owner_calendar_save_preferences', {
		target_time_zone: zone,
		viewer_member_id: memberId
	});
	if (saved.error) throw saved.error;
}

/** The database's own refusals are already in plain words. */
export function isPlainRefusal(
	error: { code?: string } | null
): error is { code: string; message: string } {
	return error?.code === '22023';
}

/** E3/E4a: a call when this person may see it: their own, or any call when they can open Leads. */
export async function visibleCall(
	client: Client,
	id: string,
	memberId: string | undefined,
	all: boolean
) {
	const { data, error } = await client.rpc('owner_calendar_entry', { target_id: id });
	if (error) throw error;
	const entry = data as { kind: string; owner_member_id: string | null } | null;
	if (!entry || entry.kind !== 'call') return false;
	return all || entry.owner_member_id === (memberId ?? null);
}
