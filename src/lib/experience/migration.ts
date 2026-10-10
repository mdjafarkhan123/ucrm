/**
 * Multi-industry foundation B10: what a business looked like at one moment, and what changed between two
 * moments. The database takes the inventory (`private.organization_inventory`); this only reads two of them.
 * It never sees a secret: customer links are counted, and record contents are compared by fingerprint.
 */

export type InventoryTable = { rows: number; ids: string | null; content: string };

export type InventoryLinkCount = { issued: number; usable: number };

export type InventorySummary = {
	organization: { id: string; slug: string; lifecycle_status: string } | null;
	current_agreement_id: string | null;
	members: Record<string, number>;
	customer_links: Record<string, InventoryLinkCount>;
	forms: { total: number; live: number };
	open_areas: string[];
	experience_path: 'experience' | 'previous_contractor';
};

export type Inventory = {
	taken_at: string;
	summary: InventorySummary;
	tables: Record<string, InventoryTable>;
};

/**
 * `lost` and `replaced` mean something the business had is gone or different, so they stop the next step.
 * `added` and `edited` are ordinary work that happened between the two moments, shown so nothing is hidden.
 */
export type ChangeKind = 'lost' | 'replaced' | 'added' | 'edited';

export type RecordChange = { table: string; kind: ChangeKind; before: number; after: number };

export type FactChange = { fact: string; before: string; after: string; stops: boolean };

export type MigrationComparison = {
	/** `same`: nothing differs. `changed`: only ordinary work was added or edited. `stop`: look before going on. */
	verdict: 'same' | 'changed' | 'stop';
	records: RecordChange[];
	facts: FactChange[];
	tables_compared: number;
	rows_before: number;
	rows_after: number;
};

const STOPPING: ReadonlySet<ChangeKind> = new Set(['lost', 'replaced']);

export const isStoppingChange = (kind: ChangeKind) => STOPPING.has(kind);

const names = (value: Record<string, number>) =>
	Object.keys(value)
		.sort()
		.map((key) => `${key} ${value[key]}`)
		.join(', ') || 'none';

function compareRecords(before: Inventory, after: Inventory): RecordChange[] {
	const changes: RecordChange[] = [];
	const tables = new Set([...Object.keys(before.tables), ...Object.keys(after.tables)]);
	for (const table of [...tables].sort()) {
		const was = before.tables[table];
		const now = after.tables[table];
		if (!was && now) {
			changes.push({ table, kind: 'added', before: 0, after: now.rows });
		} else if (was && !now) {
			changes.push({ table, kind: 'lost', before: was.rows, after: 0 });
		} else if (was && now) {
			if (now.rows < was.rows)
				changes.push({ table, kind: 'lost', before: was.rows, after: now.rows });
			else if (now.rows > was.rows)
				changes.push({ table, kind: 'added', before: was.rows, after: now.rows });
			else if (was.ids !== now.ids)
				changes.push({ table, kind: 'replaced', before: was.rows, after: now.rows });
			else if (was.content !== now.content)
				changes.push({ table, kind: 'edited', before: was.rows, after: now.rows });
		}
	}
	return changes;
}

function compareFacts(before: InventorySummary, after: InventorySummary): FactChange[] {
	const facts: FactChange[] = [];
	const note = (fact: string, was: string, now: string, stops: boolean) => {
		if (was !== now) facts.push({ fact, before: was, after: now, stops });
	};

	note(
		'Account status',
		before.organization?.lifecycle_status ?? 'unknown',
		after.organization?.lifecycle_status ?? 'unknown',
		true
	);
	note(
		'Agreement in force',
		before.current_agreement_id ?? 'none',
		after.current_agreement_id ?? 'none',
		true
	);
	note('Active team members', names(before.members), names(after.members), true);

	for (const kind of [
		...new Set([...Object.keys(before.customer_links), ...Object.keys(after.customer_links)])
	].sort()) {
		const was = before.customer_links[kind] ?? { issued: 0, usable: 0 };
		const now = after.customer_links[kind] ?? { issued: 0, usable: 0 };
		const label = `${kind.replace('_', ' ')} links`;
		note(`Issued ${label}`, String(was.issued), String(now.issued), now.issued < was.issued);
		note(`Usable ${label}`, String(was.usable), String(now.usable), now.usable < was.usable);
	}

	note(
		'Live forms',
		String(before.forms.live),
		String(after.forms.live),
		after.forms.live < before.forms.live
	);
	const lostAreas = before.open_areas.filter((area) => !after.open_areas.includes(area));
	note(
		'Open areas',
		before.open_areas.join(', ') || 'none',
		after.open_areas.join(', ') || 'none',
		lostAreas.length > 0
	);
	// Moving between the two paths is the point of a cutover or a recovery, so it is reported but never stops.
	note('Access path', before.experience_path, after.experience_path, false);
	return facts;
}

export function compareInventories(before: Inventory, after: Inventory): MigrationComparison {
	const records = compareRecords(before, after);
	const facts = compareFacts(before.summary, after.summary);
	const stops =
		records.some((change) => isStoppingChange(change.kind)) || facts.some((f) => f.stops);
	const total = (inventory: Inventory) =>
		Object.values(inventory.tables).reduce((sum, table) => sum + table.rows, 0);
	return {
		verdict: stops ? 'stop' : records.length || facts.length ? 'changed' : 'same',
		records,
		facts,
		tables_compared: new Set([...Object.keys(before.tables), ...Object.keys(after.tables)]).size,
		rows_before: total(before),
		rows_after: total(after)
	};
}

export type MigrationSnapshotMeta = {
	id: string;
	label: string;
	actor_email: string;
	taken_at: string;
	tables: number;
	rows: number;
	experience_path: 'experience' | 'previous_contractor';
};

export type MigrationPathChange = {
	id: string;
	path: 'experience' | 'previous_contractor';
	reason: string;
	actor_email: string;
	changed_at: string;
};

export type MigrationTabResponse = {
	/** The path in force. `experience` follows the confirmed profile, if there is one. */
	path: 'experience' | 'previous_contractor';
	path_history: MigrationPathChange[];
	snapshots: MigrationSnapshotMeta[];
	/** Present when two snapshots were asked for. */
	comparison?: {
		from: MigrationSnapshotMeta;
		to: MigrationSnapshotMeta;
		result: MigrationComparison;
	};
	error?: string;
};
