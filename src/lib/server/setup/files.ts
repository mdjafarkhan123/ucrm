// Client onboarding A5c: the Files a photo or file answer holds (plan §2.1, ADR 0002). Every read here is
// scoped to one organization and to Files uploaded for setup, so an answer naming any other File — another
// organization's, or a library file — reads as one that does not exist.

import { json, redirect } from '@sveltejs/kit';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError } from '$lib/server/api/errors';
import {
	createPresignedDownloadUrl,
	createPresignedListImageUrl,
	createPresignedPreviewImageUrl
} from '$lib/server/storage/r2';

/** One file of a photo or file answer, as the setup page and Jafar's client page show it. */
export type SetupFileInfo = {
	id: string;
	name: string;
	mime_type: string;
	size_bytes: number;
	/** `removed`: trashed in the File library, or gone. */
	state: 'checking' | 'ready' | 'refused' | 'removed';
	/** A small preview of a ready photo; null for anything else. */
	thumb_url: string | null;
	/** Why a refused file was refused, in words for the client. */
	problem: string | null;
};

type SetupFileRow = {
	id: string;
	display_name: string;
	mime_type: string;
	size_bytes: number;
	processing_state: string;
	processing_error: string | null;
	trashed_at: string | null;
	object_key: string | null;
	thumbnail_object_key: string | null;
};

const COLUMNS =
	'id, display_name, mime_type, size_bytes, processing_state, processing_error, trashed_at, object_key, thumbnail_object_key';

/** The setup Files among `ids` that belong to the organization. At most 20 ids per answer, so one small read. */
async function readRows(organizationId: string, ids: readonly string[]): Promise<SetupFileRow[]> {
	if (ids.length === 0) return [];
	const { data, error } = await getOwnerSupabaseClient()
		.from('files')
		.select(COLUMNS)
		.eq('organization_id', organizationId)
		.eq('origin_role', 'setup_answer')
		.in('id', [...ids]);
	if (error) throw error;
	return data;
}

function stateOf(row: SetupFileRow | undefined): SetupFileInfo['state'] {
	if (!row || row.trashed_at || !row.object_key) return 'removed';
	if (row.processing_state === 'available') return 'ready';
	if (row.processing_state === 'pending') return 'checking';
	return 'refused';
}

/** The files named by `ids`, in that order. Throws when the database cannot be read. */
export async function readSetupFiles(
	organizationId: string,
	ids: readonly string[]
): Promise<SetupFileInfo[]> {
	const rows = new Map((await readRows(organizationId, ids)).map((row) => [row.id, row]));
	return Promise.all(
		ids.map(async (id): Promise<SetupFileInfo> => {
			const row = rows.get(id);
			const state = stateOf(row);
			return {
				id,
				name: row?.display_name ?? 'Removed file',
				mime_type: row?.mime_type ?? '',
				size_bytes: row?.size_bytes ?? 0,
				state,
				thumb_url:
					state === 'ready' && row?.thumbnail_object_key
						? await createPresignedListImageUrl(row.thumbnail_object_key).catch(() => null)
						: null,
				problem:
					state === 'refused'
						? row?.processing_state === 'quarantined'
							? 'Our virus check flagged this file, so it was not kept.'
							: (row?.processing_error ?? 'This file could not be accepted.')
						: null
			};
		})
	);
}

/**
 * The first of `ids` an answer may not hold — another organization's File, a library file, or one refused
 * or removed — or null when every one may be kept. A file still being checked may.
 */
export async function unusableSetupFile(
	organizationId: string,
	ids: readonly string[]
): Promise<string | null> {
	const rows = new Map((await readRows(organizationId, ids)).map((row) => [row.id, row]));
	return (
		ids.find((id) => {
			const state = stateOf(rows.get(id));
			return state === 'removed' || state === 'refused';
		}) ?? null
	);
}

/**
 * Sends the reader to one ready setup File: a photo opens in the browser, anything else downloads under its
 * own name. The link is minted per click and lasts minutes.
 */
export async function openSetupFile(organizationId: string, fileId: string): Promise<Response> {
	let rows: SetupFileRow[];
	try {
		rows = await readRows(organizationId, [fileId]);
	} catch (error) {
		console.error('Could not read a setup file.', error);
		return databaseError();
	}
	const row = rows[0];
	if (stateOf(row) !== 'ready' || !row.object_key)
		return json({ error: 'That file is not available.' }, { status: 404 });

	let url: string;
	try {
		// Only the raster types the upload check accepts start with image/; none of them can run code.
		url = row.mime_type.startsWith('image/')
			? await createPresignedPreviewImageUrl(row.object_key)
			: await createPresignedDownloadUrl(row.object_key, row.display_name);
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}
	redirect(303, url);
}
