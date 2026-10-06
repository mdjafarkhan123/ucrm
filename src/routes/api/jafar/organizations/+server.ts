import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationDirectoryQuerySchema,
	type OrganizationDirectoryQuery
} from '$lib/server/validation/organization-directory.schema';
import { NO_PACKAGE } from '$lib/jafar/organization-directory-filters';

type DirectoryCursor = { created_at: string; id: string };

function encodeCursor(cursor: DirectoryCursor): string {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

function decodeCursor(value: string): DirectoryCursor | null {
	try {
		const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
		if (parsed && typeof parsed.created_at === 'string' && typeof parsed.id === 'string') {
			return parsed;
		}
		return null;
	} catch {
		return null;
	}
}

const DAY_MS = 24 * 60 * 60 * 1000;

// "Joined" is a window on the day an organization was created. A preset counts back from now; a custom range
// is whole days, both ends included, so the end becomes the start of the following day.
function joinedRange(query: OrganizationDirectoryQuery) {
	if (query.joined === 'custom') {
		return {
			joinedFrom: query.from ? `${query.from}T00:00:00Z` : undefined,
			joinedBefore: query.to
				? new Date(Date.parse(`${query.to}T00:00:00Z`) + DAY_MS).toISOString()
				: undefined
		};
	}
	if (query.joined) {
		return {
			joinedFrom: new Date(Date.now() - Number(query.joined) * DAY_MS).toISOString(),
			joinedBefore: undefined
		};
	}
	return { joinedFrom: undefined, joinedBefore: undefined };
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const query = event.url.searchParams;
	const parsed = organizationDirectoryQuerySchema.safeParse({
		search: query.get('search') ?? undefined,
		attention_reason: query.get('attention_reason') ?? undefined,
		lifecycle: query.get('lifecycle') ?? undefined,
		package: query.get('package') ?? undefined,
		billing: query.get('billing') ?? undefined,
		renews: query.get('renews') ?? undefined,
		team: query.get('team') ?? undefined,
		joined: query.get('joined') ?? undefined,
		from: query.get('from') ?? undefined,
		to: query.get('to') ?? undefined,
		cursor: query.get('cursor') ?? undefined,
		limit: query.get('limit') ?? undefined
	});
	if (!parsed.success)
		return json({ error: 'The organization directory filter is invalid.' }, { status: 422 });

	let cursor: DirectoryCursor | null = null;
	if (parsed.data.cursor) {
		cursor = decodeCursor(parsed.data.cursor);
		if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	}

	const filters = parsed.data;
	const packageIds = (filters.package ?? []).filter((value) => value !== NO_PACKAGE);
	const { joinedFrom, joinedBefore } = joinedRange(filters);

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_organization_directory', {
			search_term: filters.search ?? undefined,
			attention_filter: filters.attention_reason,
			cursor_created_at: cursor?.created_at ?? undefined,
			cursor_id: cursor?.id ?? undefined,
			page_size: filters.limit ?? 50,
			lifecycle_filter: filters.lifecycle,
			package_filter: packageIds.length ? packageIds : undefined,
			no_package_filter: filters.package?.includes(NO_PACKAGE) ?? false,
			billing_filter: filters.billing,
			renews_filter: filters.renews,
			joined_from_filter: joinedFrom,
			joined_before_filter: joinedBefore,
			team_size_filter: filters.team
		});
		if (error) throw error;

		const result = data as {
			organizations: Array<{
				id: string;
				name: string;
				slug: string;
				lifecycle_status: string;
				created_at: string;
				updated_at: string;
				member_count: number;
				attention_reasons: string[];
				package: {
					package_id: string;
					name: string;
					edition_number: number | null;
					billing_interval: 'month' | 'year';
				} | null;
			}>;
			next_cursor: DirectoryCursor | null;
			totals: {
				all: number;
				active: number;
				suspended: number;
				pending_closure: number;
				closed: number;
				no_package: number;
				packages: Array<{ package_id: string; name: string; count: number }>;
				matching: number;
				attention: Record<string, number>;
			};
		};

		return json({
			organizations: result.organizations,
			next_cursor: result.next_cursor ? encodeCursor(result.next_cursor) : null,
			totals: result.totals
		});
	} catch (error) {
		console.error('Could not list organizations.', error);
		return json({ error: 'Organizations could not be loaded.' }, { status: 500 });
	}
};
