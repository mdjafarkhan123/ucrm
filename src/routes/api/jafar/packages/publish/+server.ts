import type { RequestHandler } from './$types';
import { packageSystemRebuilding } from '$lib/server/packages/rebuilding';

export const POST: RequestHandler = (event) => packageSystemRebuilding(event);
