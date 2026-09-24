// The exact shapes `job_report_state`, `private.job_report_customer_document` and
// `job_report_customer_preview` return, written out by hand for the same reason the invoice and quote
// customer documents are: what is missing from a type here is the point of it. There is no cost, margin or
// internal note anywhere in the customer-facing shapes, and none may be added without changing the one
// database function that decides what a customer may see.

export type JobReportSelection = {
	include_service_details: boolean;
	include_price: boolean;
	signature_id: string | null;
	summary: string | null;
	photo_ids: string[];
	checklist: { visit_id: string; item_id: string }[];
};

// A File Manager photo linked to the job or one of its visits, checked and not in Trash.
export type JobReportCandidatePhoto = {
	file_id: string;
	file_name: string;
	mime_type: string;
	has_thumbnail: boolean;
	created_at: string;
	caption: string | null;
	/** Label names, alphabetical. */
	labels: string[];
};

export type JobReportCandidateItem = {
	item_id: string;
	label: string;
	item_type: string;
	value: string | number | boolean | null;
};

export type JobReportCandidateVisit = {
	visit_id: string;
	visit_date: string | null;
	items: JobReportCandidateItem[];
};

export type JobReportCandidateSignature = {
	id: string;
	signer_name: string;
	signature_type: string;
	collected_at: string;
};

// The editor read: the job's current selection, plus everything it could add.
export type JobReportState = {
	report: JobReportSelection;
	has_content: boolean;
	can_view_price: boolean;
	candidates: {
		photos: JobReportCandidatePhoto[];
		visits: JobReportCandidateVisit[];
		signatures: JobReportCandidateSignature[];
	};
};

export type CustomerJobReportLine = {
	line_id: string;
	position: number;
	line_kind: string;
	category: string | null;
	name: string;
	description: string | null;
	unit_label: string | null;
	quantity: number | null;
	// Present only when the report includes prices.
	unit_price_minor?: number;
	line_total_minor?: number;
};

// A photo moved to Trash after the customer's link was issued keeps its place as `removed`, with no id,
// name or words, so their copy shows the gap instead of silently changing. Preview as client never has one.
// `caption` and `labels` are frozen with the link; a link issued before Part 7B-2 has neither.
export type CustomerJobReportPhoto =
	| {
			file_id: string;
			file_name: string;
			caption?: string | null;
			labels?: string[];
			removed?: false;
	  }
	| { file_id: null; file_name: null; caption?: null; labels?: string[]; removed: true };

export type CustomerJobReportChecklistItem = {
	item_id: string;
	label: string;
	item_type: string;
	value: string | number | boolean | null;
};

export type CustomerJobReportChecklistVisit = {
	visit_id: string;
	visit_date: string | null;
	items: CustomerJobReportChecklistItem[];
};

export type CustomerJobReportSignature = {
	signer_name: string;
	signer_role: string | null;
	signature_type: string;
	statement: string;
	method: string;
	has_image: boolean;
	collected_at: string;
} | null;

// The document `private.job_report_customer_document` builds -- the same one the token page and Preview as
// client both render, so the two can never drift.
export type CustomerJobReportDocument = {
	business: { name: string | null };
	job: {
		job_number: number;
		title: string | null;
		job_type: string;
		currency_code: string;
	};
	client: {
		display_name: string | null;
		company_name: string | null;
		first_name: string | null;
		last_name: string | null;
	};
	property: {
		label: string | null;
		address_line1: string | null;
		address_line2: string | null;
		city: string | null;
		state_region: string | null;
		postal_code: string | null;
		country: string | null;
	};
	summary: string | null;
	photos: CustomerJobReportPhoto[];
	checklist: CustomerJobReportChecklistVisit[];
	service_details: {
		lines: CustomerJobReportLine[];
		totals: {
			subtotal_minor: number;
			discount_minor: number;
			tax_minor: number;
			total_minor: number;
		} | null;
	} | null;
	signature: CustomerJobReportSignature;
};

export type JobReportCustomerPreview = {
	document: CustomerJobReportDocument | null;
	preview: {
		has_content: boolean;
		prices_withheld: boolean;
	};
};
