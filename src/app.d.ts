// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
// Identity comes from the verified access token, not from a call to the auth server, so it carries the
// token's claims rather than a full auth-server user record. Only `id` and `email` are ever read.
type SessionUser = { id: string; email: string | null };

declare global {
	namespace App {
		// interface Error {}
		interface Locals {
			supabase: import('@supabase/supabase-js').SupabaseClient;
			getUser: () => Promise<SessionUser | null>;
		}
		interface PageData {
			user?: SessionUser;
			organization?: { id: string; name: string; role: string } | null;
		}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
