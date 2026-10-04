import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as listDocuments, POST as startUpload } from './+server';
import { DELETE as removeDocument, GET as openDocument } from './[id]/+server';
import { GET as readHistory } from './[id]/history/+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readOrganizationSetupCatalogue } from '$lib/server/setup/catalogue';
import { buildSetupCatalogue, type SetupCatalogueRow } from '$lib/setup/catalogue';
import { SETUP_VERSION_1 } from '$lib/setup/catalogue.fixture';

// Client onboarding B9a: Jafar's rules for protected setup documents, as the routes enforce them (2026-10-04).
// An administrator doing setup can upload one and see that it arrived; only the business owner (and Jafar,
// through his own routes) can open one or read its history; every opening and removal is recorded.

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationAdmin: vi.fn() };
});
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/setup/catalogue', () => ({ readOrganizationSetupCatalogue: vi.fn() }));
vi.mock('$lib/server/storage/r2', async () => {
	const actual =
		await vi.importActual<typeof import('$lib/server/storage/r2')>('$lib/server/storage/r2');
	return {
		...actual,
		createPresignedUploadUrl: vi.fn(async () => 'https://storage.example/upload'),
		createPresignedDownloadUrl: vi.fn(async () => 'https://storage.example/download'),
		deleteObject: vi.fn(async () => undefined)
	};
});

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const DOCUMENT_ID = '22222222-2222-4222-8222-222222222222';

// The fixture's first stage plus one protected question and one ordinary file question.
const CATALOGUE_ROW: SetupCatalogueRow = {
	...SETUP_VERSION_1,
	stages: [
		{
			...SETUP_VERSION_1.stages[0],
			items: [
				...SETUP_VERSION_1.stages[0].items,
				{
					type: 'question',
					fact_key: 'business.port_bill',
					label: 'Upload a recent phone bill.',
					hint: null,
					built_in: false,
					required: false,
					can_defer: false,
					kind: 'protected_file',
					options: null,
					max_files: 1,
					max_length: null
				},
				{
					type: 'question',
					fact_key: 'business.van_photos',
					label: 'Photos of your vans',
					hint: null,
					built_in: false,
					required: false,
					can_defer: false,
					kind: 'file',
					options: null,
					file_kinds: ['photo'],
					max_files: 5,
					max_length: null
				}
			]
		}
	]
};

type Rpc = ReturnType<typeof vi.fn>;

function ownerClient(options: { rpc?: Record<string, { data: unknown; error?: unknown }> } = {}) {
	const rpc: Rpc = vi.fn(async (name: string) => {
		const result = options.rpc?.[name] ?? { data: null };
		return { data: result.data, error: result.error ?? null };
	});
	const from = vi.fn((table: string) => {
		const data =
			table === 'profiles'
				? { full_name: 'Sara Admin' }
				: table === 'setup_protected_documents'
					? [
							{
								id: DOCUMENT_ID,
								fact_key: 'business.port_bill',
								display_name: 'bill.pdf',
								size_bytes: 1000,
								state: 'ready',
								problem: null,
								upload_completed_at: '2026-10-04T10:00:00Z',
								delete_after: null
							}
						]
					: null;
		const result = { data, error: null };
		const chain = {
			select: () => chain,
			eq: () => chain,
			in: () => chain,
			maybeSingle: () => Promise.resolve(result),
			then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve)
		};
		return chain;
	});
	vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc, from } as never);
	return { rpc, from };
}

function signedIn(role: 'owner' | 'admin') {
	vi.mocked(requireOrganizationAdmin).mockResolvedValue({
		auth: {
			organization: { id: ORGANIZATION_ID, name: 'Mike’s Plumbing', role },
			user: { id: `${role}-user`, email: `${role}@example.com` }
		},
		access: { permissions: {}, features: {} }
	} as never);
}

function event(options: { body?: unknown; search?: string; id?: string } = {}) {
	return {
		locals: { supabase: {} },
		params: { id: options.id ?? DOCUMENT_ID },
		url: new URL(`http://localhost/api/setup/protected-documents${options.search ?? ''}`),
		request: new Request('http://localhost/api/setup/protected-documents', {
			method: 'POST',
			body: options.body === undefined ? undefined : JSON.stringify(options.body)
		})
	} as never;
}

async function thrown(promise: unknown) {
	try {
		await promise;
	} catch (error) {
		return error as { status: number; location: string };
	}
	throw new Error('Expected a redirect.');
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true } as never);
	vi.mocked(readOrganizationSetupCatalogue).mockResolvedValue(buildSetupCatalogue(CATALOGUE_ROW));
});

describe('opening a protected document', () => {
	it('refuses an administrator, and records nothing', async () => {
		signedIn('admin');
		const client = ownerClient();
		const response = await openDocument(event());
		expect(response.status).toBe(403);
		expect(await response.json()).toMatchObject({ reason: 'owner_only' });
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('lets the owner open it, recording the opening under their name first', async () => {
		signedIn('owner');
		const client = ownerClient({
			rpc: {
				open_setup_protected_document: {
					data: [{ object_key: 'k', display_name: 'bill.pdf', mime_type: 'application/pdf' }]
				}
			}
		});
		const redirect = await thrown(openDocument(event()));
		expect(redirect).toMatchObject({ status: 303, location: 'https://storage.example/download' });
		expect(client.rpc).toHaveBeenCalledWith('open_setup_protected_document', {
			target_document_id: DOCUMENT_ID,
			target_organization_id: ORGANIZATION_ID,
			target_actor_user_id: 'owner-user',
			target_actor_label: 'Sara Admin',
			target_actor_owner_email: null
		});
	});

	it('says a document that cannot be opened is not available', async () => {
		signedIn('owner');
		ownerClient({ rpc: { open_setup_protected_document: { data: [] } } });
		expect((await openDocument(event())).status).toBe(404);
	});
});

describe('the list of what arrived', () => {
	it('shows an administrator the documents but says they cannot open them', async () => {
		signedIn('admin');
		ownerClient();
		const response = await listDocuments(event({ search: `?ids=${DOCUMENT_ID}` }));
		expect(await response.json()).toMatchObject({
			can_open: false,
			documents: [{ id: DOCUMENT_ID, name: 'bill.pdf', state: 'ready' }]
		});
	});

	it('tells the owner they can open them', async () => {
		signedIn('owner');
		ownerClient();
		const response = await listDocuments(event({ search: `?ids=${DOCUMENT_ID}` }));
		expect(await response.json()).toMatchObject({ can_open: true });
	});
});

describe('the history', () => {
	it('is the owner’s to read, not an administrator’s', async () => {
		signedIn('admin');
		ownerClient();
		expect((await readHistory(event())).status).toBe(403);
	});
});

describe('starting an upload', () => {
	const upload = (fact_key: string, file_name = 'bill.pdf') => ({
		fact_key,
		file_name,
		mime_type: 'application/pdf',
		size_bytes: 1000
	});

	it('lets an administrator upload to a protected question, under the protected prefix', async () => {
		signedIn('admin');
		const client = ownerClient({
			rpc: { register_setup_protected_document: { data: { id: DOCUMENT_ID } } }
		});
		const response = await startUpload(event({ body: upload('business.port_bill') }));
		expect(response.status).toBe(201);
		const args = client.rpc.mock.calls[0][1] as { target_object_key: string };
		expect(args.target_object_key.startsWith(`${ORGANIZATION_ID}/setup-protected/`)).toBe(true);
	});

	it('refuses an ordinary file question, so a protected upload cannot land in the File library', async () => {
		signedIn('owner');
		const client = ownerClient();
		const response = await startUpload(event({ body: upload('business.van_photos') }));
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses a voice recording', async () => {
		signedIn('owner');
		ownerClient();
		const response = await startUpload(event({ body: upload('business.port_bill', 'bill.mp3') }));
		expect(response.status).toBe(422);
	});
});

describe('removing', () => {
	it('lets an administrator take back a file, recorded as removed by them', async () => {
		signedIn('admin');
		const client = ownerClient({
			rpc: { delete_setup_protected_document: { data: [{ object_key: 'k' }] } }
		});
		const response = await removeDocument(event());
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'delete_setup_protected_document',
			expect.objectContaining({ target_action: 'removed', target_actor_label: 'Sara Admin' })
		);
	});
});
