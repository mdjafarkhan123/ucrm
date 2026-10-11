// Separate explicit imports: never import an eager barrel containing both presentations.
export type ProofDesign = 'classic' | 'botanical';
export async function loadShell(design: ProofDesign) {
	return design === 'classic'
		? (await import('./ClassicShell.svelte')).default
		: (await import('./BotanicalShell.svelte')).default;
}
export async function loadSurface(design: ProofDesign) {
	return design === 'classic'
		? (await import('./ClassicSurface.svelte')).default
		: (await import('./BotanicalSurface.svelte')).default;
}
