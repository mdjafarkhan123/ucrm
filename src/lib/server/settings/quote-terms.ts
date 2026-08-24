import sanitizeHtml from 'sanitize-html';

// The approved blueprint allows exactly paragraphs, headings, lists, bold, italic, and links in Quote
// terms -- no raw HTML, images, tables, scripts, or embeds. This is the one place that allow-list is
// enforced; everything downstream (the database check, the Quote document renderer) trusts this ran first.
const ALLOWED_TAGS = ['p', 'h2', 'h3', 'ul', 'ol', 'li', 'strong', 'b', 'em', 'i', 'a', 'br'];

export function sanitizeQuoteTerms(rawHtml: string): string {
	const sanitized = sanitizeHtml(rawHtml, {
		allowedTags: ALLOWED_TAGS,
		allowedAttributes: { a: ['href'] },
		// javascript:/data: links would turn a terms paragraph into a way to run code for whoever opens the
		// Quote document, so only these two schemes -- and a bare relative path -- ever survive.
		allowedSchemes: ['http', 'https'],
		allowedSchemesByTag: { a: ['http', 'https'] },
		transformTags: {
			a: sanitizeHtml.simpleTransform('a', { rel: 'noopener noreferrer', target: '_blank' })
		},
		disallowedTagsMode: 'discard'
	}).trim();

	// A contenteditable box leaves a lone <br> behind after "select all, delete" -- that is empty to the
	// person looking at it, but `<br>` is an allowed tag, so without this check it would sanitize to a
	// non-empty string and get copied into every new Quote draft as a meaningless default line.
	const hasVisibleContent = sanitized.replace(/<br\s*\/?>/gi, '').replace(/&nbsp;/gi, '').trim();
	return hasVisibleContent ? sanitized : '';
}
