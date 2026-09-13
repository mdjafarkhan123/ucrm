// The Review dry-run's brain (Onboarding & Data Portability, Part 1, step 4).
//
// Given the parsed file rows, the chosen column mapping, the match action, and a compact view of the existing
// clients the file's emails/phones matched, decide -- purely, row by row -- what WOULD happen to each row:
// create / update / skip / hold / error. Nothing here touches the database; the route feeds it lookups and
// persists the result. Keeping it a pure function is what lets us unit-test every dedupe rule directly.
//
// The rules are the ones locked in the roadmap + research doc:
//   * Match an existing client on email/phone -> Skip or Update (never a second copy).
//   * Two file rows share an email/phone -> the first row wins it; later rows import without it, flagged.
//   * A row matching client A on email but client B on phone -> held for a human, never guessed.
//   * A row that fails validation -> error, with a plain reason.
//   * A row with no email and no phone still imports (flagged); the (batch, source row) key is its retry guard.

import { z } from 'zod';
import {
	clientWriteSchema,
	deriveClientDisplayName,
	propertyAddressSchema,
	type ClientWriteInput
} from '$lib/server/validation/foundation.schema';
import { normalizeEmail, normalizePhone } from '$lib/server/clients/duplicates';
import { normalizeCountryToIso2 } from '$lib/server/imports/country';
import type { ImportClientTarget } from '$lib/server/validation/imports.schema';

// A create row must be a whole valid client (name required); that is clientWriteSchema. An UPDATE row is
// different -- it only carries the fields being changed plus whatever it matched on, so it must not be forced
// to have a full name. This schema still enforces the formats that matter (a valid email, a real property)
// without the create schema's name requirement. Empty cells are already dropped before validation, so every
// field is simply optional.
const importUpdateRowSchema = z.object({
	first_name: z.string().trim().max(500).optional(),
	last_name: z.string().trim().max(500).optional(),
	company_name: z.string().trim().max(500).optional(),
	email: z.string().trim().email('Enter a valid email.').max(254).optional(),
	phone: z.string().trim().max(40).optional(),
	lead_source: z.string().trim().max(80).optional(),
	initial_note: z.string().trim().max(500).optional(),
	property: propertyAddressSchema.optional()
});
type ImportRowFields = z.infer<typeof importUpdateRowSchema>;

export type ImportColumnMapping = Record<
	string,
	{ field: ImportClientTarget; dont_overwrite?: boolean }
>;
export type ReviewMatchAction = 'skip' | 'update';

// One existing client a file row matched, reduced to only what the update branch needs to decide changes.
export type ExistingClient = {
	id: string;
	client_type: 'person' | 'company';
	first_name: string | null;
	last_name: string | null;
	company_name: string | null;
	lead_source: string | null;
	has_email: boolean;
	has_phone: boolean;
	has_property: boolean;
};

export type ResolvedProperty = {
	label?: string;
	address_line1: string;
	address_line2?: string;
	city: string;
	state_region?: string;
	postal_code?: string;
	country: string;
};

// Matches the fixed worker contract documented on import_rows.resolved_payload. On create every client field
// is present; on update only the fields that actually change are.
export type ResolvedPayload = {
	client: {
		client_type?: 'person' | 'company';
		first_name?: string | null;
		last_name?: string | null;
		company_name?: string | null;
		display_name?: string;
		lifecycle_status?: 'lead' | 'customer';
		lead_source?: string | null;
		initial_note?: string | null;
	};
	email: string | null;
	phone: string | null;
	property: ResolvedProperty | null;
};

export type PlannedAction = 'create' | 'update' | 'skip' | 'hold' | 'error';

export type ReviewRow = {
	source_row_number: number;
	raw: Record<string, string>;
	planned_action: PlannedAction;
	resolved_payload: ResolvedPayload | null;
	match_client_id: string | null;
	match_reason: string | null;
	flags: string[];
	error_message: string | null;
};

export type ReviewSummary = {
	total: number;
	create: number;
	update: number;
	skip: number;
	hold: number;
	error: number;
};

export type ReviewInputs = {
	rows: Record<string, string>[];
	mapping: ImportColumnMapping;
	matchAction: ReviewMatchAction;
	// normalized email/phone -> existing client id (visible clients only)
	emailToClientId: Map<string, string>;
	phoneToClientId: Map<string, string>;
	clientsById: Map<string, ExistingClient>;
};

// Imported rows are full clients, not leads (matches Jobber: a CSV import creates full clients).
const IMPORTED_LIFECYCLE = 'customer' as const;

const SCALAR_FIELDS = ['first_name', 'last_name', 'company_name', 'lead_source'] as const;
type ScalarField = (typeof SCALAR_FIELDS)[number];

// Turn one file row into the candidate client fields the mapping points at. Empty cells are dropped so a blank
// column never counts as "a value to write".
function buildCandidate(row: Record<string, string>, mapping: ImportColumnMapping) {
	const scalars: Partial<Record<ImportClientTarget, string>> = {};
	const property: Record<string, string> = {};
	let sawPropertyCell = false;
	// Which of our fields carries a "don't overwrite" toggle, and whether any property column does.
	const dontOverwrite = new Map<ImportClientTarget, boolean>();
	let propertyDontOverwrite = false;

	for (const [header, entry] of Object.entries(mapping)) {
		const value = (row[header] ?? '').trim();
		dontOverwrite.set(entry.field, entry.dont_overwrite ?? false);
		if (entry.field.startsWith('property.')) {
			if (entry.dont_overwrite) propertyDontOverwrite = true;
			if (value) {
				const subField = entry.field.slice('property.'.length);
				// Real exports write the country as a full name ("United States"); our schema stores a 2-letter
				// ISO code. Normalize here, before validation, or every such property row would error out.
				property[subField] = subField === 'country' ? normalizeCountryToIso2(value) : value;
				sawPropertyCell = true;
			}
			continue;
		}
		if (value) scalars[entry.field] = value;
	}

	return { scalars, property, sawPropertyCell, dontOverwrite, propertyDontOverwrite };
}

export function runReview(inputs: ReviewInputs): { rows: ReviewRow[]; summary: ReviewSummary } {
	const { rows, mapping, matchAction, emailToClientId, phoneToClientId, clientsById } = inputs;

	// First-come-first-served claims over the whole file: the first row that would write an email/phone wins
	// it; a later row that would write the same value must import without it (our per-org uniqueness forbids
	// two clients sharing one).
	const claimedEmails = new Set<string>();
	const claimedPhones = new Set<string>();

	const out: ReviewRow[] = [];
	const summary: ReviewSummary = { total: 0, create: 0, update: 0, skip: 0, hold: 0, error: 0 };

	rows.forEach((row, index) => {
		const source_row_number = index + 1;
		const { scalars, property, sawPropertyCell, dontOverwrite, propertyDontOverwrite } =
			buildCandidate(row, mapping);
		const flags: string[] = [];

		// Infer person vs company like Jobber: a company name with no personal name is a company; anything
		// with a first/last name is a person.
		const hasPersonName = Boolean(scalars.first_name || scalars.last_name);
		const client_type: 'person' | 'company' =
			scalars.company_name && !hasPersonName ? 'company' : 'person';

		// A property needs a street to be a property; property cells without one can't be written, so flag it.
		const propertyForValidation = property.address_line1 ? property : undefined;
		if (sawPropertyCell && !property.address_line1) flags.push('property_skipped_no_address');

		const errorRow = (message: string): void => {
			out.push({
				source_row_number,
				raw: row,
				planned_action: 'error',
				resolved_payload: null,
				match_client_id: null,
				match_reason: null,
				flags,
				error_message: message
			});
			summary.error += 1;
		};

		// Match on the raw mapped values -- normalization, not validation, decides who a row belongs to, so an
		// unmatched row can still fail create validation below while a matched update row can carry partial data.
		const normEmail = normalizeEmail(scalars.email);
		const normPhone = normalizePhone(scalars.phone);
		const emailClient = normEmail ? emailToClientId.get(normEmail) : undefined;
		const phoneClient = normPhone ? phoneToClientId.get(normPhone) : undefined;

		// Email points at one client, phone at a different one -> never guessed, held for a human.
		if (emailClient && phoneClient && emailClient !== phoneClient) {
			out.push({
				source_row_number,
				raw: row,
				planned_action: 'hold',
				resolved_payload: null,
				match_client_id: emailClient,
				match_reason: 'email_phone_conflict',
				flags,
				error_message: null
			});
			summary.hold += 1;
			return;
		}

		const matchedId = emailClient ?? phoneClient ?? null;
		const matchReason = emailClient
			? phoneClient
				? 'email_phone'
				: 'email'
			: phoneClient
				? 'phone'
				: null;

		if (matchedId) {
			// Skip: leave the existing client exactly as it is -- no need to validate a row we will not write.
			if (matchAction === 'skip') {
				out.push(skipRow(source_row_number, row, matchedId, matchReason, flags));
				summary.skip += 1;
				return;
			}

			// Update: validate only the formats (a partial row is legitimate here), then change what the toggles
			// allow and add contact info/property only where the client lacks it and no earlier row claimed it.
			const parsedUpdate = importUpdateRowSchema.safeParse({
				...scalars,
				property: propertyForValidation
			});
			if (!parsedUpdate.success) {
				errorRow(parsedUpdate.error.issues[0]?.message ?? 'This row could not be read.');
				return;
			}

			const built = buildUpdate({
				data: parsedUpdate.data,
				existing: clientsById.get(matchedId),
				dontOverwrite,
				propertyDontOverwrite,
				emailClient,
				phoneClient,
				normEmail,
				normPhone,
				claimedEmails,
				claimedPhones
			});

			if (!built) {
				// Nothing new to write onto the matched client -- treat as a skip so the worker does no empty work.
				flags.push('already_up_to_date');
				out.push(skipRow(source_row_number, row, matchedId, matchReason, flags));
				summary.skip += 1;
				return;
			}

			out.push({
				source_row_number,
				raw: row,
				planned_action: 'update',
				resolved_payload: built,
				match_client_id: matchedId,
				match_reason: matchReason,
				flags,
				error_message: null
			});
			summary.update += 1;
			return;
		}

		// No existing match -> create, which must be a whole valid client (a name is required).
		const parsedCreate = clientWriteSchema.safeParse({
			client_type,
			...scalars,
			property: propertyForValidation
		});
		if (!parsedCreate.success) {
			errorRow(parsedCreate.error.issues[0]?.message ?? 'This row could not be read.');
			return;
		}
		const data = parsedCreate.data;

		// First-come-first-served claims decide which methods this row keeps.
		let email: string | null = data.email ? data.email.trim() : null;
		let phone: string | null = data.phone ? data.phone.trim() : null;

		if (normEmail) {
			if (claimedEmails.has(normEmail)) {
				email = null;
				flags.push('email_shared_in_file');
			} else {
				claimedEmails.add(normEmail);
			}
		}
		if (normPhone) {
			if (claimedPhones.has(normPhone)) {
				phone = null;
				flags.push('phone_shared_in_file');
			} else {
				claimedPhones.add(normPhone);
			}
		}
		if (!email && !phone) flags.push('no_contact_method');

		const resolved_payload: ResolvedPayload = {
			client: {
				client_type,
				first_name: data.first_name?.trim() || null,
				last_name: data.last_name?.trim() || null,
				company_name: data.company_name?.trim() || null,
				display_name: deriveClientDisplayName(data),
				lifecycle_status: IMPORTED_LIFECYCLE,
				lead_source: data.lead_source?.trim() || null,
				initial_note: data.initial_note?.trim() || null
			},
			email,
			phone,
			property: propertyForValidation ? toResolvedProperty(data) : null
		};

		out.push({
			source_row_number,
			raw: row,
			planned_action: 'create',
			resolved_payload,
			match_client_id: null,
			match_reason: null,
			flags,
			error_message: null
		});
		summary.create += 1;
	});

	summary.total = out.length;
	return { rows: out, summary };
}

function skipRow(
	source_row_number: number,
	raw: Record<string, string>,
	matchedId: string,
	matchReason: string | null,
	flags: string[]
): ReviewRow {
	return {
		source_row_number,
		raw,
		planned_action: 'skip',
		resolved_payload: null,
		match_client_id: matchedId,
		match_reason: matchReason,
		flags,
		error_message: null
	};
}

// The property sub-object of resolved_payload, taken from the validated (defaulted) client data.
function toResolvedProperty(data: {
	property?: ImportRowFields['property'];
}): ResolvedProperty | null {
	const p = data.property;
	if (!p) return null;
	return {
		label: p.label || undefined,
		address_line1: p.address_line1,
		address_line2: p.address_line2 || undefined,
		city: p.city,
		state_region: p.state_region || undefined,
		postal_code: p.postal_code || undefined,
		country: p.country
	};
}

type BuildUpdateArgs = {
	data: ImportRowFields;
	existing: ExistingClient | undefined;
	dontOverwrite: Map<ImportClientTarget, boolean>;
	propertyDontOverwrite: boolean;
	emailClient: string | undefined;
	phoneClient: string | undefined;
	normEmail: string | null;
	normPhone: string | null;
	claimedEmails: Set<string>;
	claimedPhones: Set<string>;
};

// Build the update payload, carrying only what changes. Returns null when there is nothing to write.
function buildUpdate(args: BuildUpdateArgs): ResolvedPayload | null {
	const {
		data,
		existing,
		dontOverwrite,
		propertyDontOverwrite,
		emailClient,
		phoneClient,
		normEmail,
		normPhone,
		claimedEmails,
		claimedPhones
	} = args;
	// Without the existing client's current values we cannot honor "don't overwrite"; defend by writing nothing.
	if (!existing) return null;

	const client: ResolvedPayload['client'] = {};
	let nameChanged = false;

	for (const field of SCALAR_FIELDS) {
		const nextValue = (data[field] ?? '').trim();
		if (!nextValue) continue; // nothing mapped for this field
		const existingValue = (existing[field as ScalarField] ?? '').trim();
		if (dontOverwrite.get(field) && existingValue) continue; // protected by the toggle
		if (nextValue === existingValue) continue; // already this value
		client[field] = nextValue;
		if (field !== 'lead_source') nameChanged = true;
	}

	// A name change means the derived display name changes too, from the merged (existing + new) values.
	if (nameChanged) {
		client.display_name = deriveClientDisplayName({
			client_type: existing.client_type,
			first_name: client.first_name ?? existing.first_name ?? '',
			last_name: client.last_name ?? existing.last_name ?? '',
			company_name: client.company_name ?? existing.company_name ?? ''
		} as ClientWriteInput);
	}

	// Notes are additive: always carry a mapped note, never dropped by a toggle.
	if (data.initial_note && data.initial_note.trim()) {
		client.initial_note = data.initial_note.trim();
	}

	// Add an email only if it is genuinely new to the org (emailClient is undefined -- otherwise it either is
	// this client's own matched email or would have conflicted), the client has no email or the toggle allows
	// it, and no earlier row already claimed it.
	let email: string | null = null;
	if (normEmail && emailClient === undefined) {
		const blocked = dontOverwrite.get('email') && existing.has_email;
		if (!blocked && !claimedEmails.has(normEmail)) {
			email = (data.email ?? '').trim();
			claimedEmails.add(normEmail);
		}
	}

	let phone: string | null = null;
	if (normPhone && phoneClient === undefined) {
		const blocked = dontOverwrite.get('phone') && existing.has_phone;
		if (!blocked && !claimedPhones.has(normPhone)) {
			phone = (data.phone ?? '').trim();
			claimedPhones.add(normPhone);
		}
	}

	// Add the property only if the client has none, or the toggle allows it.
	let resolvedProperty: ResolvedProperty | null = null;
	if (data.property) {
		const blocked = propertyDontOverwrite && existing.has_property;
		if (!blocked) resolvedProperty = toResolvedProperty(data);
	}

	const hasClientChange = Object.keys(client).length > 0;
	if (!hasClientChange && !email && !phone && !resolvedProperty) return null;

	return { client, email, phone, property: resolvedProperty };
}
