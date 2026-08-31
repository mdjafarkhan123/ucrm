// Settings → Automation home: the recipe list client state (Part 6C-1). TanStack Query owns it; this module
// only shapes the request/response. The list is read-only here — authoring/lifecycle mutations arrive in
// 6C-2/6C-3 and invalidate this key.

export type RecipeStatus = 'active' | 'paused' | 'draft' | 'archived';
export type RecipeSource = 'preset' | 'custom';

export type RecipeSummary = {
	id: string;
	name: string;
	status: RecipeStatus;
	source: RecipeSource;
	trigger_key: string | null;
	active_enrollments: number;
	last_activity_at: string;
};

export type RecipeCounts = { active: number; paused: number; draft: number };

export type RecipeListPage = {
	recipes: RecipeSummary[];
	// Present only on the first page (no cursor); the client keeps it while paging.
	counts: RecipeCounts | null;
	next_cursor: string | null;
};

export type RecipeListFilters = {
	search: string;
	status: RecipeStatus | '';
	source: RecipeSource | '';
};

export const automationRecipesKey = (filters: RecipeListFilters) =>
	['settings', 'automation', 'recipes', filters] as const;

export async function fetchAutomationRecipes(
	filters: RecipeListFilters,
	pageParam?: string
): Promise<RecipeListPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	if (filters.status) params.set('status', filters.status);
	if (filters.source) params.set('source', filters.source);
	if (pageParam) params.set('cursor', pageParam);
	const qs = params.toString();
	const response = await fetch(`/api/settings/automation/recipes${qs ? `?${qs}` : ''}`);
	if (!response.ok) throw new Error('Automations could not be loaded.');
	return (await response.json()) as RecipeListPage;
}
