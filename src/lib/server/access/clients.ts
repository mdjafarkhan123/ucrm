import type { RequestEvent } from '@sveltejs/kit';
import { requireOrganizationPermission } from '$lib/server/access/permission';

// Kept as its own name because the client and property routes read better this way. The rule itself
// lives in one place, so every area of the app refuses access the same way.
export async function requireClientPermission(event: RequestEvent, permissionKey: string) {
	return requireOrganizationPermission(event, permissionKey);
}
