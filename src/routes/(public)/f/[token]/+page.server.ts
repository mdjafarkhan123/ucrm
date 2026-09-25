import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fileShareTokenHash, resolveFileShare } from '$lib/server/files/share-links';

/** One shared File as the customer's page draws it. No storage key ever reaches the browser. */
export type SharedFileForCustomer = {
	id: string;
	name: string;
	mime_type: string;
	kind: 'image' | 'video' | 'document';
	size_bytes: number;
	has_thumbnail: boolean;
};

// The customer's page for a file share (Part 7D). The token from the URL is hashed here and the hash goes to
// the one reader function the service role may call. A link that never existed is a plain 404, so the page
// cannot be used to learn whether a business or a share exists. A real link that has been turned off or has
// expired says so and gives the business's phone and email instead -- whoever holds it was sent it.
//
// Loading the page records nothing: mail scanners and link previews fetch URLs before any person sees them.
// The view is recorded by the browser once the files are on screen.
export const load: PageServerLoad = async ({ params, setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});

	const tokenHash = fileShareTokenHash(params.token);
	const resolved = tokenHash ? await resolveFileShare(tokenHash) : null;
	if (!resolved) error(404, 'This link is not available.');

	const business = {
		name: resolved.business.name,
		has_logo: resolved.business.logo_object_key !== null
	};

	if (resolved.state === 'inactive') {
		return {
			share: null,
			inactive: {
				business: {
					...business,
					phone: resolved.business.phone,
					email: resolved.business.email
				}
			}
		};
	}

	return {
		inactive: null,
		share: {
			business,
			expires_at: resolved.expires_at,
			files: resolved.files.map((file): SharedFileForCustomer => ({
				id: file.id,
				name: file.name,
				mime_type: file.mime_type,
				kind: file.kind,
				size_bytes: file.size_bytes,
				has_thumbnail: file.thumbnail_object_key !== null
			}))
		}
	};
};
