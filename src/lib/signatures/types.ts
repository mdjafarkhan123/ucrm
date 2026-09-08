// The three kinds Housecall Pro settled on, fixed rather than a configurable library. Every limit here has
// a twin in 20260912100000_job_signatures_foundation.sql; the database is the one that decides, and these
// exist so a person gets a sentence about the box they typed in instead of a constraint name.

export const JOB_SIGNATURE_TYPES = ['work_authorization', 'work_completion', 'other'] as const;
export type JobSignatureType = (typeof JOB_SIGNATURE_TYPES)[number];

export const SIGNATURE_METHODS = ['typed', 'drawn'] as const;
export type SignatureMethod = (typeof SIGNATURE_METHODS)[number];

export const SIGNER_NAME_MAX = 120;
export const SIGNER_ROLE_MAX = 60;
export const SIGNATURE_STATEMENT_MAX = 500;

// A row on the job's signature card. No money and no snapshot: the signed document is its own read.
export type JobSignature = {
	id: string;
	signature_type: JobSignatureType;
	statement: string;
	signer_name: string;
	signer_role: string | null;
	method: SignatureMethod;
	has_image: boolean;
	visit_id: string | null;
	visit_date: string | null;
	collected_at: string;
	collected_by: string | null;
	/** The job document no longer hashes to what was signed — Housecall Pro's grey-turns-red. */
	is_stale: boolean;
};

// One frozen document, exactly as it stood when it was signed. `unit_price_minor`, `line_total_minor` and
// `totals` are absent for a reader without `jobs.view_price`.
export type SignedJobDocumentLine = {
	line_id: string;
	position: number;
	line_kind: string;
	category: string | null;
	name: string | null;
	description: string | null;
	unit_label: string | null;
	quantity: number;
	is_taxable: boolean;
	unit_price_minor?: number;
	line_total_minor?: number;
};

export type SignedJobDocument = {
	job_id: string;
	job_number: number;
	title: string | null;
	job_type: string;
	instructions: string | null;
	currency_code: string;
	client: {
		client_id: string | null;
		display_name: string | null;
		company_name: string | null;
		first_name: string | null;
		last_name: string | null;
	};
	property: {
		property_id: string | null;
		label: string | null;
		address_line1: string | null;
		address_line2: string | null;
		city: string | null;
		state_region: string | null;
		postal_code: string | null;
		country: string | null;
	};
	lines: SignedJobDocumentLine[];
	totals?: {
		subtotal_minor: number;
		discount_minor: number;
		tax_minor: number;
		total_minor: number;
	};
};

export type JobSignatureDocument = Omit<JobSignature, 'visit_date'> & {
	job_id: string;
	document_hash: string;
	document: SignedJobDocument;
};
