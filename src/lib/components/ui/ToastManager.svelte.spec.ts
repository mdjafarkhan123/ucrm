import { describe, expect, it } from 'vitest';
import { createToastManager } from './ToastManager.svelte';

describe('createToastManager', () => {
	it('keeps a loading toast open until the caller dismisses it', () => {
		let manager!: ReturnType<typeof createToastManager>;
		const cleanup = $effect.root(() => {
			manager = createToastManager();
		});

		const id = manager.loading('Saving change…');

		expect(manager.toasts).toEqual([
			expect.objectContaining({
				id,
				variant: 'info',
				title: 'Saving change…',
				loading: true,
				duration: 0
			})
		]);

		manager.dismiss(id);
		expect(manager.toasts).toEqual([]);
		cleanup();
	});
});
