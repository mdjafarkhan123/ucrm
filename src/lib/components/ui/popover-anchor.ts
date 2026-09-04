// What a popover is allowed to point at.
//
// Usually that is a real element. Sometimes there is nothing to point at yet: a card dragged in from the
// backlog has no place on the grid until the move is saved, so the only honest anchor is the spot the pointer
// let go of it. Floating UI calls that a virtual element and asks only for a rectangle, which is exactly what
// `anchorAtPoint` hands back. Bits UI passes any `getBoundingClientRect` straight through to Floating UI, so
// the two kinds of anchor are interchangeable everywhere a popover is opened.

export type PopoverAnchor = HTMLElement | { getBoundingClientRect: () => DOMRect };

/** A zero-size anchor sitting at one point in the viewport, for a popover with no element to attach to. */
export function anchorAtPoint(x: number, y: number): PopoverAnchor {
	return {
		getBoundingClientRect: () => new DOMRect(x, y, 0, 0)
	};
}
