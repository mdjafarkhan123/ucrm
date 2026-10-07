import type { OwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Photos of the people who work in the Jafar Panel. They are not Supabase users (ADR 0008): a teammate's
// photo sits on their `platform_team_members` row, and Jafar's own on the single owner settings row. One
// word names whose photo it is in keys and addresses: the teammate's member id, or `owner`.

export const OWNER_PHOTO_SUBJECT = 'owner';

/** Whose photo the signed-in person changes: always their own. */
export function photoSubject(session: Pick<OwnerSession, 'memberId'>) {
	return session.memberId ?? OWNER_PHOTO_SUBJECT;
}

// Both shapes are also built by `set_platform_*_photo`, and the tables refuse any other.
export function platformPhotoObjectKey(subject: string, photoId: string) {
	return `platform-photos/${subject}/${photoId}.webp`;
}

export function platformPhotoUrl(subject: string, photoId: string) {
	return `/api/jafar/photos/${subject}?v=${photoId}`;
}

/** Points the person's photo at a newly stored one, or clears it; returns the key it replaced. */
export async function setPlatformPhoto(
	session: Pick<OwnerSession, 'memberId'>,
	photoId: string | null
) {
	const client = getOwnerSupabaseClient();
	const newPhoto = photoId ? { new_photo_id: photoId } : {};
	const { data, error } = session.memberId
		? await client.rpc('set_platform_team_member_photo', {
				target_member_id: session.memberId,
				...newPhoto
			})
		: await client.rpc('set_platform_owner_photo', newPhoto);
	if (error) throw error;
	return data;
}

/** Where a person's photo lives, or null when they have none (or no such teammate exists). */
export async function platformPhotoObjectKeyFor(subject: string): Promise<string | null> {
	const client = getOwnerSupabaseClient();
	if (subject === OWNER_PHOTO_SUBJECT) {
		const { data, error } = await client
			.from('platform_owner_settings')
			.select('owner_avatar_object_key')
			.eq('id', true)
			.maybeSingle();
		if (error) throw error;
		return data?.owner_avatar_object_key ?? null;
	}
	const { data, error } = await client
		.from('platform_team_members')
		.select('avatar_object_key')
		.eq('id', subject)
		.maybeSingle();
	if (error) throw error;
	return data?.avatar_object_key ?? null;
}

/** The signed-in person's own photo address, for the top bar. */
export async function ownPlatformPhotoUrl(session: Pick<OwnerSession, 'memberId'>) {
	const client = getOwnerSupabaseClient();
	if (!session.memberId) {
		const { data, error } = await client
			.from('platform_owner_settings')
			.select('owner_avatar_url')
			.eq('id', true)
			.maybeSingle();
		if (error) throw error;
		return data?.owner_avatar_url ?? null;
	}
	const { data, error } = await client
		.from('platform_team_members')
		.select('avatar_url')
		.eq('id', session.memberId)
		.maybeSingle();
	if (error) throw error;
	return data?.avatar_url ?? null;
}

/**
 * A contractor staff member's photo as the Jafar Panel shows it. Their own address checks for a Supabase
 * session sharing their organization, which nobody in the panel has, so the panel asks its own route
 * instead. The `?v=` carries over so the browser keeps the bytes until the photo changes.
 */
export function contractorPhotoUrlInPanel(
	organizationId: string,
	userId: string,
	profileAvatarUrl: string | null
) {
	const version = profileAvatarUrl?.split('?v=')[1];
	if (!version) return null;
	return `/api/jafar/organizations/${organizationId}/team/${userId}/photo?v=${version}`;
}
