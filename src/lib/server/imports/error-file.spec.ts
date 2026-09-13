import { describe, expect, it, vi } from 'vitest';
import { buildImportErrorCsv, generateImportErrorFile, type ImportErrorRow } from './error-file';

describe('buildImportErrorCsv', () => {
	it('lists failed and held rows, sorted by source row number, with plain reasons', () => {
		const rows: ImportErrorRow[] = [
			{
				source_row_number: 5,
				status: 'held',
				raw: { Name: 'Sam', Email: 'sam@x.com' },
				match_reason: 'email_phone_conflict',
				error_message: null
			},
			{
				source_row_number: 2,
				status: 'failed',
				raw: { Name: 'Jo', Email: 'jo@x.com' },
				match_reason: null,
				error_message: "This contact's email or phone already belongs to another client."
			}
		];

		const csv = buildImportErrorCsv(rows);
		const lines = csv.trimEnd().split('\r\n');

		expect(lines[0]).toBe('Row,Result,Reason,Name,Email');
		// Row 2 comes before row 5.
		expect(lines[1]).toContain('2,Not imported,');
		expect(lines[1]).toContain("This contact's email or phone already belongs to another client.");
		expect(lines[1]).toContain('Jo,jo@x.com');
		expect(lines[2]).toContain('5,Needs review,');
		expect(lines[2]).toContain('one by email, one by phone');
	});

	it('unions original columns across rows in first-seen order', () => {
		const rows: ImportErrorRow[] = [
			{
				source_row_number: 1,
				status: 'failed',
				raw: { A: '1', B: '2' },
				match_reason: null,
				error_message: 'x'
			},
			{
				source_row_number: 2,
				status: 'failed',
				raw: { B: '3', C: '4' },
				match_reason: null,
				error_message: 'y'
			}
		];
		expect(buildImportErrorCsv(rows).split('\r\n')[0]).toBe('Row,Result,Reason,A,B,C');
	});

	it('escapes commas, quotes and newlines', () => {
		const rows: ImportErrorRow[] = [
			{
				source_row_number: 1,
				status: 'failed',
				raw: { Note: 'a, "b"\nc' },
				match_reason: null,
				error_message: 'plain'
			}
		];
		expect(buildImportErrorCsv(rows).split('\r\n')[1]).toContain('"a, ""b""\nc"');
	});

	it('handles a null raw as an empty cell', () => {
		const rows: ImportErrorRow[] = [
			{
				source_row_number: 1,
				status: 'held',
				raw: null,
				match_reason: 'other',
				error_message: null
			}
		];
		const csv = buildImportErrorCsv(rows);
		expect(csv.split('\r\n')[0]).toBe('Row,Result,Reason');
		expect(csv.split('\r\n')[1]).toBe(
			'1,Needs review,This contact needs a person to review before it can be imported.'
		);
	});
});

describe('generateImportErrorFile', () => {
	function clientReturning(rows: unknown[]) {
		const order = vi.fn().mockResolvedValue({ data: rows, error: null });
		const inFn = vi.fn().mockReturnValue({ order });
		const eq = vi.fn().mockReturnValue({ in: inFn });
		const select = vi.fn().mockReturnValue({ eq });
		const from = vi.fn().mockReturnValue({ select });
		const rpc = vi.fn().mockResolvedValue({ error: null });
		return { from, rpc, select, eq, inFn, order };
	}

	it('uploads the file and stamps the key when there are failed/held rows', async () => {
		const rows = [
			{
				source_row_number: 1,
				status: 'failed',
				raw: { Name: 'Jo' },
				match_reason: null,
				error_message: 'nope'
			}
		];
		const client = clientReturning(rows);
		const putObjectFn = vi.fn().mockResolvedValue(undefined);

		const result = await generateImportErrorFile({
			client: client as never,
			organizationId: 'org-1',
			batchId: 'batch-1',
			putObjectFn
		});

		expect(result.objectKey).toBe('org-1/client-imports/errors/batch-1.csv');
		expect(putObjectFn).toHaveBeenCalledWith(
			'org-1/client-imports/errors/batch-1.csv',
			expect.any(Uint8Array),
			'text/csv'
		);
		expect(client.rpc).toHaveBeenCalledWith('set_import_batch_error_file', {
			target_batch_id: 'batch-1',
			object_key: 'org-1/client-imports/errors/batch-1.csv'
		});
	});

	it('writes nothing and returns null when there are no rows to explain', async () => {
		const client = clientReturning([]);
		const putObjectFn = vi.fn();

		const result = await generateImportErrorFile({
			client: client as never,
			organizationId: 'org-1',
			batchId: 'batch-1',
			putObjectFn
		});

		expect(result.objectKey).toBeNull();
		expect(putObjectFn).not.toHaveBeenCalled();
		expect(client.rpc).not.toHaveBeenCalled();
	});
});
