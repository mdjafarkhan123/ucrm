import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	packageExceptionCommandSchema,
	zodOwnerFieldErrors,
	type PackageExceptionCommand
} from '$lib/server/validation/owner.schema';

// Package builder P8b: temporary exceptions on the Access tab. Each switches one feature on or off, or sets
// one limit, with a reason, a start, and an end; ending one early keeps its record. The exception rows and
// the commercial event the database writes record who acted and why.

async function loadExceptions(organizationId: string) {
	const { data, error } = await getOwnerSupabaseClient().rpc(
		'owner_organization_package_exceptions',
		{ target_organization_id: organizationId }
	);
	if (error) throw error;
	return data ?? [];
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const exceptions = await loadExceptions(parsedId.data);
		return json({ exceptions }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load package exceptions.', error);
		return json({ error: 'Exceptions could not be loaded.' }, { status: 500 });
	}
};

function runCommand(organizationId: string, email: string, command: PackageExceptionCommand) {
	const client = getOwnerSupabaseClient();
	const common = {
		target_organization_id: organizationId,
		actor_owner_email: email,
		idempotency_key: command.idempotency_key,
		reason: command.reason
	};
	if (command.action === 'end')
		return client.rpc('end_organization_package_exception', {
			...common,
			exception_id: command.exception_id
		});
	// The database command takes every argument and ignores the side not chosen; the generated types
	// don't mark them nullable, so the unused ones are passed as null explicitly.
	const isCapability = command.target === 'capability';
	const absent = null as unknown as string;
	return client.rpc('add_organization_package_exception', {
		...common,
		capability_key: isCapability ? command.key : absent,
		capability_state: isCapability ? (command.capability_state ?? absent) : absent,
		allowance_key: isCapability ? absent : command.key,
		allowance_state: isCapability ? absent : (command.allowance_state ?? absent),
		allowance_value:
			!isCapability && command.allowance_state === 'numeric'
				? (command.allowance_value ?? 0)
				: (null as unknown as number),
		starts_at: command.starts_at,
		ends_at: command.ends_at
	});
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = packageExceptionCommandSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{
				error: 'Please review the exception.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	try {
		const { data: organization, error: organizationError } = await getOwnerSupabaseClient()
			.from('organizations')
			.select('id')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		const result = await runCommand(parsedId.data, session.email, parsed.data);
		if (result.error) {
			if (['23503', '23505', '23514'].includes(result.error.code))
				return json({ error: result.error.message }, { status: 409 });
			throw result.error;
		}

		const exceptions = await loadExceptions(parsedId.data);
		return json({ command: result.data, exceptions }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not record the package exception.', error);
		return json({ error: 'The exception could not be recorded.' }, { status: 500 });
	}
};
