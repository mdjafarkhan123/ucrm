import { defineConfig } from '@playwright/test';

try {
	process.loadEnvFile('.env');
} catch {
	// .env is optional locally and absent in some environments; tests that need it self-skip.
}

export default defineConfig({
	webServer: { command: 'npm run build && npm run preview', port: 4173 },
	testMatch: '**/*.e2e.{ts,js}'
});
