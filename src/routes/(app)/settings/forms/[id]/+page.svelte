<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Tabs from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import FormPreview from '$lib/components/settings/forms/FormPreview.svelte';
	import FormContactEditor from '$lib/components/settings/forms/FormContactEditor.svelte';
	import FormSectionEditor from '$lib/components/settings/forms/FormSectionEditor.svelte';
	import BookingRulesEditor from '$lib/components/settings/forms/BookingRulesEditor.svelte';
	import BookingServicesPicker from '$lib/components/settings/forms/BookingServicesPicker.svelte';
	import BookingSlotsPreview from '$lib/components/settings/forms/BookingSlotsPreview.svelte';
	import {
		cloneContent,
		fetchFormBooking,
		fetchFormDetail,
		formBookingKey,
		formDetailKey,
		publishFormDraft,
		reviseForm,
		saveFormBooking,
		saveFormDraft,
		saveFormIdentity,
		setFormDefault,
		type FormApiError
	} from '$lib/forms/api';
	import {
		FORM_CONFIRMATION_MESSAGE_MAX,
		FORM_CONFIRMATION_TITLE_MAX,
		FORM_DESCRIPTION_MAX,
		FORM_MAX_OPTIONS,
		FORM_MAX_PHOTOS,
		FORM_MAX_QUESTIONS,
		FORM_MAX_SECTIONS,
		FORM_NAME_MAX,
		FORM_REDIRECT_URL_MAX,
		FORM_TITLE_MAX,
		isBookingOutcome,
		isChoiceQuestion,
		type BookableService,
		type FormContent,
		type FormQuestion,
		type FormQuestionType,
		type FormSection
	} from '$lib/forms/types';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import deviceFloppyIcon from '@tabler/icons/outline/device-floppy.svg?raw';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const id = $derived(page.params.id ?? '');

	const photoMaxOptions = Array.from({ length: FORM_MAX_PHOTOS }, (_, i) => ({
		value: String(i + 1),
		label: String(i + 1)
	}));

	const query = createQuery(() => ({
		queryKey: formDetailKey(id),
		queryFn: () => fetchFormDetail(id),
		enabled: id !== ''
	}));

	// Only assessment/job forms have booking rules at all (request forms are staff-reviewed and never book a
	// slot) — the query stays off, and the Booking tab stays hidden, for a request form.
	const outcome = $derived(query.data?.outcome ?? null);
	const isBooking = $derived(outcome !== null && isBookingOutcome(outcome));

	const bookingQuery = createQuery(() => ({
		queryKey: formBookingKey(id),
		queryFn: () => fetchFormBooking(id),
		enabled: id !== '' && isBooking
	}));

	// The builder edits a deep copy so the cache is never mutated in place. We seed it once per underlying
	// version: after a save the draft keeps its version id (only its revision changes), so the guard below
	// leaves the in-progress edits alone; a publish or revise changes the shape, so we force a re-seed.
	let seededVersionId = $state<string | null>(null);
	let formName = $state('');
	let isDefault = $state(false);
	let archivedAt = $state<string | null>(null);
	let formRevision = $state(0);
	let hasDraft = $state(false);
	let draftRevision = $state<number | null>(null);
	let title = $state('');
	let description = $state('');
	let content = $state<FormContent | null>(null);
	let baseline = $state('');

	// Identity (name + enabled) is saved on its own command, apart from the draft content.
	let identityName = $state('');
	let identityEnabled = $state(true);
	let identityBaseline = $state('');

	let activeTab = $state('build');
	let banner = $state('');
	let saving = $state(false);
	let publishing = $state(false);
	let revising = $state(false);
	let settingDefault = $state(false);
	let savingIdentity = $state(false);

	// Booking rules (assessment/job forms only). Not drafted/published like the content above — one save
	// takes effect immediately, matching `update_form_booking_settings`'s own "one screen, one save" shape.
	let bookingSeededRevision = $state<number | null>(null);
	let bookingRevision = $state<number | null>(null);
	let requiresBookingApproval = $state(true);
	let serviceAreaEnabled = $state(false);
	let minNoticeMinutes = $state(120);
	let slotIntervalMinutes = $state(30);
	let visitDurationMinutes = $state(60);
	let arrivalWindowMinutes = $state<number | null>(null);
	let bufferMinutes = $state(0);
	let serviceIds = $state<string[]>([]);
	let initialServices = $state<BookableService[]>([]);
	let bookingBaseline = $state('');
	let bookingBanner = $state('');
	let savingBooking = $state(false);

	function bookingSnapshot(): string {
		return JSON.stringify({
			requiresBookingApproval,
			serviceAreaEnabled,
			minNoticeMinutes,
			slotIntervalMinutes,
			visitDurationMinutes,
			arrivalWindowMinutes,
			bufferMinutes,
			serviceIds
		});
	}

	$effect(() => {
		const detail = bookingQuery.data;
		if (!detail) return;
		if (detail.rules.revision === bookingSeededRevision) return;

		untrack(() => {
			requiresBookingApproval = detail.rules.requires_booking_approval;
			serviceAreaEnabled = detail.rules.service_area_enabled;
			minNoticeMinutes = detail.rules.min_notice_minutes;
			slotIntervalMinutes = detail.rules.slot_interval_minutes;
			visitDurationMinutes = detail.rules.visit_duration_minutes;
			arrivalWindowMinutes = detail.rules.arrival_window_minutes;
			bufferMinutes = detail.rules.buffer_minutes;
			serviceIds = detail.services.map((s) => s.catalog_item_id);
			initialServices = detail.services;
			bookingRevision = detail.rules.revision;
			bookingSeededRevision = detail.rules.revision;
			bookingBaseline = bookingSnapshot();
			bookingBanner = '';
		});
	});

	const bookingDirty = $derived(bookingBaseline !== '' && bookingSnapshot() !== bookingBaseline);

	function snapshot(): string {
		return JSON.stringify({ title, description, content });
	}

	$effect(() => {
		const detail = query.data;
		if (!detail) return;
		const base = detail.draft ?? detail.published;
		const versionId = base?.version_id ?? null;
		if (versionId !== null && versionId === seededVersionId) return;
		if (!base) return;

		untrack(() => {
			formName = detail.name;
			isDefault = detail.is_default;
			archivedAt = detail.archived_at;
			formRevision = detail.revision;
			hasDraft = detail.draft !== null;
			draftRevision = detail.draft?.revision ?? null;
			title = base.title;
			description = base.description ?? '';
			content = cloneContent(base.content);
			baseline = snapshot();
			identityName = detail.name;
			identityEnabled = detail.is_enabled;
			identityBaseline = JSON.stringify({ name: detail.name, enabled: detail.is_enabled });
			seededVersionId = versionId;
			banner = '';
		});
	});

	const editable = $derived(hasDraft && archivedAt === null);
	const dirty = $derived(
		editable && content !== null && baseline !== '' && snapshot() !== baseline
	);
	const questionCount = $derived(
		content ? content.sections.reduce((n, s) => n + s.questions.length, 0) : 0
	);
	const canAddSection = $derived(!!content && content.sections.length < FORM_MAX_SECTIONS);
	const canAddQuestion = $derived(questionCount < FORM_MAX_QUESTIONS);
	const identityDirty = $derived(
		JSON.stringify({ name: identityName, enabled: identityEnabled }) !== identityBaseline
	);

	function errorText(cause: unknown): string {
		const err = cause as FormApiError;
		if (err?.reason === 'stale_revision')
			return 'Someone else changed this form since you opened it. Reloading the latest version.';
		return err instanceof Error ? err.message : 'That could not be saved.';
	}

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: ['settings', 'forms'] });
	}

	async function reloadFresh() {
		seededVersionId = null;
		await queryClient.invalidateQueries({ queryKey: formDetailKey(id) });
	}

	// Trim and drop empties the way the server's Zod does, so the saved content is clean and the preview and
	// the stored copy agree. Blank options are dropped; a blank redirect becomes null (never an empty string).
	function toPayloadContent(): FormContent {
		const c = content!;
		return {
			contact: c.contact,
			photos: c.photos,
			sections: c.sections.map((section) => ({
				id: section.id,
				title: section.title.trim(),
				questions: section.questions.map((q) => {
					const out: FormSection['questions'][number] = {
						id: q.id,
						type: q.type,
						label: q.label.trim(),
						required: q.required
					};
					if (q.help && q.help.trim()) out.help = q.help.trim();
					if (isChoiceQuestion(q.type))
						out.options = (q.options ?? []).map((o) => o.trim()).filter(Boolean);
					return out;
				})
			})),
			confirmation: {
				title: c.confirmation.title.trim(),
				message: c.confirmation.message.trim(),
				redirect_url: c.confirmation.redirect_url?.trim()
					? c.confirmation.redirect_url.trim()
					: null
			}
		};
	}

	// Mirror the essential Zod rules client-side for instant, friendly feedback. The API remains the source of
	// truth (CLAUDE.md rule 12) — this only spares the round-trip and points at the field in plain words.
	function validate(payload: FormContent): string | null {
		if (!title.trim()) return 'Add a title customers will see — it’s in the Settings tab.';
		if (!payload.confirmation.title) return 'Add a confirmation title in the Settings tab.';
		if (!payload.confirmation.message) return 'Add a confirmation message in the Settings tab.';
		if (
			payload.confirmation.redirect_url &&
			!/^https?:\/\//i.test(payload.confirmation.redirect_url)
		)
			return 'The redirect link must start with http:// or https://';
		if (!payload.contact.email.shown && !payload.contact.phone.shown)
			return 'Show at least an email or a phone field so customers can be contacted.';
		for (const section of payload.sections) {
			if (!section.title) return 'Every section needs a title.';
			for (const q of section.questions) {
				if (!q.label) return 'Every question needs a label.';
				if (isChoiceQuestion(q.type)) {
					const opts = q.options ?? [];
					if (opts.length === 0) return `“${q.label}” needs at least one option.`;
					if (new Set(opts.map((o) => o.toLowerCase())).size !== opts.length)
						return `“${q.label}” has two options that are the same.`;
				}
			}
		}
		return null;
	}

	async function save(): Promise<boolean> {
		if (draftRevision === null || !content) return false;
		const payload = toPayloadContent();
		const problem = validate(payload);
		if (problem) {
			banner = problem;
			return false;
		}
		saving = true;
		banner = '';
		try {
			const res = await saveFormDraft(id, {
				expected_revision: draftRevision,
				title: title.trim(),
				description: description.trim() || undefined,
				content: payload
			});
			draftRevision = res.revision;
			content = cloneContent(res.content);
			title = res.title;
			description = res.description ?? '';
			baseline = snapshot();
			await invalidate();
			return true;
		} catch (cause) {
			banner = errorText(cause);
			if ((cause as FormApiError)?.reason === 'stale_revision') await reloadFresh();
			return false;
		} finally {
			saving = false;
		}
	}

	async function saveDraft() {
		if (await save()) toast.success('Draft saved.');
	}

	async function publish() {
		if (draftRevision === null) return;
		publishing = true;
		try {
			if (dirty) {
				if (!(await save())) return;
			} else {
				const problem = validate(toPayloadContent());
				if (problem) {
					banner = problem;
					return;
				}
			}
			if (draftRevision === null) return;
			await publishFormDraft(id, draftRevision);
			await invalidate();
			await reloadFresh();
			toast.success('Form published — it’s now live for customers.');
		} catch (cause) {
			banner = errorText(cause);
			if ((cause as FormApiError)?.reason === 'stale_revision') await reloadFresh();
		} finally {
			publishing = false;
		}
	}

	async function revise() {
		revising = true;
		banner = '';
		try {
			await reviseForm(id);
			await invalidate();
			await reloadFresh();
			toast.success('You’re editing a new draft now. Publish when it’s ready.');
		} catch (cause) {
			banner = errorText(cause);
		} finally {
			revising = false;
		}
	}

	async function makeDefault() {
		settingDefault = true;
		try {
			const res = await setFormDefault(id, formRevision);
			formRevision = res.revision;
			isDefault = res.is_default;
			await invalidate();
			toast.success('This is now your default request form.');
		} catch (cause) {
			banner = errorText(cause);
			if ((cause as FormApiError)?.reason === 'stale_revision') await reloadFresh();
		} finally {
			settingDefault = false;
		}
	}

	async function saveIdentity() {
		savingIdentity = true;
		banner = '';
		if (!identityName.trim()) {
			banner = 'Give this form a name so you can find it later.';
			savingIdentity = false;
			return;
		}
		try {
			const res = await saveFormIdentity(id, {
				expected_revision: formRevision,
				name: identityName.trim(),
				is_enabled: identityEnabled
			});
			formRevision = res.revision;
			formName = res.name;
			identityName = res.name;
			identityEnabled = res.is_enabled;
			identityBaseline = JSON.stringify({ name: res.name, enabled: res.is_enabled });
			await invalidate();
			toast.success('Form details saved.');
		} catch (cause) {
			banner = errorText(cause);
			if ((cause as FormApiError)?.reason === 'stale_revision') await reloadFresh();
		} finally {
			savingIdentity = false;
		}
	}

	async function saveBooking() {
		if (bookingRevision === null) return;
		savingBooking = true;
		bookingBanner = '';
		try {
			const res = await saveFormBooking(id, {
				expected_revision: bookingRevision,
				requires_booking_approval: requiresBookingApproval,
				service_area_enabled: serviceAreaEnabled,
				min_notice_minutes: minNoticeMinutes,
				slot_interval_minutes: slotIntervalMinutes,
				visit_duration_minutes: visitDurationMinutes,
				arrival_window_minutes: arrivalWindowMinutes,
				buffer_minutes: bufferMinutes,
				service_ids: serviceIds
			});
			bookingRevision = res.revision;
			bookingSeededRevision = res.revision;
			bookingBaseline = bookingSnapshot();
			// This also covers the sample-slots preview (`formBookingKey(id)` is a prefix of its own query
			// key), which is exactly the "refresh after Save" behaviour approved for that card.
			await queryClient.invalidateQueries({ queryKey: formBookingKey(id) });
			toast.success('Booking rules saved.');
		} catch (cause) {
			bookingBanner = errorText(cause);
			if ((cause as FormApiError)?.reason === 'stale_revision') {
				bookingSeededRevision = null;
				await queryClient.invalidateQueries({ queryKey: formBookingKey(id) });
			}
		} finally {
			savingBooking = false;
		}
	}

	function addSection() {
		if (!content || !canAddSection) return;
		content.sections = [...content.sections, { id: crypto.randomUUID(), title: '', questions: [] }];
	}

	function moveSection(from: number, by: number) {
		if (!content) return;
		const target = from + by;
		if (target < 0 || target >= content.sections.length) return;
		const next = [...content.sections];
		[next[from], next[target]] = [next[target], next[from]];
		content.sections = next;
	}

	function removeSection(from: number) {
		if (!content) return;
		content.sections = content.sections.filter((_, i) => i !== from);
	}

	// Question and option mutations are owned here (not by the rail children) for the same reason section
	// move/remove are: a child reassigning an array on a plain, non-$bindable prop updates the underlying
	// $state but doesn't re-render that child's own template. Hoisting to the owner of `content` keeps one
	// consistent pattern for every array-shaped edit in the builder.
	function blankQuestion(type: FormQuestionType): FormQuestion {
		const question: FormQuestion = {
			id: crypto.randomUUID(),
			type,
			label: '',
			required: false,
			help: ''
		};
		if (isChoiceQuestion(type)) question.options = [''];
		return question;
	}

	function addQuestion(si: number, type: FormQuestionType) {
		const section = content?.sections[si];
		if (!section || !canAddQuestion) return;
		section.questions = [...section.questions, blankQuestion(type)];
	}

	function moveQuestion(si: number, from: number, by: number) {
		const section = content?.sections[si];
		if (!section) return;
		const target = from + by;
		if (target < 0 || target >= section.questions.length) return;
		const next = [...section.questions];
		[next[from], next[target]] = [next[target], next[from]];
		section.questions = next;
	}

	function removeQuestion(si: number, from: number) {
		const section = content?.sections[si];
		if (!section) return;
		section.questions = section.questions.filter((_, i) => i !== from);
	}

	function changeQuestionType(si: number, qi: number, type: FormQuestionType) {
		const question = content?.sections[si]?.questions[qi];
		if (!question) return;
		question.type = type;
		if (isChoiceQuestion(type)) {
			if (!question.options || question.options.length === 0) question.options = [''];
		} else {
			delete question.options;
		}
	}

	function addOption(si: number, qi: number) {
		const question = content?.sections[si]?.questions[qi];
		if (!question) return;
		if (!question.options) question.options = [];
		if (question.options.length >= FORM_MAX_OPTIONS) return;
		question.options = [...question.options, ''];
	}

	function removeOption(si: number, qi: number, i: number) {
		const question = content?.sections[si]?.questions[qi];
		if (!question?.options) return;
		question.options = question.options.filter((_, idx) => idx !== i);
		if (question.options.length === 0) question.options = [''];
	}

	function statusBadge(): {
		status: 'success' | 'warning' | 'informative' | 'inactive';
		label: string;
	} {
		if (archivedAt !== null) return { status: 'inactive', label: 'Archived' };
		const detail = query.data;
		const published = detail?.published;
		if (published && hasDraft)
			return { status: 'informative', label: 'Published · editing a draft' };
		if (published) return { status: 'success', label: 'Published' };
		return { status: 'warning', label: 'Draft — not live yet' };
	}
</script>

<svelte:head><title>{formName || 'Form builder'} · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[
			{ label: 'Settings', href: resolve('/(app)/settings') },
			{ label: 'Request Forms', href: resolve('/(app)/settings/forms') },
			{ label: formName || 'Form' }
		]}
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={4} />
	{:else if query.isError}
		<ErrorState description="This form could not be loaded." retry={() => query.refetch()} />
	{:else if content}
		{@const badge = statusBadge()}
		<div class="builder">
			<header class="builder__bar">
				<div class="builder__heading">
					<h1 class="builder__title">{formName}</h1>
					<div class="builder__meta">
						<StatusBadge status={badge.status}>{badge.label}</StatusBadge>
						{#if isDefault}<span class="builder__default">Default</span>{/if}
					</div>
				</div>
				<div class="builder__actions">
					{#if editable}
						<Button
							variant="secondary"
							onclick={() => void saveDraft()}
							loading={saving}
							disabled={!dirty || publishing}
						>
							<span class="builder__btn-icon" aria-hidden="true">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html deviceFloppyIcon}
							</span>
							Save draft
						</Button>
						<Button onclick={() => void publish()} loading={publishing} disabled={saving}>
							<span class="builder__btn-icon" aria-hidden="true">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html rocketIcon}
							</span>
							Publish
						</Button>
					{:else if archivedAt === null}
						<Button onclick={() => void revise()} loading={revising}>Edit form</Button>
					{/if}
				</div>
			</header>

			{#if banner}<p class="builder__banner" role="alert">{banner}</p>{/if}
			{#if !editable && archivedAt === null}
				<p class="builder__note">
					You’re looking at the published version. Choose <strong>Edit form</strong> to make changes in
					a new draft — the live form stays the same until you publish.
				</p>
			{/if}
			{#if archivedAt !== null}
				<p class="builder__note">
					This form is archived. Restore it from the Request Forms list to edit it.
				</p>
			{/if}

			<div class="builder__grid">
				<div class="builder__preview">
					<span class="builder__preview-label">Live preview</span>
					<FormPreview {title} {description} {content} />
				</div>

				<aside class="builder__rail">
					<Tabs
						tabs={[
							{ value: 'build', label: 'Build' },
							...(isBooking ? [{ value: 'booking', label: 'Booking' }] : []),
							{ value: 'settings', label: 'Settings' }
						]}
						bind:value={activeTab}
						label="Form builder sections"
					>
						<TabPanel value="build">
							<Card heading="Contact details">
								<p class="builder__hint">
									Every request form starts by collecting who’s asking. Name is always collected.
								</p>
								<FormContactEditor contact={content.contact} />
							</Card>

							{#each content.sections as section, si (section.id)}
								<FormSectionEditor
									{section}
									index={si}
									count={content.sections.length}
									{canAddQuestion}
									onMove={(by) => moveSection(si, by)}
									onRemove={() => removeSection(si)}
									onAddQuestion={(type) => addQuestion(si, type)}
									onMoveQuestion={(qi, by) => moveQuestion(si, qi, by)}
									onRemoveQuestion={(qi) => removeQuestion(si, qi)}
									onChangeQuestionType={(qi, type) => changeQuestionType(si, qi, type)}
									onAddOption={(qi) => addOption(si, qi)}
									onRemoveOption={(qi, i) => removeOption(si, qi, i)}
								/>
							{/each}

							<Button variant="secondary" onclick={addSection} disabled={!canAddSection}>
								<span class="builder__btn-icon" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html plusIcon}
								</span>
								Add section
							</Button>
							{#if !canAddSection}
								<p class="builder__hint">You’ve reached the {FORM_MAX_SECTIONS}-section limit.</p>
							{/if}

							<Card heading="Photos">
								<Toggle
									id="photos-enabled"
									label="Let customers attach photos"
									bind:checked={content.photos.enabled}
								/>
								{#if content.photos.enabled}
									<Select
										id="photos-max"
										label="Most photos allowed"
										options={photoMaxOptions}
										value={String(content.photos.max)}
										onchange={(v) => (content!.photos.max = Number(v))}
									/>
								{/if}
							</Card>
						</TabPanel>

						{#if isBooking}
							<TabPanel value="booking">
								{#if bookingQuery.isPending}
									<LoadingSkeleton variant="card" rows={3} />
								{:else if bookingQuery.isError}
									<ErrorState
										description="Booking rules could not be loaded."
										retry={() => bookingQuery.refetch()}
									/>
								{:else if bookingQuery.data}
									{#if bookingBanner}<p class="builder__banner" role="alert">
											{bookingBanner}
										</p>{/if}
									{#key bookingSeededRevision}
										<BookingRulesEditor
											bind:requiresBookingApproval
											bind:serviceAreaEnabled
											bind:minNoticeMinutes
											bind:slotIntervalMinutes
											bind:visitDurationMinutes
											bind:arrivalWindowMinutes
											bind:bufferMinutes
											serviceAreaReady={bookingQuery.data.organization.service_area_ready}
											disabled={archivedAt !== null}
										/>
										<BookingServicesPicker
											bind:selectedIds={serviceIds}
											{initialServices}
											disabled={archivedAt !== null}
										/>
									{/key}
									<BookingSlotsPreview
										formId={id}
										hoursSet={bookingQuery.data.organization.hours_set}
									/>
									<div class="builder__identity-actions">
										<Button
											onclick={() => void saveBooking()}
											loading={savingBooking}
											disabled={!bookingDirty || archivedAt !== null}
										>
											Save booking rules
										</Button>
									</div>
								{/if}
							</TabPanel>
						{/if}

						<TabPanel value="settings">
							<Card heading="What customers see">
								<Input
									id="form-title"
									label="Form title"
									bind:value={title}
									required
									maxlength={FORM_TITLE_MAX}
								/>
								<Textarea
									id="form-description"
									label="Description (optional)"
									bind:value={description}
									rows={3}
									maxlength={FORM_DESCRIPTION_MAX}
									showCount
								/>
							</Card>

							<Card heading="After they submit">
								<Input
									id="confirm-title"
									label="Confirmation title"
									bind:value={content.confirmation.title}
									required
									maxlength={FORM_CONFIRMATION_TITLE_MAX}
								/>
								<Textarea
									id="confirm-message"
									label="Confirmation message"
									bind:value={content.confirmation.message}
									rows={3}
									required
									maxlength={FORM_CONFIRMATION_MESSAGE_MAX}
								/>
								<Input
									id="confirm-redirect"
									label="Send them to a link afterwards (optional)"
									bind:value={content.confirmation.redirect_url}
									maxlength={FORM_REDIRECT_URL_MAX}
									placeholder="https://your-site.com/thanks"
								/>
							</Card>

							<Card heading="Form details">
								<Input
									id="identity-name"
									label="Form name (only your team sees this)"
									bind:value={identityName}
									required
									maxlength={FORM_NAME_MAX}
								/>
								<Checkbox
									id="identity-enabled"
									label="Available to receive requests"
									bind:checked={identityEnabled}
								/>
								<div class="builder__identity-actions">
									<Button
										variant="secondary"
										size="small"
										onclick={() => void saveIdentity()}
										loading={savingIdentity}
										disabled={!identityDirty}
									>
										Save details
									</Button>
								</div>
							</Card>

							<Card heading="Default form">
								{#if isDefault}
									<p class="builder__hint">This is the form customers get by default.</p>
								{:else}
									<p class="builder__hint">
										The default is the form used when no specific form is chosen. Only a published
										form can be the default.
									</p>
									<div class="builder__identity-actions">
										<Button
											variant="secondary"
											size="small"
											onclick={() => void makeDefault()}
											loading={settingDefault}
											disabled={query.data?.published === null}
										>
											Make this the default
										</Button>
									</div>
								{/if}
							</Card>
						</TabPanel>
					</Tabs>
				</aside>
			</div>
		</div>
	{/if}
</PageContainer>

<style lang="scss">
	.builder {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__bar {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);
			flex-wrap: wrap;
		}

		&__heading {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__meta {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__default {
			padding: 2px 8px;
			border-radius: var(--radius-large);
			background: var(--color-interactive--background);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
		}

		&__btn-icon {
			display: inline-grid;
			place-items: center;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__banner {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}

		&__note {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-informative--surface);
			color: var(--color-informative--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__grid {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(360px, 460px);
			gap: var(--space-large);
			align-items: start;
		}

		&__preview {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			position: sticky;
			top: var(--space-base);
		}

		&__preview-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.4px;
		}

		&__rail {
			min-width: 0;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__identity-actions {
			display: flex;
			justify-content: flex-end;
		}
	}

	@media (max-width: 1079px) {
		.builder__grid {
			grid-template-columns: 1fr;
		}
		.builder__preview {
			position: static;
			order: 2;
		}
		.builder__rail {
			order: 1;
		}
	}
</style>
