import { describe, expect, it } from 'vitest';
import {
	buildSetupCatalogue,
	catalogueFacts,
	setupValueError,
	storedSetupValue,
	type SetupFact
} from './catalogue';
import { setupListFileIds, setupListRows, type SetupListField } from './lists';

const FILE_ID = '0f8fad5b-d9cb-469f-a165-70867728950e';

// A list question as the published version returns it, read through the catalogue so the test covers the same
// path the page and the server use.
function listFact(fields: unknown[], maxRows: number): SetupFact {
	const catalogue = buildSetupCatalogue({
		version_id: 'v',
		stages: [
			{
				key: 'extra',
				title: 'Extra',
				description: '',
				service_key: null,
				items: [
					{
						type: 'question',
						fact_key: 'extra.list',
						label: 'List',
						hint: null,
						built_in: false,
						required: true,
						can_defer: false,
						kind: 'list',
						options: null,
						list_fields: fields as never,
						max_rows: maxRows,
						max_length: null
					}
				]
			}
		]
	});
	return catalogueFacts(catalogue).get('extra.list')!;
}

const services = listFact(
	[
		{ key: 'name', label: 'Service name', kind: 'text', required: true },
		{ key: 'note', label: 'Short note', kind: 'longtext', required: false },
		{ key: 'seasonal', label: 'Seasonal?', kind: 'yes_no', required: false },
		{ key: 'from', label: 'Price from', kind: 'money', required: false },
		{ key: 'site', label: 'Page', kind: 'url', required: false },
		{
			key: 'photo',
			label: 'Photo',
			kind: 'file',
			required: false,
			file_kinds: ['photo']
		}
	],
	3
);

const rows = (...items: { id: string; values: Record<string, unknown> }[]) => JSON.stringify(items);

describe('add-another lists (A5e)', () => {
	it('reads its boxes and row limit from the published version', () => {
		expect(services).toMatchObject({ kind: 'list', maxRows: 3 });
		expect(services.listFields?.[5]).toEqual({
			key: 'photo',
			label: 'Photo',
			kind: 'file',
			required: false,
			fileKinds: ['photo']
		});
	});

	it('saves rows, leaving out empty boxes and storing each box as its own type would be', () => {
		const value = rows(
			{
				id: 'a1',
				values: {
					name: ' Roof repair ',
					note: '',
					seasonal: 'yes',
					from: '{"amount":"150","currency":"GBP"}',
					site: 'example.com/roofs',
					photo: FILE_ID.toUpperCase()
				}
			},
			{ id: 'b2', values: { name: 'Gutters' } }
		);
		expect(setupValueError(services, value)).toBeNull();
		expect(storedSetupValue(services, value)).toEqual([
			{
				id: 'a1',
				values: {
					name: 'Roof repair',
					seasonal: 'yes',
					from: { amount: '150', currency: 'GBP' },
					site: 'https://example.com/roofs',
					photo: FILE_ID
				}
			},
			{ id: 'b2', values: { name: 'Gutters' } }
		]);
	});

	it('reloads a stored answer unchanged', () => {
		const stored = storedSetupValue(
			services,
			rows({ id: 'a1', values: { name: 'Roofs', from: '{"amount":"99.50","currency":"GBP"}' } })
		);
		const reloaded = JSON.stringify(stored);
		expect(setupValueError(services, reloaded)).toBeNull();
		expect(storedSetupValue(services, reloaded)).toEqual(stored);
	});

	it('says which row and box is wrong', () => {
		expect(
			setupValueError(
				services,
				rows({ id: 'a', values: { name: 'A' } }, { id: 'b', values: { note: 'x' } })
			)
		).toBe('Row 2, Service name: fill this in.');
		expect(
			setupValueError(services, rows({ id: 'a', values: { name: 'A', seasonal: 'maybe' } }))
		).toBe('Row 1, Seasonal?: Choose an option.');
		expect(
			setupValueError(services, rows({ id: 'a', values: { name: 'A', photo: 'not-a-file' } }))
		).toBe('Row 1, Photo: Add a file.');
		expect(setupValueError(services, rows({ id: 'a', values: { name: 'x'.repeat(201) } }))).toBe(
			'Row 1, Service name: Keep this under 200 characters.'
		);
	});

	it('holds to the row limit and refuses an empty list', () => {
		const four = [1, 2, 3, 4].map((n) => ({ id: `r${n}`, values: { name: `S${n}` } }));
		expect(setupValueError(services, JSON.stringify(four))).toBe('Add up to 3.');
		expect(setupValueError(services, '[]')).toBe('Add at least one.');
	});

	it('refuses a box the list does not have, a row twice, or a row with no id', () => {
		expect(setupValueError(services, rows({ id: 'a', values: { name: 'A', price: '1' } }))).toMatch(
			/has changed/
		);
		expect(
			setupValueError(
				services,
				rows({ id: 'a', values: { name: 'A' } }, { id: 'a', values: { name: 'B' } })
			)
		).toMatch(/twice/);
		expect(setupValueError(services, '[{"values":{"name":"A"}}]')).toMatch(/could not be read/);
	});

	it('a one-row list is a form: its messages do not talk about rows', () => {
		const person = listFact(
			[
				{ key: 'name', label: 'Name', kind: 'text', required: true },
				{ key: 'email', label: 'Email', kind: 'email', required: false }
			],
			1
		);
		expect(setupValueError(person, rows({ id: 'p', values: { email: 'sam@' } }))).toBe(
			'Name: fill this in.'
		);
		expect(setupValueError(person, rows({ id: 'p', values: { name: 'Sam', email: 'sam@' } }))).toBe(
			'Email: Enter an email address like name@example.com.'
		);
		expect(
			setupValueError(
				person,
				rows({ id: 'p', values: { name: 'A' } }, { id: 'q', values: { name: 'B' } })
			)
		).toBe('Add one only.');
	});

	it('a pick-one box takes only its own choices', () => {
		const list = listFact(
			[
				{
					key: 'status',
					label: 'Status',
					kind: 'choice',
					required: true,
					options: [
						{ value: 'active', label: 'Active' },
						{ value: 'seasonal', label: 'Seasonal' }
					]
				}
			],
			5
		);
		expect(setupValueError(list, rows({ id: 'a', values: { status: 'seasonal' } }))).toBeNull();
		expect(setupValueError(list, rows({ id: 'a', values: { status: 'Seasonal' } }))).not.toBeNull();
	});

	it('finds the files its rows hold, for the file check and links', () => {
		const fields = services.listFields as SetupListField[];
		const stored = JSON.stringify(
			storedSetupValue(
				services,
				rows({ id: 'a', values: { name: 'A', photo: FILE_ID } }, { id: 'b', values: { name: 'B' } })
			)
		);
		expect(setupListFileIds(setupListRows(stored), fields)).toEqual([FILE_ID]);
		expect(setupListRows('Roof repair')).toEqual([]);
	});
});
