import { json, type RequestEvent } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { ownerPackageCommandError } from '$lib/server/packages/owner-package-errors';
import {
	changePackageServiceSchema,
	createPackageServiceSchema,
	packageFieldErrors
} from '$lib/server/validation/package-builder.schema';

// Client onboarding A2 (plan §2.1): Jafar's list of the services Uplift sells. Packages tick services from
// it and setup stages show by them. Services are archived, never deleted, because a published edition may
// still name one. Every command answers with the whole list.

async function readBody(event: RequestEvent) {
	try {
		return { body: (await event.request.json()) as unknown };
	} catch {
		return { response: json({ error: 'Request body must be valid JSON.' }, { status: 400 }) };
	}
}

function answer(
	result: { data: unknown; error: { code?: string; message: string } | null },
	done: string
) {
	if (result.error) {
		const refused = ownerPackageCommandError(result.error);
		if (refused) return refused;
		console.error(`The service could not be ${done}.`, result.error);
		return json({ error: `The service could not be ${done}.` }, { status: 500 });
	}
	return json({ services: result.data });
}

function invalid(error: Parameters<typeof packageFieldErrors>[0]) {
	return json(
		{ error: 'Please review the service.', field_errors: packageFieldErrors(error) },
		{ status: 422 }
	);
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_package_services');
	if (error) {
		console.error('Could not load the service list.', error);
		return json({ error: 'The service list could not be loaded.' }, { status: 500 });
	}
	return json({ services: data }, { headers: { 'cache-control': 'no-store' } });
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const read = await readBody(event);
	if (read.response) return read.response;
	const parsed = createPackageServiceSchema.safeParse(read.body);
	if (!parsed.success) return invalid(parsed.error);

	const result = await getOwnerSupabaseClient().rpc('save_package_service', {
		// A new service has no key yet; the database makes one from the name.
		target_service_key: null as unknown as string,
		service_name: parsed.data.name,
		service_description: parsed.data.description,
		actor_owner_email: session.email
	});
	return answer(result, 'added');
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const read = await readBody(event);
	if (read.response) return read.response;
	const parsed = changePackageServiceSchema.safeParse(read.body);
	if (!parsed.success) return invalid(parsed.error);

	const client = getOwnerSupabaseClient();
	const command = parsed.data;
	if (command.action === 'update') {
		const result = await client.rpc('save_package_service', {
			target_service_key: command.key,
			service_name: command.name,
			service_description: command.description,
			actor_owner_email: session.email
		});
		return answer(result, 'saved');
	}
	const result = await client.rpc('set_package_service_archived', {
		target_service_key: command.key,
		archived: command.action === 'archive',
		actor_owner_email: session.email
	});
	return answer(result, `${command.action}d`);
};
