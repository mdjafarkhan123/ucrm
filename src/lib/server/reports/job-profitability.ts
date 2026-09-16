import { z } from 'zod';

// job_number is unique per organization, so one integer is a complete page marker.
const cursorSchema = z.object({
	direction: z.enum(['asc', 'desc']),
	jobNumber: z.number().int().min(1)
});

export type JobProfitabilityCursor = z.infer<typeof cursorSchema>;

export function encodeJobProfitabilityCursor(cursor: JobProfitabilityCursor) {
	return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function readJobProfitabilityCursor(
	raw: string | null | undefined
): JobProfitabilityCursor | null {
	if (!raw) return null;
	try {
		const parsed = cursorSchema.safeParse(
			JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'))
		);
		return parsed.success ? parsed.data : null;
	} catch {
		return null;
	}
}
