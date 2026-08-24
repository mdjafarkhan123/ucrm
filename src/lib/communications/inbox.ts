export type InboxEmail = {
	id: string;
	client_id: string;
	client_name: string;
	client_email: string;
	quote_id: string | null;
	subject: string;
	text_content: string;
	status: string;
	failure_message: string | null;
	created_at: string;
};

export type InboxEmailPage = {
	emails: InboxEmail[];
	next_cursor: string | null;
	view: 'team' | 'assigned';
};

export const inboxEmailKey = (search: string) =>
	['communications', 'inbox', 'email', search] as const;

export async function fetchInboxEmail(search = ''): Promise<InboxEmailPage> {
	const params = new URLSearchParams();
	if (search.trim()) params.set('search', search.trim());
	const response = await fetch(`/api/communications/email-history?${params.toString()}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'Email history could not be loaded.');
	return result as InboxEmailPage;
}
