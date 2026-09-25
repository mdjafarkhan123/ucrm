// A message written elsewhere in the CRM that opens in a Client's inbox conversation for staff to review and
// send -- today, "Send by email" / "Send by text" on a customer file share. It crosses the page change in
// memory rather than in the URL, because the draft can carry a live customer link that must not land in
// browser history, server logs or a copied address. A reload drops it, which is the safe failure: the
// conversation still opens, just without the prefilled text.

export type ComposerDraft = {
	clientId: string;
	channel: 'email' | 'sms';
	subject: string;
	body: string;
};

let pending: ComposerDraft | null = null;

export function handOffComposerDraft(draft: ComposerDraft) {
	pending = draft;
}

/** Hands the draft over once, and only to the conversation it was written for. */
export function takeComposerDraft(clientId: string): ComposerDraft | null {
	if (!pending || pending.clientId !== clientId) return null;
	const draft = pending;
	pending = null;
	return draft;
}
