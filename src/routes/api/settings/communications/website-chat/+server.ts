import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
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
	const [widgets, origins] = await Promise.all([
		event.locals.supabase
			.from('website_chat_widgets')
			.select(
				'id, name, launcher_position, teaser_text, greeting_text, contact_requirement, availability_visibility_mode, source_label, privacy_policy_url, channel_options, published, disabled_at, revision, created_at, updated_at'
			)
			.eq('organization_id', organizationId)
			.order('created_at'),
		event.locals.supabase
			.from('website_chat_widget_origins')
			.select('id, widget_id, origin, created_at')
			.eq('organization_id', organizationId)
			.order('created_at')
	]);

	if (widgets.error || origins.error) {
		console.error('Could not load Website Chat widgets.', widgets.error ?? origins.error);
		return json(
			{ error: 'Website Chat widgets could not be loaded.' },
			{ status: 500, headers: noStore }
		);
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

	return json(
		{ widgets: widgetsWithOrigins, limit, widgets_used: widgetsUsed },
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
