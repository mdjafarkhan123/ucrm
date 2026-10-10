import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	compareInventories,
	type Inventory,
	type MigrationPathChange,
	type MigrationSnapshotMeta,
	type MigrationTabResponse
} from '$lib/experience/migration';

type Client = SupabaseClient<Database>;

/**
 * Multi-industry foundation B10: Uplift's view of one business's migration. The database takes and keeps the
 * inventories and the access path; this reads them back, compares two, and asks the database to record
 * changes. Nothing here deletes or edits a business's records.
 */

type Path = 'experience' | 'previous_contractor';

const asPath = (value: string): Path =>
	value === 'previous_contractor' ? 'previous_contractor' : 'experience';

export async function loadExperiencePath(client: Client, organizationId: string): Promise<Path> {
	const { data, error } = await client
		.from('organization_experience_path_changes')
		.select('path')
		.eq('organization_id', organizationId)
		.order('changed_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (error) throw error;
	return data ? asPath(data.path) : 'experience';
}

function metaOf(row: {
	id: string;
	label: string;
	actor_email: string;
	taken_at: string;
	inventory: unknown;
}): MigrationSnapshotMeta {
	const inventory = row.inventory as Inventory;
	const tables = Object.values(inventory.tables ?? {});
	return {
		id: row.id,
		label: row.label,
		actor_email: row.actor_email,
		taken_at: row.taken_at,
		tables: tables.length,
		rows: tables.reduce((sum, table) => sum + table.rows, 0),
		experience_path: inventory.summary?.experience_path ?? 'experience'
	};
}

export async function loadMigrationTab(
	client: Client,
	organizationId: string,
	compare?: { from: string; to: string }
): Promise<MigrationTabResponse> {
	const [snapshots, changes] = await Promise.all([
		client
			.from('organization_migration_snapshots')
			.select('id, label, actor_email, taken_at, inventory')
			.eq('organization_id', organizationId)
			.order('taken_at', { ascending: false })
			.limit(50),
		client
			.from('organization_experience_path_changes')
			.select('id, path, reason, actor_email, changed_at')
			.eq('organization_id', organizationId)
			.order('changed_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(50)
	]);
	if (snapshots.error) throw snapshots.error;
	if (changes.error) throw changes.error;

	const path_history: MigrationPathChange[] = changes.data.map((row) => ({
		...row,
		path: asPath(row.path)
	}));
	const response: MigrationTabResponse = {
		path: path_history[0]?.path ?? 'experience',
		path_history,
		snapshots: snapshots.data.map(metaOf)
	};

	if (compare) {
		const from = snapshots.data.find((row) => row.id === compare.from);
		const to = snapshots.data.find((row) => row.id === compare.to);
		if (from && to) {
			response.comparison = {
				from: metaOf(from),
				to: metaOf(to),
				result: compareInventories(from.inventory as Inventory, to.inventory as Inventory)
			};
		}
	}
	return response;
}

export async function takeSnapshot(
	client: Client,
	organizationId: string,
	label: string,
	actorEmail: string
) {
	const { data, error } = await client.rpc('take_organization_migration_snapshot', {
		target_organization_id: organizationId,
		snapshot_label: label,
		actor_email: actorEmail
	});
	if (error) throw error;
	return data;
}

export async function recordPath(
	client: Client,
	organizationId: string,
	command: { path: Path; reason: string; idempotency_key: string },
	actorEmail: string
) {
	const { data, error } = await client.rpc('record_organization_experience_path', {
		target_organization_id: organizationId,
		target_path: command.path,
		change_reason: command.reason,
		actor_email: actorEmail,
		idempotency_key: command.idempotency_key
	});
	if (error) throw error;
	return data;
}
