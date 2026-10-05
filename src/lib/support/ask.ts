import { createContext } from 'svelte';

/** A setup section a new support chat is about (D6). */
export type SupportAskContext = { section: string; title: string };

/**
 * Ask Uplift: opens the Chat with Uplift messenger on a new message with a setup section attached, or about setup
 * in general when given null. The app layout provides it, because that is where the messenger lives; a page asks
 * through it.
 */
export const [getSupportAsk, setSupportAsk] =
	createContext<(context: SupportAskContext | null) => void>();
