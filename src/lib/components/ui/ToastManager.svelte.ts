import { getContext, setContext } from 'svelte';

export type ToastVariant = 'success' | 'error' | 'warning' | 'info';

export type ToastItem = {
	id: number;
	variant: ToastVariant;
	title: string;
	message?: string;
	duration: number;
	loading?: boolean;
};

export type ToastManager = {
	toasts: ToastItem[];
	show: (toast: Omit<ToastItem, 'id' | 'duration'> & { duration?: number }) => number;
	dismiss: (id: number) => void;
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

	function dismiss(id: number) {
		toasts = toasts.filter((toast) => toast.id !== id);
	}

	function show({
		duration = DEFAULT_DURATION,
		...toast
	}: Omit<ToastItem, 'id' | 'duration'> & { duration?: number }) {
		const id = ++nextId;
		toasts = [...toasts, { ...toast, id, duration }];

		if (duration > 0) {
			setTimeout(() => dismiss(id), duration);
		}

		return id;
	}

	return {
		get toasts() {
			return toasts;
		},
		show,
		dismiss,
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
