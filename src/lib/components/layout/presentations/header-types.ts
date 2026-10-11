import type { Component, Snippet } from 'svelte';
export type HeaderFrameProps = {
	identity?: Snippet;
	menu: Snippet;
	search: Snippet;
	add: Snippet;
	appearance: Snippet;
	notifications?: Snippet;
	accountControl: Snippet;
};
export type HeaderFrame = Component<HeaderFrameProps>;
