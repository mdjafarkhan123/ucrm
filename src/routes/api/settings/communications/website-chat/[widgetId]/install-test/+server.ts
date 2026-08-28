import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationFieldErrors,
	websiteChatWidgetInstallTestSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Checks the same exact-match origin allowlist the future public runtime will enforce (WC0.2's plan --
// a plain index scan on website_chat_widget_origins (widget_id, origin), no wildcard matching). This is
// the contractor checking their own installation, never a real visitor -- WC0.5's "invalid domain is a
// behavioral decision, not a visitor-facing screen" applies only to the public runtime, not this tool.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const widgetId = organizationIdSchema.safeParse(event.params.widgetId);
	if (!widgetId.success)
		return json({ error: 'The widget identifier is invalid.' }, { status: 422, headers: noStore });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = websiteChatWidgetInstallTestSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the page URL.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	let origin: string;
	try {
		origin = new URL(parsed.data.url).origin.toLowerCase();
	} catch {
		return json(
			{ error: 'Please review the page URL.', field_errors: { url: 'Enter a valid page URL.' } },
			{ status: 422, headers: noStore }
		);
	}

	const { data, error } = await event.locals.supabase
		.from('website_chat_widget_origins')
		.select('id')
		.eq('organization_id', check.auth.organization.id)
		.eq('widget_id', widgetId.data)
		.eq('origin', origin)
		.maybeSingle();

	if (error) {
		console.error('Could not run the Website Chat install test.', error);
		return json({ error: 'The install test could not run.' }, { status: 500, headers: noStore });
	}

	return json({ origin, allowed: data !== null }, { headers: noStore });
};
