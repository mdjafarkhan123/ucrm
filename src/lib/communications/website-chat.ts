export type WebsiteChatWidgetOrigin = {
	id: string;
	widget_id: string;
	origin: string;
	created_at: string;
};

export type WebsiteChatChannelOption = {
	type: 'whatsapp' | 'messenger';
	destination: string;
};

export type WebsiteChatWidget = {
	id: string;
	name: string;
	launcher_position: string;
	teaser_text: string | null;
	greeting_text: string | null;
	contact_requirement: string;
	availability_visibility_mode: string;
	source_label: string | null;
	privacy_policy_url: string | null;
	channel_options: WebsiteChatChannelOption[];
	published: boolean;
	disabled_at: string | null;
	suspended_at: string | null;
	revision: number;
	created_at: string;
	updated_at: string;
	origins: WebsiteChatWidgetOrigin[];
};

export type WebsiteChatWidgetLimit = {
	state: 'unlimited' | 'not_included' | 'numeric';
	value: number | null;
	is_unlimited: boolean;
	source: 'package' | 'override';
};

export type WebsiteChatWidgets = {
	widgets: WebsiteChatWidget[];
	limit: WebsiteChatWidgetLimit;
	widgets_used: number;
	organization: {
		name: string;
		brand_color: string | null;
		timezone: string;
	};
	conversation_usage: {
		state: 'unlimited' | 'not_included' | 'numeric';
		value: number | null;
		source: 'package' | 'override';
		accepted_count: number;
		period_starts_at: string | null;
		period_ends_at: string | null;
	};
	suspension: {
		active: boolean;
		reason: string | null;
		engaged_at: string | null;
	};
};

export type WebsiteChatWidgetDraft = {
	name: string;
	launcher_position: string;
	teaser_text: string | null;
	greeting_text: string | null;
	contact_requirement: string;
	availability_visibility_mode: string;
	source_label: string | null;
	privacy_policy_url: string | null;
	channel_options: WebsiteChatChannelOption[];
};

export class WebsiteChatWidgetWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {},
		public readonly reason: string = 'unknown'
	) {
		super(message);
		this.name = 'WebsiteChatWidgetWriteError';
	}
}

export const websiteChatWidgetsKey = ['settings', 'communications', 'website-chat'] as const;

export async function fetchWebsiteChatWidgets(): Promise<WebsiteChatWidgets> {
	const response = await fetch('/api/settings/communications/website-chat');
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'Website Chat widgets could not be loaded.');
	return result as WebsiteChatWidgets;
}

async function writeWidget(url: string, method: 'POST' | 'PATCH', body: object) {
	const response = await fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new WebsiteChatWidgetWriteError(
			result.error ?? 'The widget could not be saved.',
			result.field_errors ?? {},
			result.reason ?? 'unknown'
		);
	return result as { widget: WebsiteChatWidget };
}

export function createWebsiteChatWidget(draft: WebsiteChatWidgetDraft) {
	return writeWidget('/api/settings/communications/website-chat', 'POST', draft);
}

export function updateWebsiteChatWidget(
	widgetId: string,
	draft: WebsiteChatWidgetDraft & {
		expected_revision: number;
		published: boolean;
		disabled: boolean;
	}
) {
	return writeWidget(`/api/settings/communications/website-chat/${widgetId}`, 'PATCH', draft);
}

export async function addWebsiteChatWidgetOrigin(widgetId: string, origin: string) {
	const response = await fetch(`/api/settings/communications/website-chat/${widgetId}/origins`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ origin })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new WebsiteChatWidgetWriteError(
			result.error ?? 'The domain could not be added.',
			result.field_errors ?? {},
			result.reason ?? 'unknown'
		);
	return result as { origin: WebsiteChatWidgetOrigin };
}

export async function removeWebsiteChatWidgetOrigin(widgetId: string, originId: string) {
	const response = await fetch(
		`/api/settings/communications/website-chat/${widgetId}/origins/${originId}`,
		{ method: 'DELETE' }
	);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new WebsiteChatWidgetWriteError(result.error ?? 'The domain could not be removed.');
}

export async function testWebsiteChatWidgetInstall(widgetId: string, url: string) {
	const response = await fetch(
		`/api/settings/communications/website-chat/${widgetId}/install-test`,
		{
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ url })
		}
	);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new WebsiteChatWidgetWriteError(
			result.error ?? 'The install test could not run.',
			result.field_errors ?? {}
		);
	return result as { origin: string; allowed: boolean };
}
