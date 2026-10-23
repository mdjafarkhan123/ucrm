import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as addPicture } from './[senderId]/pictures/+server';
import { PATCH as save } from './[senderId]/+server';
import { GET as readPicture } from '../../../../public/sms/toll-free-proof/[token]/+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { putObject } from '$lib/server/storage/r2';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/storage/r2', () => ({
	putObject: vi.fn(),
	deleteObject: vi.fn(),
	getObjectStream: vi.fn()
}));
vi.mock('$env/dynamic/private', () => ({ env: { APP_URL: 'https://app.example.com' } }));

const organizationId = '123e4567-e89b-42d3-a456-426614174000';
const senderId = '123e4567-e89b-42d3-a456-426614174003';
const checkId = '123e4567-e89b-42d3-a456-426614174004';
const PNG = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 0]);

/** A Supabase stand-in: each table answers every chained read with the rows given for it. */
function fakeClient(tables: Record<string, unknown>) {
	return {
		from: vi.fn((table: string) => {
			const result = { data: tables[table] ?? null, error: null };
			const builder: Record<string, unknown> = {
				then: (done: (value: unknown) => unknown) => Promise.resolve(result).then(done),
				maybeSingle: () => Promise.resolve(result),
				single: () => Promise.resolve(result)
			};
			for (const step of ['select', 'eq', 'in', 'order', 'insert', 'update', 'delete'])
				builder[step] = () => builder;
			return builder;
		})
	};
}

function pictureEvent(bytes: Uint8Array, revision: number, type = 'image/png') {
	const form = new FormData();
	form.set('picture', new File([bytes], 'signup.png', { type }));
	form.set('expected_revision', String(revision));
	return {
		params: { senderId },
		request: new Request('http://localhost/pictures', { method: 'POST', body: form }),
		locals: {}
	} as never;
}

const draftCheck = { id: checkId, answers: {}, revision: 3, status: 'draft' };

describe('toll-free check API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } }
		} as never);
	});

	it('stops before the database when the person may not manage connections', async () => {
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});
		const response = await addPicture(pictureEvent(PNG, 3));
		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('refuses a file that only claims to be a picture, before storing anything', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			fakeClient({
				communication_sms_tollfree_verifications: draftCheck,
				communication_sms_tollfree_proof_images: []
			}) as never
		);
		const response = await addPicture(
			pictureEvent(new TextEncoder().encode('<script>'), 3, 'image/png')
		);
		expect(response.status).toBe(422);
		expect(putObject).not.toHaveBeenCalled();
	});

	it('refuses a sixth picture and a picture added from an out-of-date copy', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			fakeClient({
				communication_sms_tollfree_verifications: draftCheck,
				communication_sms_tollfree_proof_images: Array.from({ length: 5 }, (_, i) => ({ id: i }))
			}) as never
		);
		expect((await addPicture(pictureEvent(PNG, 3))).status).toBe(422);
		expect((await addPicture(pictureEvent(PNG, 2))).status).toBe(409);
		expect(putObject).not.toHaveBeenCalled();
	});

	it('keeps a check under review closed to changes', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			fakeClient({
				communication_sms_tollfree_verifications: { ...draftCheck, status: 'under_review' }
			}) as never
		);
		expect((await addPicture(pictureEvent(PNG, 3))).status).toBe(409);
	});

	it('refuses a malformed draft save before writing anything', async () => {
		const client = fakeClient({
			communication_sms_sender_identities: {
				id: senderId,
				phone_number: '+18885550100',
				sender_type: 'toll_free',
				number_type: 'toll_free',
				country_code: 'US',
				lifecycle_state: 'active'
			}
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const response = await save({
			params: { senderId },
			request: new Request('http://localhost/', {
				method: 'PATCH',
				body: JSON.stringify({ expected_revision: 0, business: {} })
			}),
			locals: {}
		} as never);
		expect(response.status).toBe(422);
		expect(client.from).not.toHaveBeenCalledWith('communication_sms_tollfree_verifications');
	});

	it('reads a proof picture only by its random token', async () => {
		const response = await readPicture({ params: { token: 'not-a-token' } } as never);
		expect(response.status).toBe(404);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});
});
