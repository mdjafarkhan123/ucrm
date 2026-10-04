// Client onboarding B9a: the virus check and clean-up for protected setup documents. The same single pass as
// every File (src/lib/server/files/processing-worker.ts) — size, file signature and malware scan from one read
// of the object — but a refused document leaves storage at once, and nothing is ever made to preview it.
// Runs from the files processing worker's tick.

import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { deleteObject } from '$lib/server/storage/r2';
import {
	defaultMeasureObject,
	defaultReadObject,
	inspect,
	type FileProcessingDependencies,
	type FileWorkerClient
} from '$lib/server/files/processing-worker';
import {
	ScannerUnavailableError,
	openScanSession,
	scannerIsConfigured
} from '$lib/server/files/scanner';
import { removeStoredObjects } from './protected-documents';

type ClaimedDocument = {
	id: string;
	organization_id: string;
	display_name: string;
	size_bytes: number;
	object_key: string;
	claim_token: string;
};

export type ProtectedDocumentCheckResult = {
	claimed: number;
	ready: number;
	refused: number;
	deferred: number;
};

const BATCH_SIZE = 10;

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

export async function runProtectedDocumentChecks(
	dependencies: FileProcessingDependencies = {}
): Promise<ProtectedDocumentCheckResult> {
	const client: FileWorkerClient =
		dependencies.client ?? (getOwnerSupabaseClient() as unknown as FileWorkerClient);
	const readObject = dependencies.readObject ?? defaultReadObject;
	const measureObject = dependencies.measureObject ?? defaultMeasureObject;
	const removeObject = dependencies.removeObject ?? deleteObject;
	const startScan = dependencies.startScan ?? openScanSession;
	const hasScanner = dependencies.hasScanner ?? scannerIsConfigured;

	const result: ProtectedDocumentCheckResult = { claimed: 0, ready: 0, refused: 0, deferred: 0 };

	// Without a scanner nothing is claimed: the document stays "being checked" rather than being trusted unchecked.
	if (!hasScanner()) return result;

	const claimed = await client.rpc('claim_setup_protected_documents', { batch_size: BATCH_SIZE });
	if (claimed.error) throw rpcError('Could not claim protected documents', claimed.error);
	const documents = Array.isArray(claimed.data) ? (claimed.data as ClaimedDocument[]) : [];
	result.claimed = documents.length;

	// One at a time, as for Files: each is a whole object read and scan on the container serving the app.
	for (const document of documents) {
		let outcome: Awaited<ReturnType<typeof inspect>>;
		try {
			const actualSize = await measureObject(document.object_key);
			outcome = await inspect(
				document,
				actualSize,
				await readObject(document.object_key),
				startScan,
				{
					preview: false
				}
			);
		} catch (error) {
			result.deferred += 1;
			if (error instanceof ScannerUnavailableError) {
				const released = await client.rpc('release_setup_protected_document_claim', {
					target_document_id: document.id,
					target_claim_token: document.claim_token
				});
				if (released.error) throw rpcError('Could not release a document claim', released.error);
				continue;
			}
			// Storage could not produce the object. The claim times out and retries; after five tries the
			// sweep deletes it.
			console.error('Could not read a protected setup document for checking.', {
				documentId: document.id,
				error: error instanceof Error ? error.message : error
			});
			continue;
		}

		const clean = outcome.verdict.ok && outcome.scan?.clean === true;
		if (outcome.verdict.ok && outcome.scan && !outcome.scan.clean)
			// The signature name is logged for us and never stored or shown.
			console.warn('A protected setup document was refused by the malware scanner.', {
				documentId: document.id,
				organizationId: document.organization_id,
				signature: outcome.scan.signature
			});

		const finished = await client.rpc('finish_setup_protected_document_check', {
			target_document_id: document.id,
			target_claim_token: document.claim_token,
			target_ready: clean,
			target_checksum_sha256: outcome.checksum,
			target_problem: clean
				? null
				: outcome.verdict.ok
					? 'This file was flagged as unsafe, so it was deleted.'
					: outcome.verdict.reason
		});
		if (finished.error) throw rpcError('Could not finish a document check', finished.error);

		if (clean) {
			result.ready += 1;
		} else {
			result.refused += 1;
			const rows = Array.isArray(finished.data) ? (finished.data as { object_key: string }[]) : [];
			await removeStoredObjects(
				rows.map((row) => row.object_key),
				removeObject
			);
		}
	}

	return result;
}

export type ProtectedDocumentSweepResult = { deleted: number; objectsDeleted: number };

// Deletes what is due: past its deletion date, never finished uploading, never held by its answer, or
// impossible to check. The database decides and hands back the keys; this only deletes the objects.
export async function sweepProtectedDocuments(
	dependencies: FileProcessingDependencies = {}
): Promise<ProtectedDocumentSweepResult> {
	const client: FileWorkerClient =
		dependencies.client ?? (getOwnerSupabaseClient() as unknown as FileWorkerClient);
	const removeObject = dependencies.removeObject ?? deleteObject;

	const swept = await client.rpc('sweep_setup_protected_documents', { batch_size: 100 });
	if (swept.error) throw rpcError('Could not sweep protected documents', swept.error);
	const rows = Array.isArray(swept.data) ? (swept.data as { object_key: string | null }[]) : [];
	const objectsDeleted = await removeStoredObjects(
		rows.map((row) => row.object_key),
		removeObject
	);
	return { deleted: rows.length, objectsDeleted };
}
