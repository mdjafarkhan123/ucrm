import type { LayoutServerLoad } from './$types';
import { requireOwner } from '$lib/server/auth/owner';

export const load: LayoutServerLoad = (event) => ({ owner: requireOwner(event) });
