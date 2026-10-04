// Client onboarding B9a: protected setup documents — a phone bill for moving a number, a tax letter for texting
// registration (plan §§3.6, 9; supabase/migrations/20261018090000_setup_protected_documents.sql).
//
// Jafar's rules (2026-10-04): only the business owner and Jafar can open one; an administrator doing setup can
// upload one and sees that it arrived; every upload, opening and removal is recorded, and the owner and Jafar
// both see that list; it is deleted 90 days after the provider step it served is finished. The database holds
// these documents where no browser and no File library command can reach them, so every rule about who is
// asking is decided here, by the routes that call this module.

import { json, redirect } from '@sveltejs/kit';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError } from '$lib/server/api/errors';
import { createPresignedDownloadUrl, deleteObject } from '$lib/server/storage/r2';

/** One protected document as the setup page and Jafar's client page show it. */
export type ProtectedDocumentInfo = {
	id: string;
	name: string;
	size_bytes: number;
	/** `removed`: deleted, or not one of this question's documents. */
	state: 'uploading' | 'checking' | 'ready' | 'refused' | 'removed';
	/** Why a refused file was refused, in words for the client. */
	problem: string | null;
	uploaded_at: string | null;
	/** When it will be deleted, once Jafar has marked its provider step finished. */
	delete_after: string | null;
};

/** One line of a document's history. */
export type ProtectedDocumentEvent = {
	action:
		| 'uploaded'
		| 'refused'
		| 'opened'
		| 'removed'
		| 'deletion_scheduled'
		| 'deleted_by_uplift'
		| 'expired';
	who: string;
	at: string;
};

/** Who is acting: a member of the client's team, or Jafar for Uplift. */
export type ProtectedDocumentActor =
	{ kind: 'member'; userId: string; label: string } | { kind: 'uplift'; ownerEmail: string };

type DocumentRow = {
	id: string;
	fact_key: string;
	display_name: string;
	size_bytes: number;
	state: string;
	problem: string | null;
	upload_completed_at: string | null;
	delete_after: string | null;
};

const STORAGE_UNAVAILABLE = 'File storage is not available right now. Try again in a moment.';

// The generated types call every argument a string; these commands take null for "nobody".
const NONE = null as unknown as string;

function actorArgs(actor: ProtectedDocumentActor) {
	return actor.kind === 'member'
		? {
				target_actor_user_id: actor.userId,
				target_actor_label: actor.label,
				target_actor_owner_email: NONE
			}
		: {
				target_actor_user_id: NONE,
				target_actor_label: 'Uplift',
				target_actor_owner_email: actor.ownerEmail
			};
}

/** The name a member's actions show under: their profile name, or their email when they have none. */
export async function memberActorLabel(
	userId: string,
	email: string | null | undefined
): Promise<string> {
	const { data } = await getOwnerSupabaseClient()
		.from('profiles')
		.select('full_name')
		.eq('id', userId)
		.maybeSingle();
	return (data?.full_name?.trim() || email || 'A team member').slice(0, 200);
}

/** The organization's documents among `ids`, read as at most 20 rows. */
async function readRows(organizationId: string, ids: readonly string[]): Promise<DocumentRow[]> {
	if (ids.length === 0) return [];
	const { data, error } = await getOwnerSupabaseClient()
		.from('setup_protected_documents')
		.select(
			'id, fact_key, display_name, size_bytes, state, problem, upload_completed_at, delete_after'
		)
		.eq('organization_id', organizationId)
		.in('id', [...ids]);
	if (error) throw error;
	return data;
}

function stateOf(row: DocumentRow | undefined): ProtectedDocumentInfo['state'] {
	if (!row || row.state === 'deleted') return 'removed';
	return row.state as ProtectedDocumentInfo['state'];
}

/** The documents named by `ids`, in that order. Throws when the database cannot be read. */
export async function readProtectedDocuments(
	organizationId: string,
	ids: readonly string[]
): Promise<ProtectedDocumentInfo[]> {
	const rows = new Map((await readRows(organizationId, ids)).map((row) => [row.id, row]));
	return ids.map((id): ProtectedDocumentInfo => {
		const row = rows.get(id);
		const state = stateOf(row);
		return {
			id,
			name: row && state !== 'removed' ? row.display_name : 'Removed file',
			size_bytes: row?.size_bytes ?? 0,
			state,
			problem: state === 'refused' ? (row?.problem ?? 'This file could not be accepted.') : null,
			uploaded_at: row?.upload_completed_at ?? null,
			delete_after: state === 'removed' ? null : (row?.delete_after ?? null)
		};
	});
}

/**
 * The first of `ids` the answer to `factKey` may not hold — another organization's document, another
 * question's, one never finished, refused or removed — or null when every one may be kept. A document still
 * being checked may.
 */
export async function unusableProtectedDocument(
	organizationId: string,
	factKey: string,
	ids: readonly string[]
): Promise<string | null> {
	const rows = new Map((await readRows(organizationId, ids)).map((row) => [row.id, row]));
	return (
		ids.find((id) => {
			const row = rows.get(id);
			return !row || row.fact_key !== factKey || !['checking', 'ready'].includes(row.state);
		}) ?? null
	);
}

/**
 * Sends the reader to one ready document. The opening is recorded first, so no one sees a document without a
 * line in its history. Always a download under its own name, never shown in the page, and the link lasts
 * minutes.
 */
export async function openProtectedDocument(
	organizationId: string,
	documentId: string,
	actor: ProtectedDocumentActor
): Promise<Response> {
	const { data, error } = await getOwnerSupabaseClient().rpc('open_setup_protected_document', {
		target_document_id: documentId,
		target_organization_id: organizationId,
		...actorArgs(actor)
	});
	if (error) {
		console.error('Could not open a protected setup document.', error);
		return databaseError();
	}
	const found = data?.[0];
	if (!found) return json({ error: 'That file is not available.' }, { status: 404 });

	let url: string;
	try {
		url = await createPresignedDownloadUrl(found.object_key, found.display_name);
	} catch {
		return json({ error: STORAGE_UNAVAILABLE }, { status: 503 });
	}
	redirect(303, url);
}

/** Removes a document from storage for good; its row and history stay. Removing it again changes nothing. */
export async function deleteProtectedDocument(
	organizationId: string,
	documentId: string,
	actor: ProtectedDocumentActor
): Promise<Response> {
	const { data, error } = await getOwnerSupabaseClient().rpc('delete_setup_protected_document', {
		target_document_id: documentId,
		target_organization_id: organizationId,
		target_action: actor.kind === 'member' ? 'removed' : 'deleted_by_uplift',
		...actorArgs(actor)
	});
	if (error) {
		console.error('Could not remove a protected setup document.', error);
		return databaseError();
	}
	await removeStoredObjects((data ?? []).map((row) => row.object_key));
	return json({ removed: true }, { headers: { 'cache-control': 'no-store' } });
}

/** Jafar marks the provider step this document served finished: it is deleted 90 days from the first mark. */
export async function scheduleProtectedDocumentDeletion(
	organizationId: string,
	documentId: string,
	ownerEmail: string
): Promise<Response> {
	const { data, error } = await getOwnerSupabaseClient().rpc(
		'schedule_setup_protected_document_deletion',
		{
			target_document_id: documentId,
			target_organization_id: organizationId,
			target_actor_owner_email: ownerEmail
		}
	);
	if (error) {
		if (error.code === 'P0002')
			return json({ error: 'That file is not available.' }, { status: 404 });
		console.error('Could not schedule a protected setup document for deletion.', error);
		return databaseError();
	}
	return json({ delete_after: data.delete_after }, { headers: { 'cache-control': 'no-store' } });
}

/** A document's history, oldest first. Null when it is not this organization's. */
export async function readProtectedDocumentHistory(
	organizationId: string,
	documentId: string
): Promise<ProtectedDocumentEvent[] | null> {
	const client = getOwnerSupabaseClient();
	const { data: document, error: documentError } = await client
		.from('setup_protected_documents')
		.select('id')
		.eq('organization_id', organizationId)
		.eq('id', documentId)
		.maybeSingle();
	if (documentError) throw documentError;
	if (!document) return null;

	// Bounded by what can happen to one document: an upload, a check, its openings, one removal.
	const { data, error } = await client
		.from('setup_protected_document_events')
		.select('action, actor_label, created_at')
		.eq('document_id', documentId)
		.order('created_at')
		.order('id')
		.limit(500);
	if (error) throw error;
	return data.map((event) => ({
		action: event.action as ProtectedDocumentEvent['action'],
		who: event.actor_label,
		at: event.created_at
	}));
}

/**
 * Deletes objects whose rows the database has already let go. A failure is logged, not retried: the row no
 * longer points at the object, so nobody can open it, and failing would hold up every other deletion.
 */
export async function removeStoredObjects(
	objectKeys: readonly (string | null)[],
	removeObject: (objectKey: string) => Promise<void> = deleteObject
): Promise<number> {
	let deleted = 0;
	for (const key of objectKeys) {
		if (!key) continue;
		try {
			await removeObject(key);
			deleted += 1;
		} catch (error) {
			console.error('Could not delete a protected setup document from storage.', {
				objectKey: key,
				error: error instanceof Error ? error.message : error
			});
		}
	}
	return deleted;
}
