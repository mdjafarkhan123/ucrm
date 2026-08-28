import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Tables } from '$lib/database.types';

type WebsiteChatWidget = Tables<'website_chat_widgets'>;
type WebsiteChatWidgetOrigin = Tables<'website_chat_widget_origins'>;

export class WebsiteChatWidgetCommandError extends Error {
	constructor(
		message: string,
		public readonly status: number,
		public readonly reason: string
	) {
		super(message);
		this.name = 'WebsiteChatWidgetCommandError';
	}
}

// The commands check private.has_permission and the entitlement cap themselves (they are called with
// the signed-in session's own client, not a service-role client), so this only needs to translate the
// SQLSTATE codes they can raise into the same shape sender-commands.ts uses for its own database errors.
function databaseCommandError(error: { code?: string; message?: string }): never {
	const message = error.message ?? '';
	if (error.code === '42501')
		throw new WebsiteChatWidgetCommandError(
			'You do not have access to manage Website Chat.',
			403,
			'permission_denied'
		);
	if (error.code === '23514' && message.includes('No Website Chat widgets are available'))
		throw new WebsiteChatWidgetCommandError(
			'No Website Chat widgets are available for your plan.',
			409,
			'at_cap'
		);
	if (error.code === '23514')
		throw new WebsiteChatWidgetCommandError(
			message || 'That Website Chat change is not valid.',
			422,
			'not_eligible'
		);
	if (error.code === '23505')
		throw new WebsiteChatWidgetCommandError(
			message || 'That domain is already allowed for this widget.',
			409,
			'conflict'
		);
	if (error.code === '40001')
		throw new WebsiteChatWidgetCommandError(
			'Someone else changed this widget while you were editing. Reload and try again.',
			409,
			'stale_revision'
		);
	throw error;
}

export type WebsiteChatWidgetDraft = {
	name: string;
	launcherPosition: string;
	teaserText: string | null;
	greetingText: string | null;
	contactRequirement: string;
	availabilityVisibilityMode: string;
	sourceLabel: string | null;
	privacyPolicyUrl: string | null;
	channelOptions: unknown;
};

export async function createWebsiteChatWidget(
	client: SupabaseClient<Database>,
	organizationId: string,
	input: WebsiteChatWidgetDraft
): Promise<WebsiteChatWidget> {
	const result = await client.rpc('create_website_chat_widget', {
		target_organization_id: organizationId,
		new_name: input.name,
		new_launcher_position: input.launcherPosition,
		// Postgres accepts NULL for these optional text params; generated RPC argument types do not
		// preserve function-argument nullability (same cast sender-commands.ts already needs).
		new_teaser_text: input.teaserText as string,
		new_greeting_text: input.greetingText as string,
		new_contact_requirement: input.contactRequirement,
		new_availability_visibility_mode: input.availabilityVisibilityMode,
		new_source_label: input.sourceLabel as string,
		new_privacy_policy_url: input.privacyPolicyUrl as string,
		new_channel_options: input.channelOptions as never
	});
	if (result.error) databaseCommandError(result.error);
	return result.data as unknown as WebsiteChatWidget;
}

export async function updateWebsiteChatWidget(
	client: SupabaseClient<Database>,
	organizationId: string,
	widgetId: string,
	input: WebsiteChatWidgetDraft & {
		expectedRevision: number;
		published: boolean;
		disabled: boolean;
	}
): Promise<WebsiteChatWidget> {
	const result = await client.rpc('update_website_chat_widget', {
		target_organization_id: organizationId,
		target_widget_id: widgetId,
		expected_revision: input.expectedRevision,
		new_name: input.name,
		new_launcher_position: input.launcherPosition,
		new_teaser_text: input.teaserText as string,
		new_greeting_text: input.greetingText as string,
		new_contact_requirement: input.contactRequirement,
		new_availability_visibility_mode: input.availabilityVisibilityMode,
		new_source_label: input.sourceLabel as string,
		new_privacy_policy_url: input.privacyPolicyUrl as string,
		new_channel_options: input.channelOptions as never,
		new_published: input.published,
		new_disabled: input.disabled
	});
	if (result.error) databaseCommandError(result.error);
	return result.data as unknown as WebsiteChatWidget;
}

export async function addWebsiteChatWidgetOrigin(
	client: SupabaseClient<Database>,
	organizationId: string,
	widgetId: string,
	origin: string
): Promise<WebsiteChatWidgetOrigin> {
	const result = await client.rpc('add_website_chat_widget_origin', {
		target_organization_id: organizationId,
		target_widget_id: widgetId,
		new_origin: origin
	});
	if (result.error) databaseCommandError(result.error);
	return result.data as unknown as WebsiteChatWidgetOrigin;
}

export async function removeWebsiteChatWidgetOrigin(
	client: SupabaseClient<Database>,
	organizationId: string,
	widgetId: string,
	originId: string
): Promise<void> {
	const result = await client.rpc('remove_website_chat_widget_origin', {
		target_organization_id: organizationId,
		target_widget_id: widgetId,
		target_origin_id: originId
	});
	if (result.error) databaseCommandError(result.error);
}
