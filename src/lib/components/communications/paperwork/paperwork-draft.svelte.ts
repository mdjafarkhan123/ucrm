import { uploadAttachmentFile } from '$lib/collaboration/api';
import { allowedTypeFor } from '$lib/files/allowlist';
import {
	finishPaperworkUpload,
	PAPERWORK_FILE_TYPES,
	PAPERWORK_MAX_FILE_BYTES,
	savePaperwork,
	startPaperworkUpload,
	type EndUserType,
	type PaperworkAddress,
	type PaperworkDetail,
	type PaperworkRequestError
} from '$lib/communications/number-paperwork';

// What the business is typing into one paperwork set, saved as they type (the New campaign way: a short pause,
// then a PATCH with the revision it started from). A save that comes back after more typing keeps the newer
// typing and saves again; a save refused because another tab changed the set stops saving until a reload.

const SAVE_DELAY_MS = 800;

export const EMPTY_ADDRESS: PaperworkAddress = {
	customer_name: '',
	street: '',
	street_secondary: '',
	city: '',
	region: '',
	postal_code: '',
	country_code: ''
};

export type LocalUpload = {
	name: string;
	size: number;
	/** 0 to 1 while the bytes go up; null once they are up and the server is told. */
	progress: number | null;
	/** Why the file was refused here or by the server, with nothing sent. */
	problem: string | null;
	controller: AbortController | null;
};

export class PaperworkDraft {
	detail = $state.raw<PaperworkDetail>(null as unknown as PaperworkDetail);
	revision = $state(0);
	endUserType = $state<EndUserType>('business');
	answers = $state<Record<string, string>>({});
	address = $state<PaperworkAddress | null>(null);
	documentChoices = $state<Record<string, string>>({});
	/** The typed facts about each document (its number, issue date…), by document kind. */
	documentFields = $state<Record<string, Record<string, string>>>({});

	/** Files on their way up from this browser, by document kind. */
	uploads = $state<Record<string, LocalUpload>>({});

	saving = $state(false);
	dirty = $state(false);
	error = $state('');
	/** Another tab or person changed the set; saving waits for a reload. */
	stale = $state(false);

	#timer: ReturnType<typeof setTimeout> | null = null;
	#edits = 0;
	#inFlight: Promise<boolean> | null = null;
	#onSaved: (detail: PaperworkDetail) => void;

	constructor(detail: PaperworkDetail, onSaved: (detail: PaperworkDetail) => void) {
		this.#onSaved = onSaved;
		this.load(detail);
	}

	/** Take the saved set as it is, dropping anything unsaved. */
	load(detail: PaperworkDetail) {
		this.detail = detail;
		this.revision = detail.revision;
		this.endUserType = detail.end_user_type;
		this.answers = { ...detail.answers };
		this.address = detail.address ? { ...detail.address } : null;
		this.documentChoices = { ...detail.document_choices };
		this.documentFields = Object.fromEntries(
			detail.documents.map((document) => [document.document_type, { ...document.fields }])
		);
		this.dirty = false;
		this.stale = false;
		this.error = '';
	}

	/** A newer copy of the set arrived (a file finished its checks): take it unless typing is waiting to save. */
	refresh(detail: PaperworkDetail) {
		if (!this.dirty && !this.saving && detail.revision >= this.revision) this.load(detail);
		else this.detail = { ...detail, revision: this.detail.revision };
	}

	/** Note a change and save it after a short pause. */
	changed() {
		this.#edits += 1;
		this.dirty = true;
		if (this.stale) return;
		if (this.#timer) clearTimeout(this.#timer);
		this.#timer = setTimeout(() => void this.save(), SAVE_DELAY_MS);
	}

	setAnswer(name: string, value: string) {
		this.answers = { ...this.answers, [name]: value };
		this.changed();
	}

	setDocumentField(type: string, name: string, value: string) {
		this.documentFields = {
			...this.documentFields,
			[type]: { ...this.documentFields[type], [name]: value }
		};
		this.changed();
	}

	chooseDocument(requirementName: string, type: string) {
		this.documentChoices = { ...this.documentChoices, [requirementName]: type };
		this.changed();
	}

	setAddress(address: PaperworkAddress | null) {
		this.address = address;
		this.changed();
	}

	setEndUserType(type: EndUserType) {
		if (type === this.endUserType) return;
		this.endUserType = type;
		this.changed();
	}

	/** Save now (Save draft, Continue, before adding a file). True once everything typed is saved. */
	async save(): Promise<boolean> {
		if (this.#timer) {
			clearTimeout(this.#timer);
			this.#timer = null;
		}
		if (this.#inFlight) await this.#inFlight;
		if (!this.dirty) return true;
		if (this.stale) return false;
		this.#inFlight = this.#send();
		try {
			return await this.#inFlight;
		} finally {
			this.#inFlight = null;
		}
	}

	async #send(): Promise<boolean> {
		const edits = this.#edits;
		this.saving = true;
		try {
			const saved = await savePaperwork(this.detail.id, {
				expected_revision: this.revision,
				end_user_type: this.endUserType,
				answers: this.answers,
				address: this.address ? { ...this.address, customer_name: this.#addressName() } : null,
				document_choices: this.documentChoices,
				documents: Object.entries(this.documentFields).map(([document_type, fields]) => ({
					document_type,
					fields
				}))
			});
			this.error = '';
			this.#onSaved(saved);
			if (this.#edits === edits) {
				this.load(saved);
				return true;
			}
			// More was typed while this save was on its way: keep it, and save it on top of this revision.
			this.detail = saved;
			this.revision = saved.revision;
			return this.#send();
		} catch (error) {
			const refused = error as PaperworkRequestError;
			if (refused.code === 'stale') this.stale = true;
			this.error = refused.message || 'Your changes could not be saved.';
			return false;
		} finally {
			this.saving = false;
		}
	}

	/**
	 * Send one document's file: checked here first, then the typing is saved (the server reads the chosen
	 * document kind), then the bytes go straight to storage and the server starts its own checks.
	 */
	async upload(type: string, file: File, uploaded: () => Promise<unknown>) {
		const refuse = (problem: string) => {
			this.uploads = {
				...this.uploads,
				[type]: { name: file.name, size: file.size, progress: null, problem, controller: null }
			};
		};
		if (!allowedTypeFor(file.name, PAPERWORK_FILE_TYPES)) {
			return refuse('This kind of file can’t be sent. Use a PDF, JPG or PNG under 5 MB.');
		}
		if (file.size > PAPERWORK_MAX_FILE_BYTES) {
			return refuse('This file is too big. The phone company takes files up to 5 MB.');
		}
		const controller = new AbortController();
		this.uploads = {
			...this.uploads,
			[type]: { name: file.name, size: file.size, progress: 0, problem: null, controller }
		};
		const progress = (fraction: number | null) => {
			const current = this.uploads[type];
			if (current?.controller === controller)
				this.uploads = { ...this.uploads, [type]: { ...current, progress: fraction } };
		};
		try {
			if (!(await this.save())) throw new Error(this.error || 'Your changes could not be saved.');
			const started = await startPaperworkUpload(this.detail.id, type, file);
			await uploadAttachmentFile(
				started.upload_url,
				file.slice(0, file.size, started.mime_type),
				progress,
				controller.signal
			);
			progress(null);
			await finishPaperworkUpload(this.detail.id, started.file_id);
			await uploaded();
			this.#forget(type, controller);
		} catch (error) {
			if (controller.signal.aborted) return this.#forget(type, controller);
			const refused = error as PaperworkRequestError;
			const fieldError = Object.values(refused.fieldErrors ?? {}).flat()[0];
			refuse(fieldError || refused.message || 'The file upload failed. Please try again.');
		}
	}

	/** Stop a file on its way up; nothing is added. */
	cancelUpload(type: string) {
		this.uploads[type]?.controller?.abort();
	}

	/** Put the file box back after a refused file. */
	clearUpload(type: string) {
		const rest = { ...this.uploads };
		delete rest[type];
		this.uploads = rest;
	}

	#forget(type: string, controller: AbortController) {
		if (this.uploads[type]?.controller === controller) this.clearUpload(type);
	}

	// The name the phone company files the address under: the business, or the person for "Just me".
	#addressName(): string {
		if (this.endUserType === 'business') return this.answers.business_name ?? '';
		return [this.answers.first_name, this.answers.last_name].filter(Boolean).join(' ');
	}

	/** Leaving the page: what is still waiting for its pause is saved at once. */
	dispose() {
		if (this.#timer) void this.save();
	}
}
