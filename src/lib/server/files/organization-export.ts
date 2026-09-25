// Files and Media, Part 8B: the organization export worker.
//
// Builds one zip -- manifest.json plus every available File's blob -- and streams it into R2 as archiver
// produces it (uploadStream/Upload, storage/r2.ts), so the zip itself is never buffered whole no matter how
// large the organization's library is. Each File's own bytes ARE read into memory one at a time before being
// appended, which is safe only because files_size_bytes_check already caps a single File at 25 MB
// (20260921160000_files_media_central_catalog.sql) -- buffering one bounded File at a time is far simpler
// than coordinating archiver's internal queue against a live R2 GetObject stream's connection lifecycle, and
// costs at most ~25 MB of memory regardless of how many Files the export contains.
//
// Runs on its own five-minute cron (files-export-worker-wake-five-minutes,
// 20260925140000_files_media_organization_export.sql), not the one-minute upload-processing wake, because a
// build can run far longer than that cron's 60-second timeout.
//
// Known limitation, accepted for now: one invocation builds the whole export in one pass, with no
// resumption across cron ticks if the process restarts mid-build (the claimed row is simply left
// 'processing' and never retried automatically). Fine at today's realistic org sizes; not load-tested at the
// scale Part 7B-3 proved for *listing* Files, which is a very different cost shape than reading and
// re-zipping every one of them.

import type { Readable } from 'node:stream';
import type { SupabaseClient } from '@supabase/supabase-js';
import { ZipArchive, type ArchiverError } from 'archiver';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { sendTransactionalEmail } from '$lib/server/email/brevo';
import {
	buildOrganizationExportObjectKey,
	deleteObject,
	getObjectBytes,
	uploadStream
} from '$lib/server/storage/r2';
import type { Database } from '$lib/database.types';

type Supabase = SupabaseClient<Database>;

const EXPORT_TTL_DAYS = 7;
const MANIFEST_SCHEMA_VERSION = 1;

// Same three lines as marketing/dispatcher.ts's appOrigin() -- not imported from there, since Files has no
// reason to depend on Marketing's module. A cron-triggered job has no browser request to read an origin
// from, so this is the one place besides that dispatcher that needs the app's own configured URL.
function appOrigin(): string {
	const raw = env.APP_URL?.trim();
	if (!raw)
		throw new Error('APP_URL must be set before an organization export can notify its owner.');
	return new URL(raw).origin;
}

function sanitizeZipEntryName(name: string): string {
	const cleaned = name
		.trim()
		.replace(/[\\/]+/g, '_')
		.replace(/[^a-zA-Z0-9._ -]+/g, '_');
	return cleaned.slice(0, 180) || 'file';
}

type ExportableFile = {
	id: string;
	display_name: string;
	mime_type: string;
	kind: string | null;
	size_bytes: number;
	checksum_sha256: string | null;
	object_key: string | null;
	created_at: string;
	trashed_at: string | null;
	folder: { name: string } | { name: string }[] | null;
};

type ExportableLink = {
	file_id: string;
	entity_type: string;
	entity_id: string;
	role: string;
	protected: boolean;
};

function folderName(folder: ExportableFile['folder']): string | null {
	if (!folder) return null;
	return Array.isArray(folder) ? (folder[0]?.name ?? null) : folder.name;
}

async function loadOrganizationFiles(
	client: Supabase,
	organizationId: string
): Promise<{ files: ExportableFile[]; links: ExportableLink[] }> {
	const [filesResult, linksResult] = await Promise.all([
		client
			.from('files')
			.select(
				'id, display_name, mime_type, kind, size_bytes, checksum_sha256, object_key, created_at, trashed_at, folder:file_folders(name)'
			)
			.eq('organization_id', organizationId)
			.eq('processing_state', 'available')
			.order('created_at', { ascending: true }),
		client
			.from('file_links')
			.select('file_id, entity_type, entity_id, role, protected')
			.eq('organization_id', organizationId)
	]);

	if (filesResult.error)
		throw new Error(`Could not read Files for export: ${filesResult.error.message}`);
	if (linksResult.error)
		throw new Error(`Could not read File links for export: ${linksResult.error.message}`);

	return {
		files: (filesResult.data ?? []) as unknown as ExportableFile[],
		links: (linksResult.data ?? []) as ExportableLink[]
	};
}

function buildManifest(
	organizationId: string,
	files: ExportableFile[],
	links: ExportableLink[],
	generatedAt: Date
) {
	const linksByFile = new Map<string, ExportableLink[]>();
	for (const link of links) {
		const existing = linksByFile.get(link.file_id);
		if (existing) existing.push(link);
		else linksByFile.set(link.file_id, [link]);
	}

	return {
		export_type: 'organization_files',
		schema_version: MANIFEST_SCHEMA_VERSION,
		organization_id: organizationId,
		generated_at: generatedAt.toISOString(),
		file_count: files.length,
		files: files.map((file) => ({
			id: file.id,
			display_name: file.display_name,
			mime_type: file.mime_type,
			kind: file.kind,
			size_bytes: file.size_bytes,
			checksum_sha256: file.checksum_sha256,
			folder: folderName(file.folder),
			created_at: file.created_at,
			trashed_at: file.trashed_at,
			// A File trashed 30+ days ago has had its blob permanently cleared (Part 8A) -- it is still
			// listed here, with no entry in files/, so this manifest keeps a permanent record even after
			// the object itself is gone, the same call Jafar made for the customer-facing placeholder.
			blob_included: file.object_key !== null,
			links: (linksByFile.get(file.id) ?? []).map((link) => ({
				entity_type: link.entity_type,
				entity_id: link.entity_id,
				role: link.role,
				protected: link.protected
			}))
		}))
	};
}

export type OrganizationExportJob = {
	id: string;
	organization_id: string;
	requested_by: string | null;
};

export type OrganizationExportDependencies = {
	client?: Supabase;
	readFileBytes?: (objectKey: string) => Promise<Uint8Array>;
	writeZipStream?: (objectKey: string, body: Readable, mimeType: string) => Promise<void>;
	removeObject?: (objectKey: string) => Promise<void>;
	notifyOwner?: (params: { organizationId: string; requestedBy: string | null }) => Promise<void>;
};

// Pure-ish assembly: reads every available File's bytes in turn and appends them to a zip that streams
// straight into R2. Returns the finished object's key and its real (compressed) size.
async function buildAndUploadExport(
	client: Supabase,
	job: OrganizationExportJob,
	readFileBytes: (objectKey: string) => Promise<Uint8Array>,
	writeZipStream: (objectKey: string, body: Readable, mimeType: string) => Promise<void>
): Promise<{ objectKey: string; fileCount: number; totalBytes: number }> {
	const { files, links } = await loadOrganizationFiles(client, job.organization_id);
	const manifest = buildManifest(job.organization_id, files, links, new Date());

	const archive = new ZipArchive({ zlib: { level: 6 } });
	const objectKey = buildOrganizationExportObjectKey(job.organization_id);

	const uploadPromise = writeZipStream(objectKey, archive, 'application/zip');
	archive.on('warning', (warning: ArchiverError) =>
		console.warn('Organization export zip warning.', warning)
	);

	archive.append(JSON.stringify(manifest, null, 2), { name: 'manifest.json' });

	const seenNames = new Map<string, number>();
	for (const file of files) {
		if (!file.object_key) continue; // purged -- listed in the manifest, no blob to include
		const bytes = await readFileBytes(file.object_key);
		const base = sanitizeZipEntryName(`${file.id}-${file.display_name}`);
		const count = seenNames.get(base) ?? 0;
		seenNames.set(base, count + 1);
		const entryName = count === 0 ? base : `${base}-${count}`;
		archive.append(Buffer.from(bytes), { name: `files/${entryName}` });
	}

	await archive.finalize();
	await uploadPromise;

	return { objectKey, fileCount: files.length, totalBytes: archive.pointer() };
}

async function defaultNotifyOwner(params: {
	organizationId: string;
	requestedBy: string | null;
}): Promise<void> {
	if (!params.requestedBy) return; // the requester's own account was removed since they asked

	const client = getOwnerSupabaseClient();
	const { data: userData, error: userError } = await client.auth.admin.getUserById(
		params.requestedBy
	);
	if (userError || !userData?.user?.email) {
		console.error('Could not find the owner to notify about their organization export.', {
			organizationId: params.organizationId,
			error: userError?.message
		});
		return;
	}

	const link = new URL('/files', appOrigin());
	await sendTransactionalEmail({
		to: { email: userData.user.email },
		subject: 'Your organization export is ready',
		textContent: `Your complete export is ready to download. Sign in and open Files: ${link.toString()}. The download link there expires in ${EXPORT_TTL_DAYS} days.`,
		htmlContent: `<p>Your complete export is ready to download.</p><p><a href="${link.toString()}">Open Files</a> and use Export everything again to get the download link.</p><p>It expires in ${EXPORT_TTL_DAYS} days.</p>`
	});
}

export type OrganizationExportWorkerResult = { processed: 0 | 1; outcome?: 'available' | 'failed' };

export async function runOrganizationExportWorker(
	dependencies: OrganizationExportDependencies = {}
): Promise<OrganizationExportWorkerResult> {
	const client = dependencies.client ?? getOwnerSupabaseClient();
	const readFileBytes = dependencies.readFileBytes ?? getObjectBytes;
	const writeZipStream = dependencies.writeZipStream ?? uploadStream;
	const notifyOwner = dependencies.notifyOwner ?? defaultNotifyOwner;

	const { data, error } = await client.rpc('claim_next_organization_export');
	if (error) throw new Error(`Could not claim an organization export: ${error.message}`);
	const job = (data ?? [])[0];
	if (!job) return { processed: 0 };

	try {
		const { objectKey, fileCount, totalBytes } = await buildAndUploadExport(
			client,
			job,
			readFileBytes,
			writeZipStream
		);
		const expiresAt = new Date(Date.now() + EXPORT_TTL_DAYS * 24 * 60 * 60 * 1000).toISOString();

		const { error: finalizeError } = await client.rpc('finalize_organization_export', {
			target_export_id: job.id,
			target_state: 'available',
			target_object_key: objectKey,
			target_file_count: fileCount,
			target_total_bytes: totalBytes,
			target_expires_at: expiresAt
		});
		if (finalizeError)
			throw new Error(`Could not mark an organization export available: ${finalizeError.message}`);

		await notifyOwner({ organizationId: job.organization_id, requestedBy: job.requested_by });
		return { processed: 1, outcome: 'available' };
	} catch (error) {
		const message = error instanceof Error ? error.message : 'The export could not be built.';
		console.error('An organization export failed to build.', { jobId: job.id, error: message });

		const { error: finalizeError } = await client.rpc('finalize_organization_export', {
			target_export_id: job.id,
			target_state: 'failed',
			target_error: message.slice(0, 300)
		});
		if (finalizeError)
			console.error('Could not even mark the export failed.', {
				jobId: job.id,
				error: finalizeError.message
			});

		return { processed: 1, outcome: 'failed' };
	}
}

export type OrganizationExportPurgeResult = { purged: number; objectsDeleted: number };

// The cheap half of Part 8B: clears an expired export's zip from R2. Runs on the existing one-minute sweep
// (processing-worker.ts), matching how Part 8A's Trash purge shares that cadence rather than the heavy
// build's own five-minute one.
export async function sweepExpiredOrganizationExports(
	dependencies: Pick<OrganizationExportDependencies, 'client' | 'removeObject'> = {}
): Promise<OrganizationExportPurgeResult> {
	const client = dependencies.client ?? getOwnerSupabaseClient();
	const removeObject = dependencies.removeObject ?? deleteObject;

	const { data, error } = await client.rpc('purge_expired_organization_exports', {
		batch_size: 20
	});
	if (error) throw new Error(`Could not purge expired organization exports: ${error.message}`);
	const rows = (data ?? []) as { object_key: string | null }[];

	let objectsDeleted = 0;
	for (const row of rows) {
		if (!row.object_key) continue;
		try {
			await removeObject(row.object_key);
			objectsDeleted += 1;
		} catch (deleteError) {
			console.error('Could not delete an expired organization export object.', {
				objectKey: row.object_key,
				error: deleteError instanceof Error ? deleteError.message : deleteError
			});
		}
	}

	return { purged: rows.length, objectsDeleted };
}
