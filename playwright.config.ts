import { defineConfig } from '@playwright/test';
import { loadEnv } from 'vite';

// Read .env with Vite's parser, the one the app uses: Node's `process.loadEnvFile` keeps `\$` escapes
// literally, and the preview server would inherit the broken owner password hash. Values already set in
// the shell win, as with `process.loadEnvFile`. An absent .env leaves tests that need it to self-skip.
for (const [key, value] of Object.entries(loadEnv('production', process.cwd(), ''))) {
	process.env[key] ??= value;
}

export default defineConfig({
	webServer: { command: 'npm run build && npm run preview', port: 4173 },
	testMatch: '**/*.e2e.{ts,js}'
});
