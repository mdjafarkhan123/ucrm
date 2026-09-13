import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as uploadImport } from './+server';
import { requireClientPermission } from '$lib/server/access/clients';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { putObject } from '$lib/server/storage/r2';

vi.mock('$lib/server/access/clients', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/clients')>(
		'$lib/server/access/clients'
	);
	return { ...actual, requireClientPermission: vi.fn() };
});

vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

vi.mock('$lib/server/storage/r2', () => ({
	buildClientImportObjectKey: (organizationId: string, fileName: string) =>
		`${organizationId}/client-imports/fixed-uuid-${fileName}`,
	putObject: vi.fn()
}));

const mockedRequire = vi.mocked(requireClientPermission);
const mockedRateLimit = vi.mocked(checkRateLimit);
const mockedPutObject = vi.mocked(putObject);

const ORGANIZATION_ID = 'org-1';

function grantAccess() {
	mockedRequire.mockResolvedValue({
		auth: {
			organization: { id: ORGANIZATION_ID, name: 'Bright Spark Electrical', role: 'owner' },
			user: { id: 'user-1', email: 'owner@example.com' }
		},
		access: { permissions: { 'customers.create': true }, features: {} }
	} as never);
}

// Build the POST event the route reads: a multipart request carrying one CSV file, plus a mocked
// supabase.rpc that stands in for create_import_batch.
function uploadEvent(csv: string, fileName = 'clients.csv', type = 'text/csv') {
	const form = new FormData();
	form.append('file', new File([csv], fileName, { type }));
	const rpc = vi.fn(() => Promise.resolve({ data: { id: 'batch-1' }, error: null }));
	return {
		request: new Request('http://localhost/api/imports/clients', { method: 'POST', body: form }),
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof uploadImport>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

beforeEach(() => {
	vi.clearAllMocks();
	grantAccess();
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
});

describe('POST /api/imports/clients', () => {
	it('returns the guard response when the caller lacks customers.create', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const event = uploadEvent('name,email\nAda,ada@example.com');
		const response = await uploadImport(event);
		expect(response.status).toBe(403);
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('refuses when the upload counter is spent', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const response = await uploadImport(uploadEvent('name,email\nAda,ada@example.com'));
		expect(response.status).toBe(429);
	});

	it('rejects a file that is not a CSV', async () => {
		const event = uploadEvent('not a csv', 'contacts.pdf', 'application/pdf');
		const response = await uploadImport(event);
		expect(response.status).toBe(422);
		expect(mockedPutObject).not.toHaveBeenCalled();
		expect(event.__rpc).not.toHaveBeenCalled();
	});

	it('rejects a file over the byte cap before parsing it', async () => {
		const oversize = 'a'.repeat(2.5 * 1024 * 1024 + 1);
		const response = await uploadImport(uploadEvent(oversize));
		expect(response.status).toBe(422);
		expect(mockedPutObject).not.toHaveBeenCalled();
	});

	it('rejects a CSV with a header but no data rows', async () => {
		const response = await uploadImport(uploadEvent('name,email\n'));
		expect(response.status).toBe(422);
	});

	it('keeps a repeated header by letting Papaparse rename it, losing no column', async () => {
		const event = uploadEvent('email,email\nada@example.com,ada.alt@example.com');
		const response = await uploadImport(event);
		expect(response.status).toBe(201);
		const body = await response.json();
		expect(body.headers).toEqual(['email', 'email_1']);
		expect(body.preview_rows[0]).toEqual({
			email: 'ada@example.com',
			email_1: 'ada.alt@example.com'
		});
	});

	it('rejects a blank column header', async () => {
		const response = await uploadImport(uploadEvent('name, \nAda,x'));
		expect(response.status).toBe(422);
	});

	it('rejects more than 5,000 data rows', async () => {
		const rows = Array.from({ length: 5001 }, (_, i) => `Person ${i},p${i}@example.com`);
		const response = await uploadImport(uploadEvent(`name,email\n${rows.join('\n')}`));
		expect(response.status).toBe(422);
		expect(mockedPutObject).not.toHaveBeenCalled();
	});

	it('parses, stores, records the batch, and returns a capped preview', async () => {
		const rows = Array.from({ length: 25 }, (_, i) => `Person ${i},p${i}@example.com`);
		const event = uploadEvent(`Full Name,Email\n${rows.join('\n')}`);
		const response = await uploadImport(event);

		expect(response.status).toBe(201);
		const body = await response.json();
		expect(body.headers).toEqual(['Full Name', 'Email']);
		expect(body.row_count).toBe(25);
		expect(body.preview_rows).toHaveLength(20);
		expect(body.preview_rows[0]).toEqual({ 'Full Name': 'Person 0', Email: 'p0@example.com' });
		expect(body.batch_id).toBe('batch-1');

		expect(mockedPutObject).toHaveBeenCalledWith(
			`${ORGANIZATION_ID}/client-imports/fixed-uuid-clients.csv`,
			expect.any(Uint8Array),
			'text/csv'
		);
		const [command, args] = event.__rpc.mock.calls[0];
		expect(command).toBe('create_import_batch');
		expect(args.payload).toMatchObject({
			organization_id: ORGANIZATION_ID,
			source_filename: 'clients.csv',
			storage_object_key: `${ORGANIZATION_ID}/client-imports/fixed-uuid-clients.csv`,
			file_row_count: 25
		});
	});

	it('trims stray whitespace in headers so preview keys match', async () => {
		const event = uploadEvent(' Name , Email \nAda,ada@example.com');
		const response = await uploadImport(event);
		expect(response.status).toBe(201);
		const body = await response.json();
		expect(body.headers).toEqual(['Name', 'Email']);
		expect(body.preview_rows[0]).toEqual({ Name: 'Ada', Email: 'ada@example.com' });
	});
});
