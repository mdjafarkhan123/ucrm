import { redirect } from '@sveltejs/kit';

// Standalone synthetic design reference; it does not mount the application's authenticated shell.
export function GET() {
	redirect(307, '/demo/job-details/index.html');
}
