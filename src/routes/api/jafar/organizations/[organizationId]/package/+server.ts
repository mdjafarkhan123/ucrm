import type { RequestHandler } from './$types';
import { packageSystemRebuilding } from '$lib/server/packages/rebuilding';

export const PATCH: RequestHandler = (event) => packageSystemRebuilding(event);
