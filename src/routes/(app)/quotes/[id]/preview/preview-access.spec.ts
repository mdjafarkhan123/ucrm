import { beforeEach, describe, expect, it, vi } from 'vitest';

const { load } = await import('./+page.server');

const rpc = vi.fn();
const getUser = vi.fn();

const preview = {
	document: {
		quote: { quote_number: 12, status: 'draft' },
		recipient: { name: 'Dana', email: 'dana@example.com' },
		business: { name: 'Northside Roofing' },
		document: { version_number: 0, show_totals: true },
		lines: [],
		attachments: [],
		totals: { total_minor: 120000 }
	},
	preview: {
		version_status: 'draft',
		version_number: 0,
		is_current_published: false,
		prices_withheld: false
	}
};

function event(quoteId = 'quote-1') {
	return {
		params: { id: quoteId },
		locals: { getUser, supabase: { rpc } }
	} as unknown as Parameters<typeof load>[0];
}

async function open(quoteId?: string) {
	return (await load(event(quoteId))) as { preview: typeof preview };
}

describe('opening Preview as client', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		getUser.mockResolvedValue({ id: 'user-1' });
		rpc.mockResolvedValue({ data: preview, error: null });
	});

	it('reads the customer document through the one database function', async () => {
		const answer = await open('quote-1');

		expect(rpc).toHaveBeenCalledWith('quote_customer_preview', { target_quote_id: 'quote-1' });
		expect(answer.preview.document.quote.quote_number).toBe(12);
	});

	it('sends a signed-out visitor to the login page instead of the document', async () => {
		getUser.mockResolvedValue(null);

		await expect(open()).rejects.toMatchObject({ status: 303, location: '/login' });
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses without saying whether the quote exists when the database says no', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'You do not have access to this quote.' }
		});

		await expect(open()).rejects.toMatchObject({ status: 403 });
	});

	it('says there is nothing to show when the quote has no version yet', async () => {
		rpc.mockResolvedValue({ data: null, error: null });

		await expect(open()).rejects.toMatchObject({ status: 404 });
	});

	it('creates no recipient and no access link merely by looking', async () => {
		await open();

		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain('issue_quote_access_link');
	});
});
