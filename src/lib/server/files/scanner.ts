// The malware scanner the upload pipeline talks to.
//
// ClamAV is the established open-source engine for exactly this job, and `clamd` speaks a small, stable TCP
// protocol, so this is a direct client rather than a wrapper package: roughly sixty lines against a
// documented protocol, versus a dependency that shells out to a binary we do not have.
//
// INSTREAM, from the clamd manual: send `zINSTREAM\0`, then each chunk prefixed with its length as a
// 4-byte big-endian integer, then a zero-length chunk to close. clamd replies `stream: OK\0` for clean
// content or `stream: <signature> FOUND\0` for a detection. Streaming matters here -- a 100 MB upload is
// scanned as it is read out of storage, so the worker never holds a whole file in memory.
//
// https://docs.clamav.net/manual/Usage/Scanning.html#clamd

import net from 'node:net';
import { getServerEnv } from '$lib/server/env';

const CONNECT_TIMEOUT_MS = 10_000;
const SCAN_TIMEOUT_MS = 120_000;

export type ScanResult = { clean: true } | { clean: false; signature: string };

// Distinguishes "the scanner says this file is bad" from "the scanner could not be reached". The contract
// requires an unavailable scanner to pause publication rather than release unscanned content, so the worker
// has to be able to tell those apart, and only this second case is a retryable failure.
export class ScannerUnavailableError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'ScannerUnavailableError';
	}
}

export function scannerIsConfigured(): boolean {
	return Boolean(getServerEnv().FILES_SCANNER_HOST);
}

export type ScanSession = {
	write(chunk: Uint8Array): Promise<void>;
	finish(): Promise<ScanResult>;
	abort(): void;
};

function lengthPrefix(byteLength: number): Buffer {
	const prefix = Buffer.alloc(4);
	prefix.writeUInt32BE(byteLength, 0);
	return prefix;
}

export async function openScanSession(): Promise<ScanSession> {
	const env = getServerEnv();
	const host = env.FILES_SCANNER_HOST;
	if (!host) throw new ScannerUnavailableError('No malware scanner is configured.');
	const port = env.FILES_SCANNER_PORT ?? 3310;

	const socket = await new Promise<net.Socket>((resolve, reject) => {
		const pending = net.createConnection({ host, port });
		const failed = (error: Error) => {
			pending.destroy();
			reject(new ScannerUnavailableError(`Could not reach the malware scanner: ${error.message}`));
		};
		pending.setTimeout(CONNECT_TIMEOUT_MS, () => failed(new Error('the connection timed out')));
		pending.once('error', failed);
		pending.once('connect', () => {
			pending.setTimeout(0);
			pending.removeListener('error', failed);
			resolve(pending);
		});
	});

	// A socket-level error after connecting can arrive at any moment, including between writes. Holding it
	// here means every later await can report it instead of crashing the worker with an unhandled event.
	let socketError: Error | null = null;
	socket.on('error', (error: Error) => {
		socketError = error;
	});

	const replyChunks: Buffer[] = [];
	socket.on('data', (chunk: Buffer) => replyChunks.push(chunk));

	const closed = new Promise<void>((resolve) => socket.once('close', () => resolve()));

	await writeTo(socket, Buffer.from('zINSTREAM\0'));

	async function writeTo(target: net.Socket, payload: Buffer): Promise<void> {
		if (socketError)
			throw new ScannerUnavailableError(
				`The malware scanner dropped the connection: ${socketError.message}`
			);
		if (target.write(payload)) return;
		// The socket's buffer is full. Waiting for `drain` is what keeps a 100 MB file from being queued
		// into memory faster than clamd can consume it.
		await new Promise<void>((resolve, reject) => {
			const onDrain = () => {
				target.removeListener('error', onError);
				resolve();
			};
			const onError = (error: Error) =>
				reject(
					new ScannerUnavailableError(
						`The malware scanner dropped the connection: ${error.message}`
					)
				);
			target.once('drain', onDrain);
			target.once('error', onError);
		});
	}

	return {
		async write(chunk: Uint8Array) {
			if (chunk.byteLength === 0) return;
			const body = Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
			await writeTo(socket, Buffer.concat([lengthPrefix(body.byteLength), body]));
		},

		async finish() {
			// A zero-length chunk is how INSTREAM says "that is the whole file".
			await writeTo(socket, lengthPrefix(0));

			const verdict = await Promise.race([
				closed.then(() => Buffer.concat(replyChunks).toString('utf8').trim().replace(/\0+$/, '')),
				new Promise<never>((_, reject) =>
					setTimeout(
						() =>
							reject(new ScannerUnavailableError('The malware scanner did not answer in time.')),
						SCAN_TIMEOUT_MS
					)
				)
			]);
			socket.destroy();

			if (verdict.endsWith('OK')) return { clean: true } as const;

			const found = verdict.match(/^stream:\s*(.+?)\s+FOUND$/);
			if (found) return { clean: false, signature: found[1] } as const;

			// Anything else -- a size limit, a broken database, a truncated reply -- is the scanner failing,
			// not the file being clean. Publication waits.
			throw new ScannerUnavailableError(
				`The malware scanner returned an unexpected answer: ${verdict || 'nothing'}`
			);
		},

		abort() {
			socket.destroy();
		}
	};
}
