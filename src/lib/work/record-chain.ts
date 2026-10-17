import type { TrackStep } from '$lib/components/work/LifecycleTrack.svelte';
import { REQUEST_STATUS_LABELS, type StoredRequestStatus } from '$lib/requests/statuses';
import { INVOICE_STATUS_LABELS, type InvoiceDerivedStatus } from '$lib/invoices/statuses';

// The line every work record sits on: Request > Quote > Job > Invoice > Paid. The database follows the
// links (record_chain); this file turns its answer into the five steps of the progress strip. A step the
// member may not open arrives as `restricted`: the strip still says it happened, with no link or detail.

export type RecordKind = 'request' | 'quote' | 'job' | 'invoice';

type Restricted = { restricted: true };

export type ChainRequest = { id: string; status: string; created_at: string } | Restricted;
export type ChainQuote =
	| {
			id: string;
			quote_number: number;
			status: string;
			sent_at: string | null;
			decided_at: string | null;
	  }
	| Restricted;
export type ChainJob =
	{ id: string; job_number: number; status: string; closed_at: string | null } | Restricted;
export type ChainInvoices =
	| {
			count: number;
			paid_count: number;
			primary: {
				id: string;
				invoice_number: number;
				status: string;
				issued_at: string | null;
				due_date: string | null;
			};
	  }
	| Restricted;

export type RecordChain = {
	request: ChainRequest | null;
	quote: ChainQuote | null;
	job: ChainJob | null;
	invoices: ChainInvoices | null;
};

export const recordChainKey = (kind: RecordKind, id: string) => ['record-chain', kind, id] as const;
/** Every strip, for the moment something changes that moves a record along the line. */
export const RECORD_CHAIN_KEY_PREFIX = ['record-chain'] as const;

export async function fetchRecordChain(kind: RecordKind, id: string): Promise<RecordChain> {
	const response = await fetch(`/api/records/chain?kind=${kind}&id=${id}`);
	if (!response.ok) throw new Error('The progress line could not be loaded.');
	const result = (await response.json()) as { chain: RecordChain };
	return result.chain;
}

const isOpen = <T extends object>(step: T | Restricted | null): step is T =>
	step !== null && !('restricted' in step);

const shortDate = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });
const dateOf = (iso: string | null | undefined) => (iso ? shortDate.format(new Date(iso)) : null);

type Links = {
	request: (id: string) => string;
	quote: (id: string) => string;
	job: (id: string) => string;
	invoice: (id: string) => string;
};

/** The five steps for the progress strip. The step for the page's own record carries no link. */
export function buildRecordTrack(
	chain: RecordChain,
	options: { kind: RecordKind; links: Links; clientName?: string; clientIsCompany?: boolean }
): TrackStep[] {
	const { kind, links } = options;
	const first = options.clientName?.trim().split(' ')[0];
	const who = !first || options.clientIsCompany ? 'the client' : first;
	const link = (own: RecordKind, id: string) => (own === kind ? undefined : links[own](id));

	const has = {
		request: chain.request !== null,
		quote: chain.quote !== null,
		job: chain.job !== null,
		invoice: chain.invoices !== null
	};
	const startedAs = has.quote ? 'quote' : has.job ? 'job' : 'invoice';

	// Request
	const requestStep = ((): TrackStep => {
		const step = chain.request;
		if (!step) return { label: 'Request', sub: `Started as a ${startedAs}`, state: 'todo' };
		if (!isOpen(step)) return { label: 'Request', sub: 'Received', state: 'done' };
		if (has.quote || has.job || step.status === 'converted') {
			const date = dateOf(step.created_at);
			return {
				label: 'Request',
				sub: date ? `${date} · requested` : 'Requested',
				state: 'done',
				href: link('request', step.id)
			};
		}
		return {
			label: 'Request',
			sub: REQUEST_STATUS_LABELS[step.status as StoredRequestStatus] ?? 'Open',
			state: 'current',
			progress: step.status === 'assessment_completed' ? 0.8 : 0.4,
			href: link('request', step.id)
		};
	})();

	// Quote
	const quoteStep = ((): TrackStep => {
		const step = chain.quote;
		if (!step) {
			return {
				label: 'Quote',
				sub: has.job || has.invoice ? 'Skipped' : 'Not yet',
				state: 'todo'
			};
		}
		if (!isOpen(step)) return { label: 'Quote', sub: 'Approved', state: 'done' };
		const href = link('quote', step.id);
		const approved = step.status === 'approved' || step.status === 'converted';
		if (approved) {
			const date = dateOf(step.decided_at);
			return {
				label: 'Quote',
				sub: date ? `Approved ${date}` : 'Approved',
				state: 'done',
				href
			};
		}
		if (step.status === 'declined') {
			return {
				label: 'Quote',
				sub: 'Declined',
				state: 'current',
				tone: 'critical',
				progress: 1,
				href
			};
		}
		if (step.status === 'archived') {
			return { label: 'Quote', sub: 'Archived', state: 'current', progress: 0.5, href };
		}
		if (step.status === 'draft') {
			return { label: 'Quote', sub: 'Draft, not sent', state: 'current', progress: 0.25, href };
		}
		return {
			label: 'Quote',
			sub: step.status === 'changes_requested' ? `${who} wants changes` : `Waiting on ${who}`,
			state: 'current',
			tone: 'critical',
			progress: 0.55,
			href
		};
	})();

	// Job
	const jobStep = ((): TrackStep => {
		const step = chain.job;
		if (!step) {
			return {
				label: 'Job',
				sub: has.invoice ? 'Skipped' : 'After approval',
				state: 'todo'
			};
		}
		if (!isOpen(step)) return { label: 'Job', sub: 'Created', state: 'done' };
		const href = link('job', step.id);
		if (step.status === 'closed') {
			const date = dateOf(step.closed_at);
			return {
				label: 'Job',
				sub: `#${step.job_number} · ${date ? `closed ${date}` : 'closed'}`,
				state: 'done',
				href
			};
		}
		return {
			label: 'Job',
			sub: `#${step.job_number} · in progress`,
			state: 'current',
			progress: 0.5,
			href
		};
	})();

	// Invoice, then Paid
	const invoices = chain.invoices;
	const open = isOpen(invoices) ? invoices : null;
	const invoiceStep = ((): TrackStep => {
		if (!invoices) return { label: 'Invoice', sub: 'After the work', state: 'todo' };
		if (!open) return { label: 'Invoice', sub: 'Sent', state: 'done' };
		const href = link('invoice', open.primary.id);
		const number = `#${open.primary.invoice_number}`;
		const more = open.count > 1 ? ` +${open.count - 1}` : '';
		const status = open.primary.status as InvoiceDerivedStatus;
		const label = INVOICE_STATUS_LABELS[status] ?? '';
		if (status === 'draft') {
			return {
				label: 'Invoice',
				sub: `${number}${more} · draft`,
				state: 'current',
				progress: 0.3,
				href
			};
		}
		if (status === 'voided' || status === 'bad_debt') {
			return {
				label: 'Invoice',
				sub: `${number}${more} · ${label.toLowerCase()}`,
				state: 'current',
				tone: 'critical',
				progress: 1,
				href
			};
		}
		return { label: 'Invoice', sub: `${number}${more} · sent`, state: 'done', href };
	})();

	const paidStep = ((): TrackStep => {
		if (!invoices) return { label: 'Paid', sub: 'Not yet', state: 'todo' };
		if (!open) return { label: 'Paid', sub: 'Not shared with you', state: 'todo' };
		if (open.paid_count >= open.count) return { label: 'Paid', sub: 'Paid in full', state: 'done' };
		const status = open.primary.status as InvoiceDerivedStatus;
		if (open.paid_count > 0) {
			return {
				label: 'Paid',
				sub: `${open.paid_count} of ${open.count} paid`,
				state: 'current',
				progress: open.paid_count / open.count
			};
		}
		if (status === 'past_due') {
			return { label: 'Paid', sub: 'Past due', state: 'current', tone: 'critical', progress: 0.1 };
		}
		if (status === 'awaiting_payment') {
			return { label: 'Paid', sub: 'Waiting on payment', state: 'current', progress: 0.1 };
		}
		return { label: 'Paid', sub: 'Not yet', state: 'todo' };
	})();

	return [requestStep, quoteStep, jobStep, invoiceStep, paidStep];
}
