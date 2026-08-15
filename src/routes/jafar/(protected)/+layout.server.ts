import type { LayoutServerLoad } from './$types';
import { requireOwner } from '$lib/server/auth/owner';

export const load: LayoutServerLoad = async (event) => ({ owner: await requireOwner(event) });
