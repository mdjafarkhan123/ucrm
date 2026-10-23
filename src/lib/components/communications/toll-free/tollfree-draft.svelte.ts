import {
	removeTollfreePicture,
	saveTollfreeCheck,
	TOLLFREE_PICTURE_LIMIT,
	TOLLFREE_PICTURE_MAX_BYTES,
	uploadTollfreePicture,
	type TollfreeBusiness,
	type TollfreeDetail,
	type TollfreePicture,
	type TollfreeRequestError
} from '$lib/communications/sms-tollfree';

// What the business is typing into its toll-free check, saved as they type (the paperwork draft's way: a short
// pause, then a PATCH with the revision it started from). Picture changes raise the revision on the server too,
// so they wait for the typing to be saved first. A save refused because another tab changed the check stops
// saving until a reload.

const SAVE_DELAY_MS = 800;

export type PictureUpload = {
	file: File;
	/** 0 to 1 while the bytes go up. */
	progress: number;
	/** Why it failed; the answers stay saved. */
	problem: string | null;
};

function blankBusiness(): TollfreeBusiness {
	return {
		legal_business_name: '',
		business_type: 'limited_liability_company',
		business_registration_id_type: undefined,
		business_registration_id: '',
		business_registration_country: undefined,
		website_url: '',
		business_address: {
			line1: '',
			line2: '',
			city: '',
			region: '',
			postal_code: '',
			country_code: 'US'
		},
		authorized_representative: {
			first_name: '',
			last_name: '',
			business_title: undefined,
			job_position: undefined,
			email: '',
			phone_number: ''
		},
		messaging: {
			description: '',
			consent_method: 'website_form',
			consent_description: '',
			sample_messages: ['', ''],
			privacy_policy_url: undefined,
			terms_url: undefined,
			estimated_monthly_messages: 'under_500'
		}
	};
}

/** The saved answers over a blank form, so every box has a value to bind to. */
function filled(saved: Partial<TollfreeBusiness> | undefined): TollfreeBusiness {
	const base = blankBusiness();
	const samples = saved?.messaging?.sample_messages ?? [];
	return {
		...base,
		...saved,
		business_address: { ...base.business_address, ...saved?.business_address },
		authorized_representative: {
			...base.authorized_representative,
			...saved?.authorized_representative
		},
		messaging: {
			...base.messaging,
			...saved?.messaging,
			// Twilio's carriers want two examples; the form always shows two boxes.
			sample_messages: [samples[0] ?? '', samples[1] ?? '', ...samples.slice(2)]
		}
	};
}

export class TollfreeDraft {
	senderId: string;
	revision = $state(0);
	business = $state<TollfreeBusiness>(blankBusiness());
	pictures = $state.raw<TollfreePicture[]>([]);
	upload = $state<PictureUpload | null>(null);
	removing = $state<string | null>(null);

	saving = $state(false);
	dirty = $state(false);
	error = $state('');
	/** Another tab or person changed the check; saving waits for a reload. */
	stale = $state(false);

	#timer: ReturnType<typeof setTimeout> | null = null;
	#edits = 0;
	#inFlight: Promise<boolean> | null = null;
	#onSaved: (detail: TollfreeDetail) => void;

	constructor(senderId: string, detail: TollfreeDetail, onSaved: (detail: TollfreeDetail) => void) {
		this.senderId = senderId;
		this.#onSaved = onSaved;
		this.load(detail);
	}

	/** Take the saved check as it is, dropping anything unsaved. */
	load(detail: TollfreeDetail) {
		this.business = filled(detail.check?.answers.business);
		this.revision = detail.check?.revision ?? 0;
		this.pictures = detail.pictures;
		this.dirty = false;
		this.stale = false;
		this.error = '';
	}

	/** Note a change and save it after a short pause. */
	changed() {
		this.#edits += 1;
		this.dirty = true;
		if (this.stale) return;
		if (this.#timer) clearTimeout(this.#timer);
		this.#timer = setTimeout(() => void this.save(), SAVE_DELAY_MS);
	}

	/** Save now (Save draft, Continue, Send, before a picture). True once everything typed is saved. */
	async save(): Promise<boolean> {
		if (this.#timer) {
			clearTimeout(this.#timer);
			this.#timer = null;
		}
		if (this.#inFlight) await this.#inFlight;
		if (!this.dirty) return !this.stale;
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
			const saved = await saveTollfreeCheck(
				this.senderId,
				this.revision,
				$state.snapshot(this.business)
			);
			this.error = '';
			this.revision = saved.check?.revision ?? this.revision;
			this.pictures = saved.pictures;
			this.#onSaved(saved);
			if (this.#edits === edits) {
				this.dirty = false;
				return true;
			}
			// More was typed while this save was on its way: save it on top of this revision.
			return this.#send();
		} catch (error) {
			this.#refused(error, 'Your changes could not be saved.');
			return false;
		} finally {
			this.saving = false;
		}
	}

	/** Add one proof picture: checked here, then the typing is saved, then the bytes go up with progress. */
	async addPicture(file: File) {
		if (this.upload && !this.upload.problem) return;
		const fail = (problem: string) => (this.upload = { file, progress: 0, problem });
		if (!['image/jpeg', 'image/png'].includes(file.type)) return fail('Add a JPG or PNG picture.');
		if (file.size > TOLLFREE_PICTURE_MAX_BYTES)
			return fail('This picture is too big. Add one up to 5 MB.');
		if (this.pictures.length >= TOLLFREE_PICTURE_LIMIT)
			return fail('Add no more than five pictures.');
		this.upload = { file, progress: 0, problem: null };
		try {
			if (!(await this.save())) throw new Error(this.error || 'Your changes could not be saved.');
			const saved = await uploadTollfreePicture(this.senderId, this.revision, file, (fraction) => {
				if (this.upload?.file === file) this.upload.progress = fraction;
			});
			this.revision = saved.revision;
			this.pictures = saved.pictures;
			this.upload = null;
		} catch (error) {
			const refused = error as TollfreeRequestError;
			if (refused.code === 'stale') this.stale = true;
			// A refused picture says why; a server or connection failure only needs the way forward.
			fail(
				refused.status >= 400 && refused.status < 500
					? refused.message
					: 'Your answers are saved. Try this picture again or choose another one.'
			);
		}
	}

	/** Try the failed picture again. */
	retryPicture() {
		const file = this.upload?.file;
		if (!file) return;
		this.upload = null;
		void this.addPicture(file);
	}

	async removePicture(id: string) {
		if (this.removing) return;
		this.removing = id;
		try {
			if (!(await this.save())) return;
			const saved = await removeTollfreePicture(this.senderId, id, this.revision);
			this.revision = saved.revision;
			this.pictures = saved.pictures;
		} catch (error) {
			this.#refused(error, 'That picture could not be removed.');
		} finally {
			this.removing = null;
		}
	}

	#refused(error: unknown, fallback: string) {
		const refused = error as TollfreeRequestError;
		if (refused.code === 'stale') this.stale = true;
		this.error = refused.message || fallback;
	}

	/** Leaving the page: what is still waiting for its pause is saved at once. */
	dispose() {
		if (this.#timer) void this.save();
	}
}
