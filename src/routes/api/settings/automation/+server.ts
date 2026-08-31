import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

// Settings → Automation, the contractor read. The single Automation access decision drives it; this route
// adds no entitlement, permission, authority, or limit logic of its own. It is also the direct-route denial
// surface: a plan without Automation returns 403 not_included, a member without view returns 403
// permission_denied, and a suspended or operationally disabled organization that still has view keeps its
// read-only access rather than being turned away. No recipe data exists in 6B — only the access shell.
export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;
	return json(check.automation, { headers: PRIVATE_READ_HEADERS });
};
