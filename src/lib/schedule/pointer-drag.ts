// The mechanics of dragging with a pointer, in one place.
//
// Not the browser's own drag-and-drop: that cannot report where inside an element the pointer is, cannot be
// styled beyond a screenshot of the source, and does not exist on touch. Every calendar that lets you place
// work by hand -- Google Calendar, Outlook, Jobber -- uses raw pointer events instead, and so does this.
//
// What lives here is only the part that is identical everywhere: don't treat a click as a drag, follow the
// pointer even when it leaves the element, let Escape call the whole thing off, and always let go of the
// listeners afterwards. Where the pointer landed and what that means is the calendar's business.

export type PointerDragHandlers = {
	/** How far the pointer must travel before this is a drag and not a click. */
	threshold?: number;
	onStart?: () => void;
	onMove: (event: PointerEvent) => void;
	/** Only called once the threshold was passed, so a plain click never proposes a change. */
	onDrop: (event: PointerEvent) => void;
	/** Escape, a cancelled pointer, or a release that never became a drag. */
	onCancel: () => void;
};

const DEFAULT_THRESHOLD = 4;

export function startPointerDrag(event: PointerEvent, handlers: PointerDragHandlers): void {
	// Only the primary button drags. A right-click belongs to the browser's menu.
	if (event.button !== 0) return;

	const threshold = handlers.threshold ?? DEFAULT_THRESHOLD;
	const originX = event.clientX;
	const originY = event.clientY;
	let dragging = false;

	function finish() {
		window.removeEventListener('pointermove', move);
		window.removeEventListener('pointerup', up);
		window.removeEventListener('pointercancel', cancel);
		window.removeEventListener('keydown', key);
	}

	function move(next: PointerEvent) {
		if (!dragging) {
			const travelled = Math.hypot(next.clientX - originX, next.clientY - originY);
			if (travelled < threshold) return;
			dragging = true;
			handlers.onStart?.();
		}
		// Once this is a real drag the browser must stop trying to select text under the pointer.
		next.preventDefault();
		handlers.onMove(next);
	}

	function up(next: PointerEvent) {
		finish();
		if (dragging) handlers.onDrop(next);
		else handlers.onCancel();
	}

	function cancel() {
		finish();
		handlers.onCancel();
	}

	function key(next: KeyboardEvent) {
		if (next.key !== 'Escape') return;
		next.preventDefault();
		cancel();
	}

	window.addEventListener('pointermove', move);
	window.addEventListener('pointerup', up);
	window.addEventListener('pointercancel', cancel);
	window.addEventListener('keydown', key);
}

/** Where a pointer sits inside an element, in pixels from its top-left, including whatever it has scrolled. */
export function offsetWithin(element: HTMLElement, event: PointerEvent) {
	const box = element.getBoundingClientRect();
	return { x: event.clientX - box.left, y: event.clientY - box.top };
}
