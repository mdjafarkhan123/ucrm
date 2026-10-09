// Contractor Settings Part 6C: the typed Quote v1 automation catalog.
//
// This is the SINGLE source of authorable building blocks. The builder (6C-2) renders choices from it and
// the server validator (src/lib/server/automation/definition.ts) validates against the SAME entries, so the
// two can never drift (docs/automation-behavior-contract.md § Catalogs and extension rules). It is safe in
// the browser: labels, summaries, and strict Zod config shapes only — no code, SQL, URLs, or credentials.
//
// "enabled" means authorable now (the contract's first dependency-ready subset). "blocked" entries are
// designed but not yet authorable; the builder shows them disabled with a reason rather than hiding them,
// and the validator refuses to accept them in a saved definition.

import { z } from 'zod';
import {
	automationAppointmentEmailBodySchema,
	automationAppointmentEmailSubjectSchema,
	automationEmailBodySchema,
	automationEmailSubjectSchema,
	automationInquiryEmailBodySchema,
	automationInquiryEmailSubjectSchema,
	automationInquirySmsBodySchema,
	automationSmsBodySchema
} from './email-variables';

export const AUTOMATION_SCHEMA_VERSION = 1;

export type CatalogKind = 'trigger' | 'condition' | 'wait' | 'action' | 'stop';

export type CatalogAvailability = { status: 'enabled' } | { status: 'blocked'; reason: string };

// What a recipe acts on, fixed by its trigger. CRM launch readiness Part 4 Stage 6 added the website inquiry (a
// form submission or chat session). Google review Part 4B added the job whose work was completed. Every
// condition, step and stop must match the trigger's subject, except entries marked 'any' (a wait means the same
// thing for every subject). Client reminders Part 3 added the appointment: a job visit or an assessment.
export type CatalogSubject = 'quote' | 'website_inquiry' | 'job' | 'appointment';

export type CatalogEntry = {
	key: string;
	kind: CatalogKind;
	label: string;
	summary: string;
	subject: CatalogSubject | 'any';
	// A stop the engine always applies for its subject. The builder shows it ticked and locked, and the
	// validator adds it, so the saved recipe never claims less than what really happens.
	alwaysOn?: boolean;
	availability: CatalogAvailability;
	// Strict config shape for this entry. `.strict()` is what rejects unknown fields at save time.
	configSchema: z.ZodTypeAny;
};

const NO_CONFIG = z.object({}).strict();

// Quote statuses/outcomes are owned by the Quotes domain; the builder supplies the valid option list. The
// catalog only guarantees a non-empty selection here, so 6C stays decoupled from exact status strings.
const statusSelectionConfig = z
	.object({ statuses: z.array(z.string().min(1)).min(1).max(20) })
	.strict();

// Google review Part 4B: a recurring job is never asked automatically unless the contractor picks "after every
// N completed visits" (owner decision 2026-09-26). Absent means off.
export const RECURRING_EVERY_VISITS_MAX = 52;
const jobWorkCompletedConfig = z
	.object({
		recurring_every_visits: z.number().int().min(1).max(RECURRING_EVERY_VISITS_MAX).optional()
	})
	.strict();

// Client reminders Part 3: when a visit or assessment reminder goes out. Jobber's default is 1 day before, at
// the visit's own time of day; the owner can choose 1 hour to 7 days before, or a fixed time of day instead.
export const APPOINTMENT_REMINDER_MAX_HOURS = 168;
export const APPOINTMENT_REMINDER_MAX_DAYS = 7;
export const APPOINTMENT_REMINDER_DEFAULT = { mode: 'before', amount: 1, unit: 'days' } as const;

const appointmentReminderTimingConfig = z
	.union([
		z
			.object({
				mode: z.literal('before'),
				unit: z.enum(['hours', 'days']),
				amount: z.number().int().min(1)
			})
			.strict(),
		z
			.object({
				mode: z.literal('fixed_time'),
				days_before: z.number().int().min(1).max(APPOINTMENT_REMINDER_MAX_DAYS),
				time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Choose a time of day.')
			})
			.strict()
	])
	.superRefine((value, ctx) => {
		if (value.mode !== 'before') return;
		const hours = value.unit === 'days' ? value.amount * 24 : value.amount;
		if (hours > APPOINTMENT_REMINDER_MAX_HOURS) {
			ctx.addIssue({
				code: 'custom',
				path: ['amount'],
				message: 'A reminder can go out at most 7 days before.'
			});
		}
	});

const blocked = (reason: string): CatalogAvailability => ({ status: 'blocked', reason });
const enabled: CatalogAvailability = { status: 'enabled' };

// --- Triggers -----------------------------------------------------------------------------------------
const triggers: CatalogEntry[] = [
	{
		key: 'quote.delivery_succeeded',
		kind: 'trigger',
		label: 'Quote was delivered',
		summary: 'Runs after a quote email is confirmed delivered to the customer.',
		subject: 'quote',
		availability: enabled,
		configSchema: NO_CONFIG
	},
	{
		key: 'quote.viewed',
		kind: 'trigger',
		label: 'Customer viewed the quote',
		summary: 'Runs when the customer opens the quote.',
		subject: 'quote',
		availability: blocked('Available once quote view tracking ships.'),
		configSchema: NO_CONFIG
	},
	{
		key: 'quote.changes_requested',
		kind: 'trigger',
		label: 'Customer requested changes',
		summary: 'Runs when the customer asks for changes to the quote.',
		subject: 'quote',
		availability: blocked('Available once quote change requests ship.'),
		configSchema: NO_CONFIG
	},
	{
		key: 'quote.approved',
		kind: 'trigger',
		label: 'Customer approved the quote',
		summary: 'Runs when the customer approves the quote.',
		subject: 'quote',
		availability: blocked('Available in a later update.'),
		configSchema: NO_CONFIG
	},
	{
		key: 'quote.declined',
		kind: 'trigger',
		label: 'Customer declined the quote',
		summary: 'Runs when the customer declines the quote.',
		subject: 'quote',
		availability: blocked('Available in a later update.'),
		configSchema: NO_CONFIG
	},
	{
		key: 'website_inquiry.received',
		kind: 'trigger',
		label: 'New website inquiry',
		summary: 'Runs once when someone sends your website form or starts a website chat.',
		subject: 'website_inquiry',
		availability: enabled,
		configSchema: NO_CONFIG
	},
	{
		key: 'job.work_completed',
		kind: 'trigger',
		label: "A job's work is completed",
		summary:
			'Runs when a one-time job is closed with its work done, and on recurring jobs after every chosen number of completed visits.',
		subject: 'job',
		availability: enabled,
		configSchema: jobWorkCompletedConfig
	},
	{
		key: 'appointment.reminder_due',
		kind: 'trigger',
		label: 'A visit or assessment is coming up',
		summary:
			'Runs once for each scheduled visit or assessment, at the chosen time before it starts. Moving the visit moves the reminder.',
		subject: 'appointment',
		availability: enabled,
		configSchema: appointmentReminderTimingConfig
	}
];

// --- Conditions ---------------------------------------------------------------------------------------
const conditions: CatalogEntry[] = [
	{
		key: 'quote.current_status',
		kind: 'condition',
		label: 'Quote is currently in a status',
		summary: 'Only continues while the quote is in one of the chosen statuses.',
		subject: 'quote',
		availability: enabled,
		configSchema: statusSelectionConfig
	},
	{
		key: 'quote.recipient_attached',
		kind: 'condition',
		label: 'Quote still has a reachable recipient',
		summary: 'Only continues while a valid recipient is attached to the quote.',
		subject: 'quote',
		availability: enabled,
		configSchema: NO_CONFIG
	},
	{
		key: 'quote.total_comparison',
		kind: 'condition',
		label: 'Quote total compares to an amount',
		summary: 'Only continues when the quote total is above or below an amount.',
		subject: 'quote',
		availability: blocked('Available in a later update.'),
		configSchema: z
			.object({
				operator: z.enum(['gt', 'gte', 'lt', 'lte']),
				amount_cents: z.number().int().min(0)
			})
			.strict()
	},
	{
		key: 'quote.assigned_owner',
		kind: 'condition',
		label: 'Quote is assigned to an owner',
		summary: 'Only continues when the quote is assigned to a chosen team member.',
		subject: 'quote',
		availability: blocked('Available in a later update.'),
		configSchema: z.object({ user_ids: z.array(z.string().uuid()).min(1).max(50) }).strict()
	},
	{
		key: 'quote.follow_up_preference',
		kind: 'condition',
		label: 'Customer allows follow-ups',
		summary: 'Only continues while the customer has not opted out of follow-ups.',
		subject: 'quote',
		availability: blocked('Available in a later update.'),
		configSchema: NO_CONFIG
	},
	{
		key: 'quote.delivery_channel',
		kind: 'condition',
		label: 'Quote was delivered on a channel',
		summary: 'Only continues when the quote went out on the chosen channel.',
		subject: 'quote',
		availability: blocked('Available in a later update.'),
		configSchema: z.object({ channels: z.array(z.enum(['email', 'sms'])).min(1) }).strict()
	}
];

// --- Waits and actions (Then steps) -------------------------------------------------------------------
const waits: CatalogEntry[] = [
	{
		key: 'wait.relative_delay',
		kind: 'wait',
		label: 'Wait a while',
		summary: 'Waits a set number of days, hours, or minutes before the next step.',
		subject: 'any',
		availability: enabled,
		// Local send window is applied by the engine (6D); here we only fix a positive delay.
		configSchema: z
			.object({
				unit: z.enum(['minutes', 'hours', 'days']),
				amount: z.number().int().min(1).max(2160)
			})
			.strict()
	}
];

const actions: CatalogEntry[] = [
	{
		key: 'action.send_email',
		kind: 'action',
		label: 'Send an email',
		summary: 'Sends a follow-up email to the customer through Communications.',
		subject: 'quote',
		availability: enabled,
		// 6D-3: the contractor authors the subject and body as plain text. The only dynamic values allowed are
		// the fixed allow-listed variables (email-variables.ts); the send path fills and escapes them. No
		// template id, no raw HTML.
		configSchema: z
			.object({
				subject: automationEmailSubjectSchema,
				body: automationEmailBodySchema
			})
			.strict()
	},
	{
		key: 'action.send_sms',
		kind: 'action',
		label: 'Send a text message',
		summary: 'Sends a follow-up text to the customer through Communications.',
		subject: 'quote',
		availability: enabled,
		// Stage 7: the contractor authors the text as plain text, same allow-listed variables as email, no
		// subject line. `sender_id` is an optional authorized pin to a specific eligible number; left unset it
		// continues the customer's established conversation number, else the organization default (docs/
		// automation-behavior-contract.md § SMS customer action). Whether that sender still exists and is
		// eligible is rechecked live by the send effect every time the step runs, not at save time.
		configSchema: z
			.object({
				body: automationSmsBodySchema,
				sender_id: z.string().uuid().optional()
			})
			.strict()
	},
	{
		key: 'action.send_customer_message',
		kind: 'action',
		label: 'Reply by text or email',
		summary:
			'Texts the customer when they agreed to texts and a number is ready, otherwise emails them. If the text fails, the email goes instead.',
		subject: 'website_inquiry',
		availability: enabled,
		// Stage 5 engine: sms_body is optional (without it the step only emails); the email copy is always needed
		// because it is the fallback. Business-fact variables only — an inquiry has no quote.
		configSchema: z
			.object({
				sms_body: automationInquirySmsBodySchema.optional(),
				email_subject: automationInquiryEmailSubjectSchema,
				email_body: automationInquiryEmailBodySchema
			})
			.strict()
	},
	{
		key: 'action.send_review_request',
		kind: 'action',
		label: 'Send a review request',
		summary:
			'Asks the customer for a Google review with the message and reminders from your Review settings.',
		subject: 'job',
		availability: enabled,
		// Following HighLevel's Review Request action, the wording, style and reminders live in Review settings;
		// the step only picks the channel. SMS is the default (brief § Channel choice).
		configSchema: z.object({ channel: z.enum(['sms', 'email']) }).strict()
	},
	{
		key: 'action.send_appointment_email',
		kind: 'action',
		label: 'Send a reminder email',
		summary: 'Emails the customer about their upcoming visit or assessment.',
		subject: 'appointment',
		availability: enabled,
		// The visit's date, time and address are filled at sending time, so a moved visit is always described right.
		configSchema: z
			.object({
				subject: automationAppointmentEmailSubjectSchema,
				body: automationAppointmentEmailBodySchema
			})
			.strict()
	},
	{
		key: 'action.notify_staff',
		kind: 'action',
		label: 'Notify a team member',
		summary: 'Sends an internal notification to an eligible team member.',
		subject: 'quote',
		availability: blocked('Available once staff notifications ship.'),
		configSchema: z.object({ user_ids: z.array(z.string().uuid()).min(1).max(50) }).strict()
	},
	{
		key: 'action.create_task',
		kind: 'action',
		label: 'Create a task',
		summary: 'Creates an internal task to follow up.',
		subject: 'quote',
		availability: blocked('Available once tasks ship.'),
		configSchema: z.object({ title: z.string().trim().min(1).max(200) }).strict()
	},
	{
		key: 'action.update_quote_status',
		kind: 'action',
		label: 'Update the quote status',
		summary: 'Changes the quote status automatically.',
		subject: 'quote',
		availability: blocked('Available in a later update.'),
		configSchema: z.object({ status: z.string().min(1) }).strict()
	}
];

// --- Stop conditions ----------------------------------------------------------------------------------
const stopKeys: Array<{ key: string; label: string }> = [
	{ key: 'stop.quote_approved', label: 'Customer approved the quote' },
	{ key: 'stop.quote_declined', label: 'Customer declined the quote' },
	{ key: 'stop.changes_requested', label: 'Customer requested changes' },
	{ key: 'stop.quote_archived', label: 'Quote was archived' },
	{ key: 'stop.quote_converted', label: 'Quote was converted to a job' },
	{ key: 'stop.quote_expired', label: 'Quote expired' },
	{ key: 'stop.recipient_invalid', label: 'Recipient is no longer reachable' },
	{ key: 'stop.preferences_invalid', label: 'Customer opted out of follow-ups' },
	{ key: 'stop.customer_reply', label: 'Customer replied' }
];

const stops: CatalogEntry[] = [
	...stopKeys.map(({ key, label }) => ({
		key,
		kind: 'stop' as const,
		label,
		summary: 'Stops the automation for that quote.',
		subject: 'quote' as const,
		availability: enabled,
		configSchema: NO_CONFIG
	})),
	// Stage 3 engine rules, applied to every inquiry enrollment (HighLevel "User Replied" / "Stop on Response").
	{
		key: 'stop.inquiry_staff_reply',
		kind: 'stop',
		label: 'A team member replied',
		summary: 'Stops the follow-up once a reply from your team is delivered.',
		subject: 'website_inquiry',
		alwaysOn: true,
		availability: enabled,
		configSchema: NO_CONFIG
	},
	{
		key: 'stop.inquiry_customer_reply',
		kind: 'stop',
		label: 'Customer replied (pauses, so your team can Resume, Skip, or Stop)',
		summary:
			'Pauses before the next message once the customer answers something this automation sent.',
		subject: 'website_inquiry',
		alwaysOn: true,
		availability: enabled,
		configSchema: NO_CONFIG
	},
	// Google review Part 4B engine rules, applied to every job enrollment (brief § When the sequence stops).
	{
		key: 'stop.job_reopened',
		kind: 'stop',
		label: 'The job was reopened or is no longer complete',
		summary: 'Stops before asking once the job is reopened or no longer has completed work.',
		subject: 'job',
		alwaysOn: true,
		availability: enabled,
		configSchema: NO_CONFIG
	},
	{
		key: 'stop.client_review_opt_out',
		kind: 'stop',
		label: 'The client turned off review requests',
		summary: 'Stops before asking once the client is removed or no longer wants review requests.',
		subject: 'job',
		alwaysOn: true,
		availability: enabled,
		configSchema: NO_CONFIG
	},
	// Client reminders Part 3 engine rules, applied to every reminder (plan § Customer messages: shared rules).
	{
		key: 'stop.appointment_not_ahead',
		kind: 'stop',
		label: 'The visit was cancelled, completed or has started',
		summary: 'Nothing is sent for a visit that is no longer coming up.',
		subject: 'appointment',
		alwaysOn: true,
		availability: enabled,
		configSchema: NO_CONFIG
	},
	{
		key: 'stop.client_reminder_opt_out',
		kind: 'stop',
		label: 'The client turned off visit reminders or is on Do not disturb',
		summary: 'Nothing is sent once the client no longer wants reminders.',
		subject: 'appointment',
		alwaysOn: true,
		availability: enabled,
		configSchema: NO_CONFIG
	}
];

export const AUTOMATION_CATALOG: readonly CatalogEntry[] = [
	...triggers,
	...conditions,
	...waits,
	...actions,
	...stops
];

const CATALOG_BY_KEY = new Map(AUTOMATION_CATALOG.map((entry) => [entry.key, entry]));

export function getCatalogEntry(key: string): CatalogEntry | undefined {
	return CATALOG_BY_KEY.get(key);
}

export function catalogEntriesByKind(kind: CatalogKind): CatalogEntry[] {
	return AUTOMATION_CATALOG.filter((entry) => entry.kind === kind);
}

export function isEnabled(entry: CatalogEntry): boolean {
	return entry.availability.status === 'enabled';
}

// The plain label a list/summary shows for a trigger key; falls back to the raw key so an unknown or
// retired key is never rendered blank.
// The steps that message the customer, counted toward "most messages one customer could get". A review request
// counts once; its reminders come from Review settings and are shown separately.
const CUSTOMER_MESSAGE_ACTION_KEYS = new Set([
	'action.send_email',
	'action.send_sms',
	'action.send_customer_message',
	'action.send_review_request',
	'action.send_appointment_email'
]);

export function sendsCustomerMessage(key: string): boolean {
	return CUSTOMER_MESSAGE_ACTION_KEYS.has(key);
}

export function triggerLabel(key: string | null): string {
	if (!key) return 'No trigger yet';
	return getCatalogEntry(key)?.label ?? key;
}

// The subject a trigger fixes for its recipe, or null when no (known) trigger is chosen yet.
export function triggerSubject(key: string | null | undefined): CatalogSubject | null {
	if (!key) return null;
	const subject = getCatalogEntry(key)?.subject;
	return subject && subject !== 'any' ? subject : null;
}

export function fitsSubject(entry: CatalogEntry, subject: CatalogSubject | null): boolean {
	return entry.subject === 'any' || subject === null || entry.subject === subject;
}

// The stops the engine applies regardless of choice, for a subject.
export function alwaysOnStopKeys(subject: CatalogSubject | null): string[] {
	return AUTOMATION_CATALOG.filter(
		(entry) =>
			entry.kind === 'stop' && entry.alwaysOn && subject !== null && entry.subject === subject
	).map((entry) => entry.key);
}
