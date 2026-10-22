import type { SupabaseClient } from '@supabase/supabase-js';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getStripeConnectionStatus } from '$lib/server/payments/stripe-connection';
import { organizationLogoUrl } from '$lib/server/settings/logo';
import { businessHoursIsSet } from '$lib/server/settings/readiness';
import type { SettingsHomeSummary } from '$lib/settings/api';

// What the Settings home says about each setting right now ("GST 5% default", "84 items", "Mon–Fri 8–5").
// Every figure is its own small read, and a read that fails leaves just that value empty: the row still
// shows and opens, it only loses its caption. A member is only asked about what they may open.

export type SummaryPermissions = {
	team_manage: boolean;
	communications_manage: boolean;
	snippets_manage: boolean;
	taxes_manage: boolean;
	price_book_manage: boolean;
	checklists_manage: boolean;
	forms_manage: boolean;
	reviews_manage: boolean;
	invoices_manage: boolean;
	payments_manage: boolean;
	pipeline_view: boolean;
	automations_view: boolean;
};

type Facts = {
	organizationId: string;
	supabase: SupabaseClient;
	permissions: SummaryPermissions;
};

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

async function safe<T>(read: PromiseLike<T>, fallback: T): Promise<T> {
	try {
		return await read;
	} catch (error) {
		console.error('Could not read one Settings home figure.', error);
		return fallback;
	}
}

async function count(
	read: PromiseLike<{ count: number | null; error: unknown }>
): Promise<number | null> {
	return safe(
		Promise.resolve(read).then((result) => (result.error ? null : (result.count ?? 0))),
		null
	);
}

function shortTime(time: string) {
	const [hours, minutes] = time.split(':').map(Number);
	const suffix = hours >= 12 ? 'PM' : 'AM';
	const hour = hours % 12 === 0 ? 12 : hours % 12;
	return minutes ? `${hour}:${String(minutes).padStart(2, '0')} ${suffix}` : `${hour} ${suffix}`;
}

type HourRow = {
	weekday: number;
	is_open: boolean;
	is_open_24h: boolean;
	opens_at: string | null;
	closes_at: string | null;
	period_index: number;
};

// "9–5": the short form the hours row uses, where AM and PM would make it too long to fit.
function bareTime(time: string) {
	const [hours, minutes] = time.split(':').map(Number);
	const hour = hours % 12 === 0 ? 12 : hours % 12;
	return minutes ? `${hour}:${String(minutes).padStart(2, '0')}` : `${hour}`;
}

function periodsText(rows: HourRow[], short = false) {
	if (rows.some((row) => row.is_open_24h)) return 'Open 24 hours';
	return rows
		.filter((row) => row.is_open && row.opens_at && row.closes_at)
		.sort((a, b) => a.period_index - b.period_index)
		.map((row) =>
			short
				? `${bareTime(row.opens_at!)}–${bareTime(row.closes_at!)}`
				: `${shortTime(row.opens_at!)} – ${shortTime(row.closes_at!)}`
		)
		.join(', ');
}

// "Mon–Fri 8 AM – 5 PM": consecutive days with the same hours are joined; more than one pattern says
// how many days are open instead.
export function hoursSummary(rows: HourRow[]): string {
	const byDay = new Map<number, HourRow[]>();
	for (const row of rows) byDay.set(row.weekday, [...(byDay.get(row.weekday) ?? []), row]);
	const open = [...byDay.entries()]
		.map(([day, dayRows]) => ({ day, text: periodsText(dayRows, true) }))
		.filter((entry) => entry.text)
		.sort((a, b) => a.day - b.day);
	if (open.length === 0) return 'Closed all week';
	const texts = new Set(open.map((entry) => entry.text));
	if (texts.size > 1) return `Open ${open.length} days`;
	const days = open.map((entry) => entry.day);
	const runs: number[][] = [];
	for (const day of days) {
		const last = runs[runs.length - 1];
		if (last && day === last[last.length - 1] + 1) last.push(day);
		else runs.push([day]);
	}
	const label =
		days.length === 7
			? 'Every day'
			: runs
					.map((run) =>
						run.length > 2
							? `${WEEKDAYS[run[0]]}–${WEEKDAYS[run[run.length - 1]]}`
							: run.map((day) => WEEKDAYS[day]).join(', ')
					)
					.join(', ');
	return `${label} ${open[0].text}`;
}

export function openTodayText(rows: HourRow[], timezone: string, now = new Date()): string | null {
	let weekdayName: string;
	try {
		weekdayName = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: timezone }).format(
			now
		);
	} catch {
		return null;
	}
	const weekday = WEEKDAYS.indexOf(weekdayName);
	if (weekday < 0) return null;
	return periodsText(rows.filter((row) => row.weekday === weekday)) || 'Closed today';
}

function plural(amount: number, one: string, many = `${one}s`) {
	return `${amount} ${amount === 1 ? one : many}`;
}

export async function loadSettingsHomeSummary(facts: Facts): Promise<SettingsHomeSummary> {
	const { organizationId, supabase, permissions } = facts;
	const owner = getOwnerSupabaseClient();
	const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
	const active = <T>(run: () => T, allowed: boolean) => (allowed ? run() : null);

	const [
		settings,
		hours,
		taxRate,
		invoiceTerm,
		products,
		checklists,
		customStages,
		members,
		activity,
		senders,
		chatSites,
		forms,
		templates,
		snippets,
		blocked,
		automations,
		review,
		stripe
	] = await Promise.all([
		safe(
			Promise.resolve(
				supabase
					.from('organization_settings')
					.select(
						'trade, phone, website, address_line1, city, region, timezone, currency_code, brand_color, logo_object_key, branding_revision, service_area_radius_miles, hours_mode, tax_default_source, tax_default_rate_id, quote_require_customer_signature, invoice_default_term_residential_id, contact_match_priority'
					)
					.eq('organization_id', organizationId)
					.maybeSingle()
			).then((result) => result.data),
			null
		),
		safe(
			Promise.resolve(
				supabase
					.from('organization_business_hours')
					.select('weekday, is_open, is_open_24h, opens_at, closes_at, period_index')
					.eq('organization_id', organizationId)
			).then((result) => (result.data ?? []) as HourRow[]),
			[] as HourRow[]
		),
		active(
			() =>
				safe(
					Promise.resolve(
						supabase
							.from('organization_tax_rates')
							.select('id, name, rate_basis_points')
							.eq('organization_id', organizationId)
							.eq('is_active', true)
					).then((result) => result.data ?? []),
					[] as Array<{ id: string; name: string; rate_basis_points: number }>
				),
			permissions.taxes_manage
		),
		active(
			() =>
				safe(
					Promise.resolve(
						supabase
							.from('invoice_payment_terms')
							.select('id, name')
							.eq('organization_id', organizationId)
							.is('archived_at', null)
					).then((result) => result.data ?? []),
					[] as Array<{ id: string; name: string }>
				),
			permissions.invoices_manage
		),
		active(
			() =>
				count(
					supabase
						.from('catalog_items')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
						.is('archived_at', null)
				),
			permissions.price_book_manage
		),
		active(
			() =>
				count(
					supabase
						.from('checklist_templates')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
						.is('archived_at', null)
				),
			permissions.checklists_manage
		),
		active(
			() =>
				count(
					supabase
						.from('pipeline_custom_stages')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
						.is('disabled_at', null)
				),
			permissions.pipeline_view
		),
		active(
			() =>
				safe(
					Promise.resolve(
						supabase
							.from('organization_members')
							.select('role')
							.eq('organization_id', organizationId)
							.eq('status', 'active')
					).then((result) => (result.error ? null : (result.data ?? []))),
					null as Array<{ role: string }> | null
				),
			permissions.team_manage
		),
		active(
			() =>
				count(
					supabase
						.from('organization_member_access_events')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
						.gte('created_at', weekAgo)
				),
			permissions.team_manage
		),
		active(
			() =>
				safe(
					Promise.resolve(
						owner
							.from('communication_email_senders')
							.select('email_address, is_organization_default')
							.eq('organization_id', organizationId)
							.eq('lifecycle_state', 'enabled')
					).then((result) => (result.error ? null : (result.data ?? []))),
					null as Array<{ email_address: string; is_organization_default: boolean }> | null
				),
			permissions.communications_manage
		),
		active(
			() =>
				count(
					owner
						.from('website_chat_widgets')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
						.eq('published', true)
						.is('disabled_at', null)
				),
			permissions.communications_manage
		),
		active(
			() =>
				count(
					supabase
						.from('forms')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
						.eq('is_enabled', true)
						.is('archived_at', null)
				),
			permissions.forms_manage
		),
		active(
			() =>
				count(
					owner
						.from('communications_email_templates')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
				),
			permissions.communications_manage
		),
		active(
			() =>
				count(
					owner
						.from('communications_snippets')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
				),
			permissions.snippets_manage
		),
		active(
			() =>
				safe(
					Promise.resolve(
						owner.rpc('get_communication_email_blocked_addresses', {
							p_organization_id: organizationId
						})
					).then((result) =>
						result.error
							? null
							: ((result.data as { blocked_total?: number } | null)?.blocked_total ?? 0)
					),
					null as number | null
				),
			permissions.communications_manage
		),
		active(
			() =>
				count(
					owner
						.from('automation_recipes')
						.select('id', { count: 'exact', head: true })
						.eq('organization_id', organizationId)
						.eq('status', 'active')
				),
			permissions.automations_view
		),
		active(
			() =>
				safe(
					Promise.resolve(
						owner
							.from('review_settings')
							.select('google_review_url')
							.eq('organization_id', organizationId)
							.maybeSingle()
					).then((result) => Boolean(result.data?.google_review_url)),
					null as boolean | null
				),
			permissions.reviews_manage
		),
		active(
			() =>
				safe(
					getStripeConnectionStatus(organizationId).then((status) => status.connected),
					null as boolean | null
				),
			permissions.payments_manage
		)
	]);

	const timezone = settings?.timezone ?? 'UTC';
	const defaultTax =
		settings?.tax_default_source === 'rate' && settings.tax_default_rate_id
			? taxRate?.find((rate) => rate.id === settings.tax_default_rate_id)
			: null;
	const defaultTerm =
		invoiceTerm?.find((term) => term.id === settings?.invoice_default_term_residential_id) ?? null;
	const roles = members ? new Set(members.map((member) => member.role)).size : null;
	const address = [settings?.address_line1].filter(Boolean).join(', ');
	const place = [settings?.city, settings?.region].filter(Boolean).join(', ');

	const business = {
		phone: settings?.phone ?? null,
		email:
			(senders?.find((sender) => sender.is_organization_default) ?? senders?.[0])?.email_address ??
			null,
		website: settings?.website ?? null,
		place: place || null,
		trade: settings?.trade ?? null,
		address: address || null,
		timezone,
		currency_code: settings?.currency_code ?? null,
		service_radius_miles: settings?.service_area_radius_miles ?? null,
		open_today: hours.length ? openTodayText(hours, timezone) : null,
		logo_url: settings?.logo_object_key
			? organizationLogoUrl(settings.branding_revision ?? 0)
			: null,
		brand_color: settings?.brand_color ?? null
	};

	const values: SettingsHomeSummary['values'] = {
		branding: settings ? (settings.logo_object_key ? 'Logo added' : 'No logo yet') : null,
		hours:
			settings && businessHoursIsSet(settings.hours_mode)
				? settings.hours_mode === 'appointment_only'
					? 'By appointment'
					: hoursSummary(hours)
				: null,
		taxes: defaultTax
			? `${defaultTax.name} ${Number((defaultTax.rate_basis_points / 100).toFixed(3))}% default`
			: taxRate
				? 'No default'
				: null,
		quotes: settings
			? settings.quote_require_customer_signature
				? 'Signature required'
				: 'Signature optional'
			: null,
		invoices: defaultTerm ? defaultTerm.name : null,
		products: products === null ? null : plural(products, 'item'),
		checklists: checklists === null ? null : plural(checklists, 'list'),
		pipeline:
			customStages === null
				? null
				: customStages === 0
					? 'Standard stages'
					: plural(customStages, 'custom stage'),
		team: members ? plural(members.length, 'person', 'people') : null,
		roles: roles === null ? null : plural(roles, 'role'),
		activity: activity === null ? null : `${activity} this week`,
		website_chat:
			chatSites === null ? null : chatSites === 0 ? 'Off' : `On ${plural(chatSites, 'site')}`,
		request_forms: forms === null ? null : `${forms} live`,
		email_templates: templates === null ? null : `${templates} saved`,
		snippets: snippets === null ? null : `${snippets} saved`,
		contact_matching: settings
			? settings.contact_match_priority === 'phone'
				? 'Phone first'
				: 'Email first'
			: null,
		blocked_addresses: blocked === null ? null : `${blocked} blocked`,
		automations: automations === null ? null : `${automations} running`
	};

	return {
		business,
		values,
		signals: {
			logo: settings ? Boolean(settings.logo_object_key) : null,
			profile_details: settings
				? Boolean(settings.trade && (settings.phone || settings.website) && place)
				: null,
			tax_default: taxRate ? Boolean(defaultTax) : null,
			products: products,
			team_members: members ? members.length : null,
			request_forms: forms,
			email_verified: senders === null ? null : senders.length > 0,
			payments_connected: stripe,
			review_link: review
		}
	};
}
