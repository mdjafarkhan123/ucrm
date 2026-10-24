import { json } from '@sveltejs/kit';
import { databaseError, notFound } from '$lib/server/api/errors';

/**
 * Data privacy Part 6: the database owns delete and restore (`delete_clients`, `restore_client_deletions`);
 * this turns its refusals into the answers the pop-ups read. Plan: docs/data-privacy-deletion-behavior-contract.md
 * § Deleting a customer.
 */
export function deletionFailure(error: { code?: string; message?: string }) {
	if (error.code === '42501') return json({ error: error.message }, { status: 403 });
	if (error.code === 'P0002') return notFound(error.message ?? 'That client could not be found.');
	if (error.code === '22023' || error.code === '55000') {
		return json({ error: error.message }, { status: 422 });
	}
	console.error('A client delete or restore failed.', error);
	return databaseError();
}
