import { describe, expect, it, vi } from 'vitest';
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

	it('holds a toast open while it is paused, then counts down again from the top', () => {
		vi.useFakeTimers();
		let manager!: ReturnType<typeof createToastManager>;
		const cleanup = $effect.root(() => {
			manager = createToastManager();
		});

		const undo = vi.fn();
		const id = manager.show({
			variant: 'success',
			title: 'Moved to Assessment unscheduled.',
			duration: 8000,
			action: { label: 'Undo', onSelect: undo }
		});

		vi.advanceTimersByTime(7000);
		manager.pause(id);
		vi.advanceTimersByTime(60_000);
		expect(manager.toasts).toHaveLength(1);
		expect(manager.toasts[0].action?.label).toBe('Undo');

		manager.resume(id);
		vi.advanceTimersByTime(7999);
		expect(manager.toasts).toHaveLength(1);
		vi.advanceTimersByTime(1);
		expect(manager.toasts).toEqual([]);

		cleanup();
		vi.useRealTimers();
	});
});
