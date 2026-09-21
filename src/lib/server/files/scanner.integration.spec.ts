// Talks to a real clamd. The client speaks a hand-written protocol, so mocks would only prove the mock
// agrees with itself -- this is the test that proves the wire format is right.
//
// Skipped unless a scanner is reachable, so an ordinary `npm run test:unit` is unaffected. To run it:
//
//   docker compose -f docker-compose.scanner.yml up -d
//   FILES_SCANNER_HOST=127.0.0.1 npx vitest run src/lib/server/files/scanner.integration.spec.ts
//
// Wait for the container's health check to pass first: clamd refuses connections until it has loaded its
// virus definitions, which takes a few minutes on a first start.

import { beforeAll, describe, expect, it, vi } from 'vitest';

const host = process.env.FILES_SCANNER_HOST;
const port = process.env.FILES_SCANNER_PORT ? Number(process.env.FILES_SCANNER_PORT) : 3310;

// The module reads its configuration through SvelteKit's private env, which has no value outside a
// request, so the accessor is replaced with the process environment this test was launched with.
vi.mock('$lib/server/env', () => ({
	getServerEnv: () => ({ FILES_SCANNER_HOST: host, FILES_SCANNER_PORT: port })
}));

// The EICAR test string: the industry-standard harmless file every scanner is required to detect. It is
// not malware and does nothing; it exists so exactly this test can be written.
const EICAR = Buffer.from(
	`X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*`,
	'ascii'
);

describe.skipIf(!host)('the ClamAV client, against a real daemon', () => {
	let openScanSession: typeof import('./scanner').openScanSession;

	beforeAll(async () => {
		({ openScanSession } = await import('./scanner'));
	});

	it('passes a clean file', async () => {
		const session = await openScanSession();
		await session.write(Buffer.from('a perfectly ordinary quote for a new roof', 'utf8'));
		expect(await session.finish()).toEqual({ clean: true });
	});

	it('detects the EICAR test file and names the signature', async () => {
		const session = await openScanSession();
		await session.write(EICAR);
		const result = await session.finish();
		expect(result.clean).toBe(false);
		if (!result.clean) expect(result.signature).toMatch(/Eicar/i);
	});

	// The daemon's default stream ceiling is 25 MB; docker/clamav/clamd.conf raises it past the File
	// Manager's 100 MB limit. If that file stops being mounted, this is the test that notices.
	it('accepts a file larger than the default 25 MB stream limit', async () => {
		const session = await openScanSession();
		const megabyte = Buffer.alloc(1024 * 1024, 0x41);
		for (let written = 0; written < 30; written += 1) await session.write(megabyte);
		expect(await session.finish()).toEqual({ clean: true });
	}, 60_000);
});
