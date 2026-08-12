// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		interface Locals {
			supabase: import('@supabase/supabase-js').SupabaseClient;
			getUser: () => Promise<import('@supabase/supabase-js').User | null>;
		}
		interface PageData {
			user?: import('@supabase/supabase-js').User;
			organization?: { id: string; name: string; role: string } | null;
		}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
