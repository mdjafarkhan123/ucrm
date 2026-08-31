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
import { automationEmailBodySchema, automationEmailSubjectSchema } from './email-variables';

export const AUTOMATION_SCHEMA_VERSION = 1;

export type CatalogKind = 'trigger' | 'condition' | 'wait' | 'action' | 'stop';

export type CatalogAvailability = { status: 'enabled' } | { status: 'blocked'; reason: string };

export type CatalogEntry = {
	key: string;
	kind: CatalogKind;
	label: string;
	summary: string;
	// v1 recipes all act on a Quote. Kept explicit so a later subject cannot be added by accident.
	subject: 'quote';
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
		summary: 'Waits a set number of days or hours before the next step.',
		subject: 'quote',
		availability: enabled,
		// Local send window is applied by the engine (6D); here we only fix a positive delay.
		configSchema: z
			.object({ unit: z.enum(['hours', 'days']), amount: z.number().int().min(1).max(2160) })
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
		summary: 'Sends a follow-up text to the customer.',
		subject: 'quote',
		availability: blocked('Text messaging is not available yet.'),
		configSchema: z.object({ body: z.string().trim().min(1).max(1000) }).strict()
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

const stops: CatalogEntry[] = stopKeys.map(({ key, label }) => ({
	key,
	kind: 'stop' as const,
	label,
	summary: 'Stops the automation for that quote.',
	subject: 'quote' as const,
	availability: enabled,
	configSchema: NO_CONFIG
}));

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
export function triggerLabel(key: string | null): string {
	if (!key) return 'No trigger yet';
	return getCatalogEntry(key)?.label ?? key;
}
