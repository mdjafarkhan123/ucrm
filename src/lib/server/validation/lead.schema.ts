import { z } from 'zod';
import {
	CONTACT_METHOD_KINDS,
	LEAD_CONTACT_METHODS_MAX,
	LEAD_COUNTRY_FILTER_MAX,
	LEAD_SEARCH_MAX,
	LEAD_SORTS,
	LEAD_SOURCES,
	LEAD_STATUSES,
	isCountryCode
} from '$lib/jafar/leads';
import {
	CALL_OUTCOMES,
	CONTACT_CHANNELS,
	CONTACT_DIRECTIONS,
	CONTACT_FUTURE_SKEW_MS,
	HISTORY_BODY_MAX,
	takesCallOutcome,
	type ContactChannel,
	type ContactDirection
} from '$lib/jafar/lead-history';
import { calendarDate } from './owner.schema';

// A list arrives as one comma-separated value: `?status=new,later`. Every item must be allowed and none repeated,
// so a bad link is refused rather than half-applied.
function list<Value extends string>(allowed: readonly [Value, ...Value[]]) {
	return z
		.string()
		.max(1000)
		.transform((raw) => raw.split(',').map((part) => part.trim()))
		.pipe(z.array(z.enum(allowed)).min(1).max(allowed.length))
		.transform((items) => [...new Set(items)]);
}

const countryCode = z.string().trim().toUpperCase().refine(isCountryCode, 'Choose the country.');

export const leadListQuerySchema = z.object({
	search: z.string().trim().max(LEAD_SEARCH_MAX).optional(),
	status: list(LEAD_STATUSES).optional(),
	country: z
		.string()
		.max(1000)
		.transform((raw) => raw.split(',').map((part) => part.trim().toUpperCase()))
		.pipe(z.array(z.string().refine(isCountryCode)).min(1).max(LEAD_COUNTRY_FILTER_MAX))
		.transform((items) => [...new Set(items)])
		.optional(),
	source: list(LEAD_SOURCES).optional(),
	sort: z.enum(LEAD_SORTS).optional(),
	/** Opaque cursor from the previous page's `next_cursor`. */
	cursor: z.string().max(300).optional(),
	limit: z.coerce.number().int().min(1).max(100).optional()
});

export type LeadListQuery = z.infer<typeof leadListQuerySchema>;

// Empty text in a form field means "not given".
const optionalText = (max: number, message?: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullish()
		.transform((value) => (value ? value : null));

export const leadContactMethodSchema = z.object({
	kind: z.enum(CONTACT_METHOD_KINDS),
	value: z.string().trim().min(1, 'Enter the contact detail.').max(300),
	found_at: z.string().trim().min(1, 'Say where you found this detail.').max(300)
});

// An email must look like one; a phone or WhatsApp number needs its country code.
function checkContactValue(
	method: { kind: string; value: string },
	path: (string | number)[],
	context: z.RefinementCtx
) {
	if (method.kind === 'email' && !z.email().safeParse(method.value).success)
		context.addIssue({ code: 'custom', path, message: 'Enter a valid email address.' });
	if (
		(method.kind === 'phone' || method.kind === 'whatsapp') &&
		method.value.replace(/\D/g, '').length < 7
	)
		context.addIssue({
			code: 'custom',
			path,
			message: 'Enter the full phone number, with its country code.'
		});
}

// The details a Lead is added with and can later be edited: the business and how Uplift came across it.
const leadDetailFields = {
	business_name: z.string().trim().min(1, 'Enter the business name.').max(200),
	country_code: countryCode,
	trade: z.string().trim().min(1, 'Enter the trade.').max(120),
	source: z.enum(LEAD_SOURCES, { message: 'Choose how you found this business.' }),
	source_detail: optionalText(300),
	website: optionalText(300),
	contact_name: optionalText(120),
	fit_notes: optionalText(4000)
};

export const leadCreateSchema = z
	.object({
		...leadDetailFields,
		lead_status: z.enum(LEAD_STATUSES).default('new'),
		next_action: optionalText(200),
		next_action_due_on: calendarDate.nullish().transform((value) => value ?? null),
		contact_methods: z
			.array(leadContactMethodSchema)
			.max(LEAD_CONTACT_METHODS_MAX, `Add at most ${LEAD_CONTACT_METHODS_MAX} contact details.`)
			.default([])
	})
	.superRefine((lead, context) => {
		// A next action is a dated step: both or neither.
		if (lead.next_action && !lead.next_action_due_on)
			context.addIssue({
				code: 'custom',
				path: ['next_action_due_on'],
				message: 'Choose when the next action is due.'
			});
		if (!lead.next_action && lead.next_action_due_on)
			context.addIssue({
				code: 'custom',
				path: ['next_action'],
				message: 'Say what the next action is.'
			});
		lead.contact_methods.forEach((method, index) =>
			checkContactValue(method, ['contact_methods', index, 'value'], context)
		);
	});

export type LeadCreateInput = z.infer<typeof leadCreateSchema>;

// What the add form sends while someone types, to warn about a business already on file.
export const leadDuplicateCheckSchema = z.object({
	business_name: z.string().trim().max(200).optional(),
	country_code: z
		.string()
		.trim()
		.toUpperCase()
		.refine((value) => value === '' || isCountryCode(value))
		.optional(),
	website: z.string().trim().max(300).optional(),
	emails: z.array(z.string().trim().max(300)).max(LEAD_CONTACT_METHODS_MAX).default([]),
	phones: z.array(z.string().trim().max(300)).max(LEAD_CONTACT_METHODS_MAX).default([]),
	/** The Lead being edited, so it does not match itself. */
	exclude_id: z.uuid().optional()
});

// --- B2: the Lead page ---------------------------------------------------------------------------------------

const nextActionText = z.string().trim().min(1, 'Say what the next action is.').max(200);

/**
 * One change from the Lead page: the status, the next action, or both. `next_action.mode`:
 * `set` replaces it, `done` records the current one as done and optionally sets the next, `clear` removes it.
 */
export const leadChangeSchema = z
	.object({
		lead_status: z.enum(LEAD_STATUSES).optional(),
		next_action: z
			.discriminatedUnion('mode', [
				z.object({ mode: z.literal('set'), text: nextActionText, due_on: calendarDate }),
				z.object({
					mode: z.literal('done'),
					text: nextActionText.nullish().transform((value) => value ?? null),
					due_on: calendarDate.nullish().transform((value) => value ?? null)
				}),
				z.object({ mode: z.literal('clear') })
			])
			.optional()
	})
	.superRefine((change, context) => {
		if (!change.lead_status && !change.next_action)
			context.addIssue({ code: 'custom', path: ['form'], message: 'Nothing to change.' });
		const next = change.next_action;
		if (next?.mode === 'done' && Boolean(next.text) !== Boolean(next.due_on))
			context.addIssue({
				code: 'custom',
				path: next.text ? ['next_action', 'due_on'] : ['next_action', 'text'],
				message: next.text ? 'Choose when the next action is due.' : 'Say what the next action is.'
			});
	});

export type LeadChangeInput = z.infer<typeof leadChangeSchema>;

// Logged contact happened already: a time up to a few minutes ahead is a fast clock, anything later is a mistake.
const occurredAt = z.iso
	.datetime({ offset: true, message: 'Choose when it happened.' })
	.refine(
		(value) => Date.parse(value) <= Date.now() + CONTACT_FUTURE_SKEW_MS,
		'Contact you log has already happened — choose a time that is not in the future.'
	)
	.refine(
		(value) => Date.parse(value) >= Date.parse('2000-01-01T00:00:00Z'),
		'Choose when it happened.'
	);

const historyBody = z
	.string()
	.trim()
	.max(HISTORY_BODY_MAX, `Keep it under ${HISTORY_BODY_MAX} characters.`);

const contactFields = {
	contact_direction: z.enum(CONTACT_DIRECTIONS, { message: 'Choose who reached out.' }),
	contact_channel: z.enum(CONTACT_CHANNELS, { message: 'Choose how.' }),
	contact_method_id: z
		.uuid()
		.nullish()
		.transform((value) => value ?? null),
	call_outcome: z
		.enum(CALL_OUTCOMES)
		.nullish()
		.transform((value) => value ?? null),
	occurred_at: occurredAt,
	body: historyBody.nullish().transform((value) => (value ? value : null))
};

function checkCallOutcome(
	entry: {
		contact_direction: ContactDirection;
		contact_channel: ContactChannel;
		call_outcome: unknown;
	},
	context: z.RefinementCtx
) {
	const needsOutcome = takesCallOutcome(entry.contact_channel, entry.contact_direction);
	if (needsOutcome && !entry.call_outcome)
		context.addIssue({
			code: 'custom',
			path: ['call_outcome'],
			message: 'Choose how the call went.'
		});
	if (!needsOutcome && entry.call_outcome)
		context.addIssue({
			code: 'custom',
			path: ['call_outcome'],
			message: 'Only a call you made has an outcome.'
		});
}

export const leadNoteSchema = z.object({
	kind: z.literal('note'),
	body: historyBody.min(1, 'Write the note.')
});

/** Adding to a Lead's history: a note, or contact that happened outside UCRM. */
export const leadHistoryEntrySchema = z
	.discriminatedUnion('kind', [
		leadNoteSchema,
		z.object({ kind: z.literal('contact'), ...contactFields })
	])
	.superRefine((entry, context) => {
		if (entry.kind === 'contact') checkCallOutcome(entry, context);
	});

export type LeadHistoryEntryInput = z.infer<typeof leadHistoryEntrySchema>;

export const leadHistoryQuerySchema = z.object({ cursor: z.string().max(300) });

export const leadApplicationSearchSchema = z.object({
	search: z.string().trim().max(LEAD_SEARCH_MAX).optional()
});

export const leadApplicationLinkSchema = z.object({ application_id: z.uuid() });

// --- B2b: editing a Lead's details ---------------------------------------------------------------------------

/**
 * One save from the Lead page. `fields` holds only the details being changed. Contact details arrive as
 * operations so two people editing at once do not undo each other: `change` corrects a detail in place (history
 * that used it follows the correction) and never changes its type; `remove` keeps it for history but stops
 * offering it.
 */
export const leadDetailsEditSchema = z
	.object({
		fields: z.object(leadDetailFields).partial().strict().default({}),
		contact_methods: z
			.object({
				add: z.array(leadContactMethodSchema).max(LEAD_CONTACT_METHODS_MAX).default([]),
				change: z
					.array(leadContactMethodSchema.extend({ id: z.uuid() }))
					.max(LEAD_CONTACT_METHODS_MAX)
					.default([]),
				remove: z.array(z.uuid()).max(LEAD_CONTACT_METHODS_MAX).default([])
			})
			.default({ add: [], change: [], remove: [] })
	})
	.superRefine((edit, context) => {
		const methods = edit.contact_methods;
		if (
			Object.keys(edit.fields).length === 0 &&
			!methods.add.length &&
			!methods.change.length &&
			!methods.remove.length
		)
			context.addIssue({ code: 'custom', path: ['form'], message: 'Nothing to change.' });
		methods.add.forEach((method, index) =>
			checkContactValue(method, ['contact_methods', 'add', index, 'value'], context)
		);
		methods.change.forEach((method, index) =>
			checkContactValue(method, ['contact_methods', 'change', index, 'value'], context)
		);
		const ids = [...methods.change.map((method) => method.id), ...methods.remove];
		if (new Set(ids).size !== ids.length)
			context.addIssue({
				code: 'custom',
				path: ['form'],
				message: 'A contact detail can be changed or removed, not both.'
			});
	});

export type LeadDetailsEditInput = z.infer<typeof leadDetailsEditSchema>;
