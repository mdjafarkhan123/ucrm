import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

/**
 * Files an import's uploaded spreadsheet in the File Manager's Imports folder (Jafar, 2026-10-24: whatever a
 * business imports belongs to its Files, so it can manage it). The File is born pending and the ordinary
 * processing worker checks it like any upload. The import itself never depends on this: a failure is logged and
 * the import carries on, because the spreadsheet is already stored where the import reads it.
 */
export async function fileImportSpreadsheet(params: {
	organizationId: string;
	batchId: string;
	uploadedBy: string;
	sizeBytes: number;
}): Promise<void> {
	try {
		const { error } = await getOwnerSupabaseClient().rpc('register_import_file', {
			target_organization_id: params.organizationId,
			target_batch_id: params.batchId,
			target_uploaded_by: params.uploadedBy,
			target_size_bytes: params.sizeBytes
		});
		if (error) console.error('Could not file the import spreadsheet in Files.', error);
	} catch (error) {
		console.error('Could not file the import spreadsheet in Files.', error);
	}
}
