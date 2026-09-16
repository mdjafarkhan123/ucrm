// The opening-balances Review dry-run's brain (Onboarding & Data Portability, Part 4).
//
// Given the parsed file rows, the chosen column mapping, which client each row's email resolves to, and the
// clients' current (unreplaced) opening-balance facts, decide -- purely, row by row -- what WOULD happen:
// create / update (a correction) / hold / error. Nothing here touches the database; the route feeds it lookups
// and persists the result, the same split review.ts (client import) uses.
//
// The rules (financial-reconciliation contract, "Opening balances"):
//   * A row's client_email must resolve to an existing client -- this import never creates one (only the
//     Client importer does, and a Client with no debt has nothing to record here).
//   * A client that already carries an active (unreplaced) fact of the same balance_type gets a correction
//     (predecessor_opening_balance_id), never a second, competing fact.
//   * Two file rows that would both correct/create the same {client, balance_type} pair in one run -> never
//     guessed which comes first; both are held for a human to split across two runs (the same "never guessed"
//     rule the client importer's email/phone conflict uses).
//   * A row that fails validation -> error, with a plain reason.
//   * There is no skip outcome: unlike the client importer, nothing here is ever "already up to date" --
//     Review's summary.skip is always 0, kept only so the shared Review/Done components' shape still fits.

import type { ImportOpeningBalanceTarget } from '$lib/server/validation/imports.schema';
import { normalizeEmail } from '$lib/server/clients/duplicates';

export type OpeningBalanceColumnMapping = Record<string, { field: ImportOpeningBalanceTarget }>;

export type BalanceType = 'receivable' | 'credit';

export type ActiveOpeningBalanceFact = {
	client_id: string;
	balance_type: BalanceType;
	opening_balance_id: string;
};

export type ResolvedOpeningBalancePayload = {
	client_id: string;
	balance_type: BalanceType;
	amount_minor: number;
	currency_code: string;
	as_of_date: string;
	source_note: string | null;
	predecessor_opening_balance_id?: string;
};

export type OpeningBalancePlannedAction = 'create' | 'update' | 'hold' | 'error';

export type OpeningBalanceReviewRow = {
	source_row_number: number;
	raw: Record<string, string>;
	planned_action: OpeningBalancePlannedAction;
	resolved_payload: ResolvedOpeningBalancePayload | null;
	match_client_id: string | null;
	match_reason: string | null;
	flags: string[];
	error_message: string | null;
};

export type OpeningBalanceReviewSummary = {
	total: number;
	create: number;
	update: number;
	skip: number;
	hold: number;
	error: number;
};

export type OpeningBalanceReviewInputs = {
	rows: Record<string, string>[];
	mapping: OpeningBalanceColumnMapping;
	// normalized email -> client id, for clients the caller may see.
	emailToClientId: Map<string, string>;
	activeFacts: ActiveOpeningBalanceFact[];
	currencyCode: string;
};

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

function isValidIsoDate(value: string): boolean {
	const match = ISO_DATE.exec(value);
	if (!match) return false;
	const [, yearStr, monthStr, dayStr] = match;
	const year = Number(yearStr);
	const month = Number(monthStr);
	const day = Number(dayStr);
	if (month < 1 || month > 12) return false;
	const date = new Date(Date.UTC(year, month - 1, day));
	return (
		date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
	);
}

// Accepts "1,250.00" or "$1250" as well as "1250" -- real spreadsheets carry currency symbols and thousands
// separators. Returns integer minor units (cents), or null when the cell is not a positive amount.
function parseAmountMinor(raw: string): number | null {
	const cleaned = raw.trim().replace(/[$,\s]/g, '');
	if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return null;
	const minor = Math.round(Number(cleaned) * 100);
	return minor > 0 ? minor : null;
}

function cellsFor(row: Record<string, string>, mapping: OpeningBalanceColumnMapping) {
	const values: Partial<Record<ImportOpeningBalanceTarget, string>> = {};
	for (const [header, entry] of Object.entries(mapping)) {
		const value = (row[header] ?? '').trim();
		if (value) values[entry.field] = value;
	}
	return values;
}

export function runOpeningBalanceReview(inputs: OpeningBalanceReviewInputs): {
	rows: OpeningBalanceReviewRow[];
	summary: OpeningBalanceReviewSummary;
} {
	const { rows, mapping, emailToClientId, activeFacts, currencyCode } = inputs;

	const activeByPair = new Map<string, ActiveOpeningBalanceFact>();
	for (const fact of activeFacts) {
		activeByPair.set(`${fact.client_id}:${fact.balance_type}`, fact);
	}
	// First-come-first-served within the file, mirroring the client importer's claimed-email/phone rule: the
	// first row for a {client, balance_type} pair stands, a later row for the same pair is never guessed.
	const claimedPairs = new Set<string>();

	const out: OpeningBalanceReviewRow[] = [];
	const summary: OpeningBalanceReviewSummary = {
		total: 0,
		create: 0,
		update: 0,
		skip: 0,
		hold: 0,
		error: 0
	};

	rows.forEach((row, index) => {
		const source_row_number = index + 1;
		const cells = cellsFor(row, mapping);

		const errorRow = (message: string): void => {
			out.push({
				source_row_number,
				raw: row,
				planned_action: 'error',
				resolved_payload: null,
				match_client_id: null,
				match_reason: null,
				flags: [],
				error_message: message
			});
			summary.error += 1;
		};

		const emailCell = cells.client_email;
		if (!emailCell) return errorRow('Enter the client’s email.');
		const normEmail = normalizeEmail(emailCell);
		const clientId = normEmail ? emailToClientId.get(normEmail) : undefined;
		if (!clientId) {
			return errorRow(
				'No client in your account has this email. Import the client first, then their opening balance.'
			);
		}

		const balanceTypeCell = (cells.balance_type ?? '').toLowerCase();
		if (balanceTypeCell !== 'receivable' && balanceTypeCell !== 'credit') {
			return errorRow('Balance type must be "receivable" or "credit".');
		}
		const balanceType = balanceTypeCell as BalanceType;

		const amountCell = cells.amount;
		const amountMinor = amountCell ? parseAmountMinor(amountCell) : null;
		if (!amountMinor) return errorRow('Enter a positive amount, e.g. 1250.00.');

		const dateCell = cells.as_of_date;
		if (!dateCell || !isValidIsoDate(dateCell)) {
			return errorRow('Enter the as-of date as YYYY-MM-DD.');
		}

		const noteCell = cells.source_note;
		if (noteCell && noteCell.length > 500) {
			return errorRow('The note is too long (500 characters max).');
		}

		const pairKey = `${clientId}:${balanceType}`;
		if (claimedPairs.has(pairKey)) {
			out.push({
				source_row_number,
				raw: row,
				planned_action: 'hold',
				resolved_payload: null,
				match_client_id: clientId,
				match_reason: 'duplicate_in_file',
				flags: [],
				error_message: null
			});
			summary.hold += 1;
			return;
		}
		claimedPairs.add(pairKey);

		const existing = activeByPair.get(pairKey);
		const resolved_payload: ResolvedOpeningBalancePayload = {
			client_id: clientId,
			balance_type: balanceType,
			amount_minor: amountMinor,
			currency_code: currencyCode,
			as_of_date: dateCell,
			source_note: noteCell ?? null,
			...(existing ? { predecessor_opening_balance_id: existing.opening_balance_id } : {})
		};

		out.push({
			source_row_number,
			raw: row,
			planned_action: existing ? 'update' : 'create',
			resolved_payload,
			match_client_id: existing ? existing.opening_balance_id : null,
			match_reason: existing ? `existing_${balanceType}` : null,
			flags: [],
			error_message: null
		});
		if (existing) summary.update += 1;
		else summary.create += 1;
	});

	summary.total = out.length;
	return { rows: out, summary };
}
