import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationDirectoryQuerySchema } from '$lib/server/validation/organization-directory.schema';

type DirectoryCursor = { created_at: string; id: string };

function encodeCursor(cursor: DirectoryCursor): string {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

function decodeCursor(value: string): DirectoryCursor | null {
	try {
		const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
		if (
			parsed &&
			typeof parsed.created_at === 'string' &&
			typeof parsed.id === 'string'
		) {
			return parsed;
		}
		return null;
	} catch {
		return null;
	}
}

export const GET: RequestHandler = async (event) => {
	if (!await getOwnerSession(event)) return ownerUnauthorized();

	const parsed = organizationDirectoryQuerySchema.safeParse({
		search: event.url.searchParams.get('search') ?? undefined,
		attention_reason: event.url.searchParams.get('attention_reason') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined
	});
	if (!parsed.success)
		return json({ error: 'The organization directory filter is invalid.' }, { status: 422 });

	let cursor: DirectoryCursor | null = null;
	if (parsed.data.cursor) {
		cursor = decodeCursor(parsed.data.cursor);
		if (!cursor) return json({ error: 'The page cursor is invalid.' }, { status: 422 });
	}

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_organization_directory', {
			search_term: parsed.data.search ?? undefined,
			attention_reason: parsed.data.attention_reason ?? undefined,
			cursor_created_at: cursor?.created_at ?? undefined,
			cursor_id: cursor?.id ?? undefined,
			page_size: parsed.data.limit ?? 50
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
			}>;
			next_cursor: DirectoryCursor | null;
			totals: {
				all: number;
				active: number;
				suspended: number;
				pending_setup: number;
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
