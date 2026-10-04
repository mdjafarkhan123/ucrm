// Client onboarding A5e: an add-another list (plan §2.1; the blueprint's "Structured" and "Repeatable"
// answers). Jafar names a few boxes each row holds — a service's name, note and season, or a person's name,
// role, email and phone — and how many rows a client may add; a list allowed one row is a plain form for one
// person or one address. Rows follow the MOJ "Add another" pattern: numbered, each with its own Remove.
//
// The answer travels and is stored as JSON: [{ id, values: { <box key>: <value> } }]. A row keeps its id so a
// later question can pick rows without copying them (A5f). Each box's value is checked by the same rule as a
// question of its type, which `$lib/setup/catalogue` supplies, so a box and a question can never disagree.

import type { SetupFileKind } from '$lib/setup/files';

/** The types a box in a row may have. Mirrors private.setup_list_fields_ok. */
export const SETUP_LIST_FIELD_KINDS = [
	'text',
	'longtext',
	'phone',
	'email',
	'url',
	'date',
	'number',
	'money',
	'yes_no',
	'choice',
	'file'
] as const;
export type SetupListFieldKind = (typeof SETUP_LIST_FIELD_KINDS)[number];

export const SETUP_LIST_FIELD_KIND_LABELS: Record<SetupListFieldKind, string> = {
	text: 'Short text',
	longtext: 'Long text',
	phone: 'Phone',
	email: 'Email',
	url: 'Web link',
	date: 'Date',
	number: 'Number',
	money: 'Money',
	yes_no: 'Yes / no',
	choice: 'Pick one',
	file: 'Photo or file'
};

export type SetupListField = {
	key: string;
	label: string;
	kind: SetupListFieldKind;
	required: boolean;
	/** `choice`: what the client picks from. */
	options?: { value: string; label: string }[];
	/** `file`: the kinds of file the box takes. It holds one file. */
	fileKinds?: SetupFileKind[];
};

/** The most boxes one row holds. */
export const SETUP_LIST_MAX_FIELDS = 8;

/** How many rows a list may take. Mirrors setup_items_max_rows_check; 1 is a plain form. */
export const SETUP_MAX_ROWS_CHOICES = [1, 3, 5, 10, 20, 50] as const;

export type SetupListRow = { id: string; values: Record<string, unknown> };

type Parsed<T> = { value: T; error: null } | { value: null; error: string };

/** Checks one box's text as a question of the box's type would be, and gives the value to store. */
export type SetupListCellCheck = (field: SetupListField, text: string) => Parsed<unknown>;

const ROW_ID = /^[a-z0-9-]{1,40}$/i;

/** A new row's id. Only unique within one answer, so a short random one is plenty. */
export function newSetupListRowId(): string {
	return crypto.randomUUID().slice(0, 8);
}

/** The text a box's stored value is checked as: a money amount or a number arrives as JSON or a number. */
export function setupListCellText(value: unknown): string {
	if (value === null || value === undefined) return '';
	if (typeof value === 'string') return value.trim();
	if (typeof value === 'number') return String(value);
	return JSON.stringify(value);
}

function json(raw: string): unknown {
	try {
		return JSON.parse(raw);
	} catch {
		return undefined;
	}
}

/** Where a row's problem is, for the person reading it: "Row 2, Email:" — or just "Email:" on a form. */
function where(maxRows: number, index: number, label?: string) {
	const row = maxRows === 1 ? '' : `Row ${index + 1}`;
	if (!label) return row;
	return row ? `${row}, ${label}:` : `${label}:`;
}

/**
 * A list answer: at least one row, at most `maxRows`, each naming only this list's boxes, with every required
 * box filled and every filled box valid. Empty boxes are left out of what is stored.
 */
export function parseSetupList(
	raw: string,
	rules: { fields: readonly SetupListField[]; maxRows: number },
	check: SetupListCellCheck
): Parsed<SetupListRow[]> {
	const fail = (error: string): Parsed<never> => ({ value: null, error });
	const list = json(raw);
	if (!Array.isArray(list) || list.length === 0)
		return fail(rules.maxRows === 1 ? 'Fill this in.' : 'Add at least one.');
	if (list.length > rules.maxRows)
		return fail(rules.maxRows === 1 ? 'Add one only.' : `Add up to ${rules.maxRows}.`);

	const keys = new Set(rules.fields.map((field) => field.key));
	const ids = new Set<string>();
	const rows: SetupListRow[] = [];
	for (const [index, item] of list.entries()) {
		const row = item as Partial<SetupListRow> | null;
		if (
			!row ||
			typeof row !== 'object' ||
			typeof row.id !== 'string' ||
			!ROW_ID.test(row.id) ||
			!row.values ||
			typeof row.values !== 'object' ||
			Array.isArray(row.values)
		)
			return fail('This list could not be read. Reload the page and try again.');
		if (ids.has(row.id)) return fail('A row is listed twice. Reload the page and try again.');
		ids.add(row.id);
		if (Object.keys(row.values).some((key) => !keys.has(key)))
			return fail('This list has changed. Reload the page and try again.');

		const values: Record<string, unknown> = {};
		for (const field of rules.fields) {
			const text = setupListCellText(row.values[field.key]);
			if (!text) {
				if (field.required)
					return fail(`${where(rules.maxRows, index, field.label)} fill this in.`);
				continue;
			}
			const parsed = check(field, text);
			if (parsed.error !== null)
				return fail(`${where(rules.maxRows, index, field.label)} ${parsed.error}`);
			values[field.key] = parsed.value;
		}
		if (Object.keys(values).length === 0)
			return fail(
				rules.maxRows === 1
					? 'Fill this in.'
					: `${where(rules.maxRows, index)} is empty. Fill it in or remove it.`
			);
		rows.push({ id: row.id, values });
	}
	return { value: rows, error: null };
}

/** The rows a stored answer's text holds, or an empty list when it holds none. */
export function setupListRows(raw: string | null | undefined): SetupListRow[] {
	if (!raw?.startsWith('[')) return [];
	const list = json(raw);
	if (!Array.isArray(list)) return [];
	return list.filter(
		(row): row is SetupListRow =>
			!!row &&
			typeof row === 'object' &&
			typeof row.id === 'string' &&
			!!row.values &&
			typeof row.values === 'object' &&
			!Array.isArray(row.values)
	);
}

/** The File ids the file boxes of a list's rows hold. */
export function setupListFileIds(
	rows: readonly SetupListRow[],
	fields: readonly SetupListField[]
): string[] {
	const fileKeys = fields.filter((field) => field.kind === 'file').map((field) => field.key);
	return rows.flatMap((row) =>
		fileKeys.flatMap((key) => {
			const id = row.values[key];
			return typeof id === 'string' && id ? [id] : [];
		})
	);
}

/** Starting boxes Jafar can pick for a new list, and then rename, add to or remove. */
export const SETUP_LIST_STARTERS: {
	key: string;
	label: string;
	fields: Omit<SetupListField, 'key'>[];
}[] = [
	{
		key: 'person',
		label: 'Person',
		fields: [
			{ label: 'Name', kind: 'text', required: true },
			{ label: 'Role', kind: 'text', required: false },
			{ label: 'Email', kind: 'email', required: false },
			{ label: 'Phone', kind: 'phone', required: false }
		]
	},
	{
		key: 'address',
		label: 'Address',
		fields: [
			{ label: 'Street address', kind: 'text', required: true },
			{ label: 'Town or city', kind: 'text', required: true },
			{ label: 'County, state or region', kind: 'text', required: false },
			{ label: 'Postcode or ZIP code', kind: 'text', required: false }
		]
	},
	{
		key: 'service',
		label: 'Service',
		fields: [
			{ label: 'Service name', kind: 'text', required: true },
			{ label: 'Short note', kind: 'longtext', required: false },
			{ label: 'Seasonal?', kind: 'yes_no', required: false }
		]
	},
	{
		key: 'link',
		label: 'Link + note',
		fields: [
			{ label: 'Web link', kind: 'url', required: true },
			{ label: 'Note', kind: 'text', required: false }
		]
	}
];
