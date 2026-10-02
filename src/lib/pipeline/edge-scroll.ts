// How fast the board should slide sideways while a card is dragged near its left or right edge, the way
// Trello and Jira do it: a wide strip along each edge, slow where the strip begins and fastest at the edge
// itself, and still going when the pointer is carried past the edge. The drag library scrolls too, but
// only inside the last 30px, which is too thin a strip to find while holding a card.

/** How far in from each edge the board starts to slide, in pixels. */
export const EDGE_ZONE = 120;
const SLOWEST = 150;
const FASTEST = 900;
// A card picked up from a column that already sits inside a strip must not send the board sliding the
// moment it is lifted. That edge waits until the pointer has been carried this far towards it.
const ARM_DISTANCE = 24;

function ramp(distanceFromEdge: number) {
	const depth = Math.min(1, (EDGE_ZONE - Math.max(distanceFromEdge, 0)) / EDGE_ZONE);
	return SLOWEST + (FASTEST - SLOWEST) * depth;
}

/** One per drag. `speed` answers in pixels per second: negative slides left, positive right, 0 stays. */
export function createEdgeScroll() {
	let startX: number | null = null;
	let leftArmed = false;
	let rightArmed = false;

	return {
		speed(pointerX: number, boardLeft: number, boardRight: number): number {
			const fromLeft = pointerX - boardLeft;
			const fromRight = boardRight - pointerX;
			if (startX === null) startX = pointerX;
			if (fromLeft >= EDGE_ZONE || startX - pointerX >= ARM_DISTANCE) leftArmed = true;
			if (fromRight >= EDGE_ZONE || pointerX - startX >= ARM_DISTANCE) rightArmed = true;

			if (leftArmed && fromLeft < EDGE_ZONE) return -ramp(fromLeft);
			if (rightArmed && fromRight < EDGE_ZONE) return ramp(fromRight);
			return 0;
		}
	};
}
