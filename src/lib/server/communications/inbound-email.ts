// Provider-neutral inbound email helpers shared by the SES inbound pipeline.

export type CandidateRecipient = { address: string; local_part: string; domain_name: string };

// Shared by every provider's candidate-recipient resolution: a raw address string in, a normalized
// {address, local_part, domain_name} out, or null for something that is not a plausible address at all.
export function parseCandidateAddress(rawAddress: string): CandidateRecipient | null {
	const address = rawAddress.trim().toLowerCase();
	const at = address.lastIndexOf('@');
	if (at <= 0 || at === address.length - 1) return null;
	return { address, local_part: address.slice(0, at), domain_name: address.slice(at + 1) };
}

export type InboundMessageKind = 'reply' | 'auto_response' | 'delivery_notice';

// Auto-response and delivery-notice detection reads only the standard signals other mail systems already
// set, not a UCRM-invented heuristic. Shared by every provider so the heuristics live in exactly one
// place -- callers just supply their own lowercased headers map and sender address.
export function classifyMessageKind(
	headers: Record<string, string>,
	senderAddress: string
): InboundMessageKind {
	const sender = senderAddress.trim().toLowerCase();

	if (
		headers['auto-submitted']?.toLowerCase().startsWith('auto-') ||
		headers['x-autoreply'] !== undefined ||
		headers['x-autorespond'] !== undefined ||
		headers['precedence']?.toLowerCase() === 'auto_reply'
	) {
		return 'auto_response';
	}

	if (
		headers['content-type']?.toLowerCase().includes('multipart/report') ||
		sender.startsWith('mailer-daemon@') ||
		sender.startsWith('postmaster@')
	) {
		return 'delivery_notice';
	}

	return 'reply';
}

export const INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES = 20 * 1024 * 1024;

// Gmail's documented blocked-extension list is the reference standard for dangerous attachment types.
export const DANGEROUS_ATTACHMENT_EXTENSIONS = new Set([
	'ade',
	'adp',
	'apk',
	'appx',
	'appxbundle',
	'bat',
	'cab',
	'chm',
	'cmd',
	'com',
	'cpl',
	'dll',
	'dmg',
	'ex',
	'ex_',
	'exe',
	'hta',
	'ins',
	'isp',
	'iso',
	'jar',
	'js',
	'jse',
	'lib',
	'lnk',
	'mde',
	'msc',
	'msi',
	'msix',
	'msixbundle',
	'msp',
	'mst',
	'nsh',
	'pif',
	'ps1',
	'scr',
	'sct',
	'shb',
	'sys',
	'vb',
	'vbe',
	'vbs',
	'vxd',
	'wsc',
	'wsf',
	'wsh'
]);

export function attachmentExtension(fileName: string): string {
	const dot = fileName.lastIndexOf('.');
	return dot < 0 ? '' : fileName.slice(dot + 1).toLowerCase();
}
