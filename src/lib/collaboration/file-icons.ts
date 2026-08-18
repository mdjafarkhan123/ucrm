import photoIcon from '@tabler/icons/outline/photo.svg?raw';
import filePdfIcon from '@tabler/icons/outline/file-type-pdf.svg?raw';
import fileDocIcon from '@tabler/icons/outline/file-type-doc.svg?raw';
import fileDocxIcon from '@tabler/icons/outline/file-type-docx.svg?raw';
import fileXlsIcon from '@tabler/icons/outline/file-type-xls.svg?raw';
import fileCsvIcon from '@tabler/icons/outline/file-type-csv.svg?raw';
import fileZipIcon from '@tabler/icons/outline/file-type-zip.svg?raw';
import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
import fileIcon from '@tabler/icons/outline/file.svg?raw';

// One place decides which icon a file gets, so a saved attachment and one still waiting to upload never
// show a different icon for the same file.
export function iconForMimeType(mimeType: string) {
	if (mimeType.startsWith('image/')) return photoIcon;
	if (mimeType === 'application/pdf') return filePdfIcon;
	if (mimeType === 'application/msword') return fileDocIcon;
	if (mimeType.includes('wordprocessingml')) return fileDocxIcon;
	if (mimeType === 'application/vnd.ms-excel' || mimeType.includes('spreadsheetml'))
		return fileXlsIcon;
	if (mimeType === 'text/csv') return fileCsvIcon;
	if (mimeType === 'application/zip') return fileZipIcon;
	if (mimeType === 'text/plain') return fileTextIcon;
	return fileIcon;
}
