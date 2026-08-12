import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { freeAccessChangeSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const eventSelect =
	'id, organization_id, package_version_id, action, access_until_date, reason, actor_kind, actor_owner_email, occurred_at, created_at';

type FreeAccessEvent = {
	action: 'grant' | 'extend' | 'convert_to_forever' | 'end';
	access_until_date: string | null;
	package_version_id: string;
	[key: string]: unknown;
};

function todayInTimeZone(timezone: string | undefined) {
	try {
		return new Intl.DateTimeFormat('en-CA', {
			timeZone: timezone || 'UTC',
			year: 'numeric',
			month: '2-digit',
			day: '2-digit'
		}).format(new Date());
	} catch {
		return new Date().toISOString().slice(0, 10);
	}
}

function summarize(events: FreeAccessEvent[], timezone?: string) {
	const latest = events[0] ?? null;
	if (!latest || latest.action === 'end') {
		return { status: 'paid', access_until_date: null, package_version_id: null, latest };
	}

	const expired =
		latest.access_until_date !== null && latest.access_until_date < todayInTimeZone(timezone);
	return {
		status: expired ? 'expired' : latest.access_until_date ? 'until_date' : 'forever',
		access_until_date: latest.access_until_date,
		package_version_id: latest.package_version_id,
		latest
	};
}

async function getOrganizationState(organizationId: string) {
	const client = getOwnerSupabaseClient();
	const [
		{ data: organization, error: organizationError },
		{ data: settings, error: settingsError },
		{ data: assignment, error: assignmentError },
		{ data: events, error: eventsError }
	] = await Promise.all([
		client.from('organizations').select('id, name').eq('id', organizationId).maybeSingle(),
		client
			.from('organization_settings')
			.select('timezone')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client
			.from('organization_package_assignments')
			.select('id, package_version_id, effective_at, assignment_source, reason')
			.eq('organization_id', organizationId)
			.order('effective_at', { ascending: false })
			.limit(1)
			.maybeSingle(),
		client
			.from('organization_free_access_events')
			.select(eventSelect)
			.eq('organization_id', organizationId)
			.order('occurred_at', { ascending: false })
			.order('id', { ascending: false })
	]);

	if (organizationError) throw organizationError;
	if (settingsError) throw settingsError;
	if (assignmentError) throw assignmentError;
	if (eventsError) throw eventsError;
	if (!organization) return null;

	return {
		organization,
		assignment,
		events: (events ?? []) as FreeAccessEvent[],
		free_access: summarize((events ?? []) as FreeAccessEvent[], settings?.timezone)
	};
}

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const state = await getOrganizationState(parsedId.data);
		return state ? json(state) : json({ error: 'Organization was not found.' }, { status: 404 });
	} catch (error) {
		console.error('Could not load organization free access.', error);
		return json({ error: 'Free access could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
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
	const parsed = freeAccessChangeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the free access change.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const grantsForeverAccess =
		parsed.data.action === 'convert_to_forever' ||
		((parsed.data.action === 'grant' || parsed.data.action === 'extend') &&
			!parsed.data.access_until_date);
	if (grantsForeverAccess && !consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before granting permanent free access.',
				step_up_required: true
			},
			{ status: 403 }
		);
	}

	try {
		const state = await getOrganizationState(parsedId.data);
		if (!state) return json({ error: 'Organization was not found.' }, { status: 404 });
		if (!state.assignment) {
			return json(
				{ error: 'Assign a published package version before granting free access.' },
				{ status: 409 }
			);
		}
		if (parsed.data.action === 'extend' && state.free_access.status === 'paid') {
			return json({ error: 'Free access is not active for this organization.' }, { status: 409 });
		}

		const client = getOwnerSupabaseClient();
		const { data: created, error } = await client
			.from('organization_free_access_events')
			.insert({
				organization_id: parsedId.data,
				package_version_id: state.assignment.package_version_id,
				action: parsed.data.action,
				access_until_date: parsed.data.access_until_date ?? null,
				reason: parsed.data.reason,
				actor_owner_email: session.email
			})
			.select(eventSelect)
			.single();
		if (error) throw error;

		const next = await getOrganizationState(parsedId.data);
		return json({ event: created, ...(next ?? {}) });
	} catch (error) {
		console.error('Could not change organization free access.', error);
		return json({ error: 'Free access could not be changed.' }, { status: 500 });
	}
};
