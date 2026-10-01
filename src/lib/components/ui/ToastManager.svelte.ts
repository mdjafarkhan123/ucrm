import { getContext, setContext } from 'svelte';

export type ToastVariant = 'success' | 'error' | 'warning' | 'info';

export type ToastItem = {
	id: number;
	variant: ToastVariant;
	title: string;
	message?: string;
	duration: number;
	loading?: boolean;
	// One thing the person can do about what the toast says: Undo, or open the record it is about.
	// Choosing it closes the toast.
	action?: { label: string; onSelect: () => void };
};

export type ToastManager = {
	toasts: ToastItem[];
	show: (toast: Omit<ToastItem, 'id' | 'duration'> & { duration?: number }) => number;
	dismiss: (id: number) => void;
	// A toast being read or reached for does not close under the pointer or the keyboard: its countdown
	// stops while it is hovered or focused, and starts again from the top afterwards.
	pause: (id: number) => void;
	resume: (id: number) => void;
	success: (title: string, message?: string) => number;
	error: (title: string, message?: string) => number;
	warning: (title: string, message?: string) => number;
	info: (title: string, message?: string) => number;
	loading: (title: string, message?: string) => number;
};

const TOAST_CONTEXT = Symbol('toast-manager');
const DEFAULT_DURATION = 4000;

export function createToastManager(): ToastManager {
	let toasts = $state<ToastItem[]>([]);
	let nextId = 0;
	const timers = new Map<number, ReturnType<typeof setTimeout>>();

	function pause(id: number) {
		clearTimeout(timers.get(id));
		timers.delete(id);
	}

	function dismiss(id: number) {
		pause(id);
		toasts = toasts.filter((toast) => toast.id !== id);
	}

	function resume(id: number) {
		const toast = toasts.find((candidate) => candidate.id === id);
		if (!toast || toast.duration <= 0 || timers.has(id)) return;
		timers.set(
			id,
			setTimeout(() => dismiss(id), toast.duration)
		);
	}

	function show({
		duration = DEFAULT_DURATION,
		...toast
	}: Omit<ToastItem, 'id' | 'duration'> & { duration?: number }) {
		const id = ++nextId;
		toasts = [...toasts, { ...toast, id, duration }];

		resume(id);

		return id;
	}

	return {
		get toasts() {
			return toasts;
		},
		show,
		dismiss,
		pause,
		resume,
		success: (title, message) => show({ variant: 'success', title, message }),
		error: (title, message) => show({ variant: 'error', title, message }),
		warning: (title, message) => show({ variant: 'warning', title, message }),
		info: (title, message) => show({ variant: 'info', title, message }),
		loading: (title, message) =>
			show({ variant: 'info', title, message, loading: true, duration: 0 })
	};
}

export function provideToastManager(manager: ToastManager) {
	setContext(TOAST_CONTEXT, manager);
}

export function getToastManager() {
	return getContext<ToastManager>(TOAST_CONTEXT);
}
