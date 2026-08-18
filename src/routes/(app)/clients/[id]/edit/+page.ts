import { redirect } from '@sveltejs/kit';
import { resolve } from '$app/paths';
import type { PageLoad } from './$types';

// Editing happens on the client's own page now, block by block. This keeps an old bookmark or a link in
// someone's email working instead of dead-ending on a 404.
export const load: PageLoad = ({ params }) => {
	redirect(308, resolve('/(app)/clients/[id]', { id: params.id }));
};
