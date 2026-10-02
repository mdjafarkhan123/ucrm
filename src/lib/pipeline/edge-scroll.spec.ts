import { describe, expect, it } from 'vitest';
import { createEdgeScroll, EDGE_ZONE } from './edge-scroll';

// A board that spans 200px to 1200px across the screen.
const LEFT = 200;
const RIGHT = 1200;

describe('createEdgeScroll', () => {
	it('stays still while the card is carried across the middle of the board', () => {
		const scroll = createEdgeScroll();
		expect(scroll.speed(700, LEFT, RIGHT)).toBe(0);
		expect(scroll.speed(RIGHT - EDGE_ZONE, LEFT, RIGHT)).toBe(0);
	});

	it('slides right inside the right strip, faster the nearer the edge', () => {
		const scroll = createEdgeScroll();
		scroll.speed(700, LEFT, RIGHT);
		const justInside = scroll.speed(RIGHT - 100, LEFT, RIGHT);
		const nearEdge = scroll.speed(RIGHT - 10, LEFT, RIGHT);
		expect(justInside).toBeGreaterThan(0);
		expect(nearEdge).toBeGreaterThan(justInside);
	});

	it('slides left inside the left strip', () => {
		const scroll = createEdgeScroll();
		scroll.speed(700, LEFT, RIGHT);
		expect(scroll.speed(LEFT + 40, LEFT, RIGHT)).toBeLessThan(0);
	});

	it('keeps sliding at full speed when the pointer is carried past the edge', () => {
		const scroll = createEdgeScroll();
		scroll.speed(700, LEFT, RIGHT);
		expect(scroll.speed(RIGHT + 300, LEFT, RIGHT)).toBe(scroll.speed(RIGHT, LEFT, RIGHT));
		expect(scroll.speed(LEFT - 300, LEFT, RIGHT)).toBe(scroll.speed(LEFT, LEFT, RIGHT));
	});

	it('does not slide the moment a card is lifted from a column already inside a strip', () => {
		const scroll = createEdgeScroll();
		expect(scroll.speed(LEFT + 60, LEFT, RIGHT)).toBe(0);
		// A small wobble while lifting is not a request to scroll.
		expect(scroll.speed(LEFT + 50, LEFT, RIGHT)).toBe(0);
	});

	it('starts sliding once that card is carried on towards the edge', () => {
		const scroll = createEdgeScroll();
		scroll.speed(LEFT + 60, LEFT, RIGHT);
		expect(scroll.speed(LEFT + 30, LEFT, RIGHT)).toBeLessThan(0);
	});

	it('slides for a card that left its strip and came back', () => {
		const scroll = createEdgeScroll();
		scroll.speed(LEFT + 60, LEFT, RIGHT);
		scroll.speed(LEFT + 300, LEFT, RIGHT);
		expect(scroll.speed(LEFT + 60, LEFT, RIGHT)).toBeLessThan(0);
	});
});
