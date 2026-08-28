import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	WebsiteChatWidgetCommandError,
	createWebsiteChatWidget
} from '$lib/server/communications/website-chat-widget-commands';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	communicationFieldErrors,
	websiteChatWidgetCreateSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	const now = new Date().toISOString();
	const [widgets, origins, allowance, period, authority, organizationSettings] = await Promise.all([
		event.locals.supabase
			.from('website_chat_widgets')
			.select(
				'id, name, launcher_position, teaser_text, greeting_text, contact_requirement, availability_visibility_mode, source_label, privacy_policy_url, channel_options, published, disabled_at, suspended_at, revision, created_at, updated_at'
			)
			.eq('organization_id', organizationId)
			.order('created_at'),
		event.locals.supabase
			.from('website_chat_widget_origins')
			.select('id, widget_id, origin, created_at')
			.eq('organization_id', organizationId)
			.order('created_at'),
		ownerClient.rpc('get_organization_communication_website_chat_allowance', {
			target_organization_id: organizationId,
			at: now
		}),
		ownerClient
			.from('website_chat_allowance_periods')
			.select('id, starts_at, ends_at')
			.eq('organization_id', organizationId)
			.lte('starts_at', now)
			.gt('ends_at', now)
			.order('starts_at', { ascending: false })
			.limit(1)
			.maybeSingle(),
		ownerClient.rpc('get_organization_website_chat_authority', {
			p_organization_id: organizationId
		}),
		ownerClient
			.from('organization_settings')
			.select('brand_color, timezone')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);

	if (
		widgets.error ||
		origins.error ||
		allowance.error ||
		period.error ||
		authority.error ||
		organizationSettings.error
	) {
		console.error(
			'Could not load Website Chat widgets.',
			widgets.error ??
				origins.error ??
				allowance.error ??
				period.error ??
				authority.error ??
				organizationSettings.error
		);
		return json(
			{ error: 'Website Chat widgets could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}

	let acceptedCount = 0;
	if (period.data) {
		const bucket = await ownerClient
			.from('website_chat_capacity_buckets')
			.select('accepted_count')
			.eq('organization_id', organizationId)
			.eq('allowance_period_id', period.data.id)
			.maybeSingle();
		if (bucket.error) {
			console.error('Could not load Website Chat usage.', bucket.error);
			return json(
				{ error: 'Website Chat widgets could not be loaded.' },
				{ status: 500, headers: noStore }
			);
		}
		acceptedCount = bucket.data?.accepted_count ?? 0;
	}

	const originsByWidget = new Map<string, typeof origins.data>();
	for (const origin of origins.data ?? []) {
		const existing = originsByWidget.get(origin.widget_id);
		if (existing) existing.push(origin);
		else originsByWidget.set(origin.widget_id, [origin]);
	}

	const widgetsWithOrigins = (widgets.data ?? []).map((widget) => ({
		...widget,
		origins: originsByWidget.get(widget.id) ?? []
	}));

	const limit = check.access.limits.website_chat_widgets;
	const widgetsUsed = (widgets.data ?? []).filter((widget) => !widget.disabled_at).length;
	const allowanceRow = allowance.data?.[0];
	const authorityData =
		authority.data && typeof authority.data === 'object' && !Array.isArray(authority.data)
			? authority.data
			: {};
	const suspensionData =
		'suspension' in authorityData &&
		authorityData.suspension &&
		typeof authorityData.suspension === 'object' &&
		!Array.isArray(authorityData.suspension)
			? authorityData.suspension
			: null;

	return json(
		{
			widgets: widgetsWithOrigins,
			limit,
			widgets_used: widgetsUsed,
			organization: {
				name: check.auth.organization.name,
				brand_color: organizationSettings.data?.brand_color ?? null,
				timezone: organizationSettings.data?.timezone ?? 'UTC'
			},
			conversation_usage: {
				state: allowanceRow?.effective_state ?? 'not_included',
				value: allowanceRow?.effective_value ?? null,
				source: allowanceRow?.effective_source ?? 'package',
				accepted_count: acceptedCount,
				period_starts_at: period.data?.starts_at ?? null,
				period_ends_at: period.data?.ends_at ?? null
			},
			suspension: suspensionData
				? {
						active: true,
						reason:
							'reason' in suspensionData && typeof suspensionData.reason === 'string'
								? suspensionData.reason
								: null,
						engaged_at:
							'engaged_at' in suspensionData && typeof suspensionData.engaged_at === 'string'
								? suspensionData.engaged_at
								: null
					}
				: { active: false, reason: null, engaged_at: null }
		},
		{ headers: noStore }
	);
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = websiteChatWidgetCreateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the widget details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	try {
		const rateLimit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `website_chat_widget:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const input = parsed.data;
		const widget = await createWebsiteChatWidget(
			event.locals.supabase,
			check.auth.organization.id,
			{
				name: input.name,
				launcherPosition: input.launcher_position,
				teaserText: input.teaser_text,
				greetingText: input.greeting_text,
				contactRequirement: input.contact_requirement,
				availabilityVisibilityMode: input.availability_visibility_mode,
				sourceLabel: input.source_label,
				privacyPolicyUrl: input.privacy_policy_url,
				channelOptions: input.channel_options
			}
		);
		return json({ widget: { ...widget, origins: [] } }, { status: 201, headers: noStore });
	} catch (error) {
		if (error instanceof WebsiteChatWidgetCommandError) {
			return json(
				{ error: error.message, reason: error.reason },
				{ status: error.status, headers: noStore }
			);
		}
		console.error('Could not create the Website Chat widget.', error);
		return json(
			{ error: 'The Website Chat widget could not be created.' },
			{ status: 500, headers: noStore }
		);
	}
};
