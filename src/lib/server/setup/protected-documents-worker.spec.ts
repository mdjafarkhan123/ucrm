import { describe, expect, it, vi } from 'vitest';
import { runProtectedDocumentChecks, sweepProtectedDocuments } from './protected-documents-worker';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

// Client onboarding B9a: a protected document passes the same one-read check as every File, but a refused one
// leaves storage at once, and nothing is checked at all without a scanner.

const PDF = new TextEncoder().encode('%PDF-1.7\n' + 'x'.repeat(200));

function stream(bytes: Uint8Array) {
	return new ReadableStream<Uint8Array>({
		start(controller) {
			controller.enqueue(bytes);
			controller.close();
		}
	});
}

function harness(scanClean: boolean) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'claim_setup_protected_documents')
			return {
				data: [
					{
						id: 'doc-1',
						organization_id: 'org-1',
						display_name: 'bill.pdf',
						size_bytes: PDF.byteLength,
						object_key: 'org-1/setup-protected/a-bill.pdf',
						claim_token: 'token-1'
					}
				],
				error: null
			};
		if (name === 'finish_setup_protected_document_check')
			return {
				data: scanClean ? [] : [{ object_key: 'org-1/setup-protected/a-bill.pdf' }],
				error: null
			};
		return { data: null, error: null };
	});
	const removeObject = vi.fn(async () => undefined);
	return {
		rpc,
		removeObject,
		dependencies: {
			client: { rpc },
			measureObject: async () => PDF.byteLength,
			readObject: async () => stream(PDF),
			removeObject,
			hasScanner: () => true,
			startScan: async () => ({
				write: async () => undefined,
				finish: async () =>
					scanClean ? { clean: true as const } : { clean: false as const, signature: 'Eicar-Test' },
				abort: () => undefined
			})
		}
	};
}

describe('checking protected documents', () => {
	it('makes a clean document ready and leaves it in storage', async () => {
		const { rpc, removeObject, dependencies } = harness(true);
		expect(await runProtectedDocumentChecks(dependencies)).toMatchObject({ claimed: 1, ready: 1 });
		expect(rpc).toHaveBeenCalledWith(
			'finish_setup_protected_document_check',
			expect.objectContaining({ target_ready: true, target_problem: null })
		);
		expect(removeObject).not.toHaveBeenCalled();
	});

	it('refuses a flagged document and deletes it from storage at once', async () => {
		const { rpc, removeObject, dependencies } = harness(false);
		expect(await runProtectedDocumentChecks(dependencies)).toMatchObject({ refused: 1 });
		expect(rpc).toHaveBeenCalledWith(
			'finish_setup_protected_document_check',
			expect.objectContaining({ target_ready: false })
		);
		expect(removeObject).toHaveBeenCalledWith('org-1/setup-protected/a-bill.pdf');
	});

	it('claims nothing without a scanner, so nothing is trusted unchecked', async () => {
		const { rpc, dependencies } = harness(true);
		await runProtectedDocumentChecks({ ...dependencies, hasScanner: () => false });
		expect(rpc).not.toHaveBeenCalled();
	});
});

describe('the sweep', () => {
	it('deletes the objects the database lets go of', async () => {
		const removeObject = vi.fn(async () => undefined);
		const rpc = vi.fn(async () => ({
			data: [{ object_key: 'org-1/setup-protected/old.pdf' }, { object_key: null }],
			error: null
		}));
		expect(await sweepProtectedDocuments({ client: { rpc }, removeObject })).toEqual({
			deleted: 2,
			objectsDeleted: 1
		});
		expect(removeObject).toHaveBeenCalledWith('org-1/setup-protected/old.pdf');
	});
});
