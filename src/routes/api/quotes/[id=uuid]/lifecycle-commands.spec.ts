import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as publish } from './publish/+server';
import { POST as revise } from './revise/+server';
import { POST as decision } from './decision/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const quoteId = '00000000-0000-4000-8000-000000000091';

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

function commandEvent(
	body: unknown,
	rpcResult: unknown = { data: { version_number: 1 }, error: null }
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: quoteId },
		request: new Request(`http://localhost/api/quotes/${quoteId}`, {
			method: 'POST',
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
		// Three routes share this fake event and each names its own generated route id, so the shape is
		// handed over untyped rather than pretending to be one of them.
	} as unknown as Parameters<typeof publish>[0] &
		Parameters<typeof revise>[0] &
		Parameters<typeof decision>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

const stale = {
	data: null,
	error: {
		code: 'P0409',
		message: 'Someone else changed this quote while you were editing. Reload and try again.'
	}
};

describe('publishing a quote', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.send': true }));
	});

	it('asks for the send permission, not the edit one', async () => {
		await publish(commandEvent({ expected_revision: 2 }));

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.send');
	});

	it('refuses to run at all without that permission', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = commandEvent({ expected_revision: 2 });

		expect((await publish(target)).status).toBe(403);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('will not send without the revision the browser was shown', async () => {
		const target = commandEvent({});

		expect((await publish(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('sends through the one command that freezes the version', async () => {
		const target = commandEvent({ expected_revision: 3 });

		await publish(target);

		expect(target.__rpc).toHaveBeenCalledWith('publish_quote', {
			target_quote_id: quoteId,
			expected_revision: 3
		});
	});

	it('answers a stale send with a conflict the browser can reload on', async () => {
		const response = await publish(commandEvent({ expected_revision: 1 }, stale));
		const body = await response.json();

		expect(response.status).toBe(409);
		expect(body.reason).toBe('stale');
	});

	it('turns a refused send into the sentence the database wrote', async () => {
		const response = await publish(
			commandEvent(
				{ expected_revision: 1 },
				{
					data: null,
					error: { code: '23514', message: 'Add at least one line before sending this quote.' }
				}
			)
		);
		const body = await response.json();

		expect(response.status).toBe(422);
		expect(body.field_errors.form).toBe('Add at least one line before sending this quote.');
	});
});

describe('revising a quote', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.edit': true }));
	});

	it('clones the published version without needing a body', async () => {
		const target = commandEvent(undefined);

		await revise(target);

		expect(target.__rpc).toHaveBeenCalledWith('revise_quote', { target_quote_id: quoteId });
	});

	it('hides a quote it cannot reach behind a not found', async () => {
		const response = await revise(
			commandEvent(undefined, { data: null, error: { code: '42501', message: 'no' } })
		);

		expect(response.status).toBe(404);
	});
});

describe('recording a decision', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.record_decision': true }));
	});

	it('asks for the decision permission of its own', async () => {
		await decision(commandEvent({ decision: 'approved' }));

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.record_decision');
	});

	it('refuses an answer that is neither approved nor declined', async () => {
		const target = commandEvent({ decision: 'maybe' });

		expect((await decision(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('passes the answer, the note, and the revision through', async () => {
		const target = commandEvent({
			decision: 'declined',
			note: '  Went with someone cheaper.  ',
			expected_revision: 4
		});

		await decision(target);

		expect(target.__rpc).toHaveBeenCalledWith('record_quote_decision', {
			target_quote_id: quoteId,
			new_decision: 'declined',
			decision_note: 'Went with someone cheaper.',
			expected_revision: 4
		});
	});

	it('sends no revision when the quote is already in front of the customer', async () => {
		const target = commandEvent({ decision: 'approved' });

		await decision(target);
		const [, args] = target.__rpc.mock.calls[0] as [string, Record<string, unknown>];

		expect(args.expected_revision).toBeNull();
		expect(args.decision_note).toBeNull();
	});
});
