const HTML_ESCAPE: Record<string, string> = {
	'&': '&amp;',
	'<': '&lt;',
	'>': '&gt;',
	'"': '&quot;',
	"'": '&#39;'
};

function escapeHtml(value: string) {
	return value.replace(/[&<>"']/g, (character) => HTML_ESCAPE[character] ?? character);
}

/**
 * Manual email starts as plain text. This server renderer prevents a browser-supplied HTML body from
 * smuggling markup, tracking pixels, or unsafe links into the provider payload. Rich text is deferred to
 * the separately approved template/composer work.
 */
export function renderManualEmailHtml(body: string) {
	return `<p>${escapeHtml(body).replace(/\r?\n/g, '<br>')}</p>`;
}
