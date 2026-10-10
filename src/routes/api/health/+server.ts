import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

// Liveness: the Node process is up and answering. It touches nothing else, so a slow database can never make
// the container look dead and get it restarted. Docker's HEALTHCHECK and the external reachability monitor
// call this. It reveals nothing about the system.
export const GET: RequestHandler = () =>
	json({ status: 'ok' }, { headers: { 'cache-control': 'no-store' } });
