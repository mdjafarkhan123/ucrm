// Client-safe mirror of the same constants in `$lib/server/communications/inbound-email.ts` (that file is
// server-only and can't be imported from browser code). A file we would refuse to receive is one we refuse
// to send, so both directions share these limits -- keep both lists in sync.
export const OUTBOUND_ATTACHMENT_TOTAL_SIZE_BYTES = 20 * 1024 * 1024;
export const MAX_OUTBOUND_ATTACHMENTS = 10;

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

function attachmentExtension(fileName: string): string {
	const dot = fileName.lastIndexOf('.');
	return dot < 0 ? '' : fileName.slice(dot + 1).toLowerCase();
}

export function isDangerousAttachmentName(fileName: string): boolean {
	return DANGEROUS_ATTACHMENT_EXTENSIONS.has(attachmentExtension(fileName));
}
