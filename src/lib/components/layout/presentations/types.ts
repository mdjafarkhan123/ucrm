import type { Component, Snippet } from 'svelte';
import type { HeaderFrame } from './header-types';
import type { NavGroup } from '../navigation';
export type ShellFrameProps = {
	children: Snippet;
	notice?: Snippet;
	header: Snippet<[HeaderFrame, Snippet?]>;
	groups: NavGroup[];
	brand: string;
	eyebrow: string;
	logoUrl: string | null;
	variant: 'contractor' | 'owner';
	mobileOpen?: boolean;
	sidebarCollapsed?: boolean;
};
export type ShellFrame = Component<ShellFrameProps>;
