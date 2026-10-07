import { json } from '@sveltejs/kit';
import { isOwnerEmail } from '$lib/server/auth/owner';
import { notFound, validationError } from '$lib/server/api/errors';
import type { LeadHistoryEntryInput } from '$lib/server/validation/lead.schema';
import type { HistoryEntry, HistoryPage } from '$lib/jafar/lead-history';

// Jafar business management B2: what the database's owner_lead_history returns, made ready for the page -- a
// name for whoever did each thing and an opaque cursor for "Show older".

type HistoryCursor = { occurred_at: string; id: string };

export type RawHistoryEntry = Omit<HistoryEntry, 'actor'> & {
	actor_email: string | null;
	actor_name: string | null;
};

export type RawHistoryPage = { entries: RawHistoryEntry[]; next_cursor: HistoryCursor | null };

export function encodeHistoryCursor(cursor: HistoryCursor): string {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function decodeHistoryCursor(value: string): HistoryCursor | null {
	try {
		const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
		if (
			parsed &&
			typeof parsed.occurred_at === 'string' &&
			!Number.isNaN(Date.parse(parsed.occurred_at)) &&
			typeof parsed.id === 'string' &&
			/^[0-9a-f-]{36}$/i.test(parsed.id)
		)
			return { occurred_at: parsed.occurred_at, id: parsed.id };
		return null;
	} catch {
		return null;
	}
}

/** The platform owner is "Jafar"; a teammate is their name, or their email if they never gave one. */
export function actorLabel(email: string | null, name: string | null): string | null {
	if (!email) return null;
	if (name) return name;
	return isOwnerEmail(email) ? 'Jafar' : email;
}

export function presentHistory(raw: RawHistoryPage): HistoryPage {
	return {
		entries: raw.entries.map(({ actor_email, actor_name, ...entry }) => ({
			...entry,
			actor: actorLabel(actor_email, actor_name)
		})),
		next_cursor: raw.next_cursor ? encodeHistoryCursor(raw.next_cursor) : null
	};
}

/** The table columns for a note or a logged contact; every other column stays empty, as the table requires. */
export function historyRowFor(entry: LeadHistoryEntryInput) {
	if (entry.kind === 'note')
		return {
			kind: 'note' as const,
			body: entry.body,
			occurred_at: undefined,
			contact_direction: null,
			contact_channel: null,
			contact_method_id: null,
			call_outcome: null
		};
	return {
		kind: 'contact' as const,
		body: entry.body,
		occurred_at: entry.occurred_at,
		contact_direction: entry.contact_direction,
		contact_channel: entry.contact_channel,
		contact_method_id: entry.contact_method_id,
		call_outcome: entry.call_outcome
	};
}

/** A refusal from the database, in words the form can show; null for anything unexpected. */
export function historyWriteError(error: { code?: string; message?: string }) {
	if (error.code === '23503') {
		// The composite key names the contact detail; the plain one names the Lead itself.
		if (error.message?.includes('platform_business_history_contact_method_fkey'))
			return validationError({
				contact_method_id: 'That contact detail is no longer on this Lead. Choose another.'
			});
		return notFound('This Lead no longer exists.');
	}
	if (error.code === '23514')
		return json(
			{ error: 'That entry is not complete. Check each field and try again.' },
			{ status: 422 }
		);
	return null;
}

/** What owner_lead_link_application answered, as the response the page acts on. */
export function linkResultResponse(result: string) {
	switch (result) {
		case 'linked':
		case 'unlinked':
		case 'unchanged':
			return json({ result });
		case 'linked_elsewhere':
			return json(
				{
					error:
						'This Application is already linked to another business. Unlink it there first if it belongs here.'
				},
				{ status: 409 }
			);
		case 'application_not_found':
			return notFound('This Application no longer exists.');
		default:
			return notFound('This Lead no longer exists.');
	}
}
