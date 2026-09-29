import type { RequestHandler } from './$types';
import { packageSystemRebuilding } from '$lib/server/packages/rebuilding';

export const PUT: RequestHandler = (event) => packageSystemRebuilding(event);
export const DELETE: RequestHandler = (event) => packageSystemRebuilding(event);
