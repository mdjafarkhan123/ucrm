// The signed-in person's own profile photo. The server answers with the new address for every avatar.

type PhotoResult = { avatar_url: string | null };

async function readResult(response: Response, fallback: string): Promise<PhotoResult> {
	const result: {
		avatar_url?: string | null;
		error?: string;
		field_errors?: Record<string, string>;
	} = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.field_errors?.photo ?? result.error ?? fallback);
	return { avatar_url: result.avatar_url ?? null };
}

export async function uploadProfilePhoto(photo: Blob): Promise<PhotoResult> {
	const body = new FormData();
	body.append('photo', photo, 'profile-photo.jpg');
	const response = await fetch('/api/profile/photo', { method: 'POST', body });
	return readResult(response, 'Your photo could not be saved. Please try again.');
}

export async function removeProfilePhoto(): Promise<PhotoResult> {
	const response = await fetch('/api/profile/photo', { method: 'DELETE' });
	return readResult(response, 'Your photo could not be removed. Please try again.');
}
