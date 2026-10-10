<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import type {
		ConfirmableExperienceDefinition,
		ExperienceAgreementSummary,
		ExperienceHistoryEntry
	} from '$lib/experience/types';

	// Multi-industry foundation B1 (plan "Organization experience profile"): Jafar confirms which Industry
	// experience a business runs on, its Business type and the services he reviewed, with a reason. The
	// Agreement in force is recorded with it. A Business type left blank stays "Not yet confirmed"; trade
	// text never fills it in.
	let {
		definitions,
		current,
		agreement,
		pending,
		error,
		onSubmit,
		onClose
	}: {
		definitions: ConfirmableExperienceDefinition[];
		/** The current decision, whose answers start the form; null for a first decision. */
		current: ExperienceHistoryEntry | null;
		agreement: ExperienceAgreementSummary | null;
		pending: boolean;
		error: string;
		onSubmit: (input: {
			experience_key: string;
			definition_version: number;
			business_type_key: string | null;
			service_shape: string;
			reason: string;
		}) => void;
		onClose: () => void;
	} = $props();

	const uid = $props.id();
	const definitionValue = (definition: { experience_key: string; version: number }) =>
		`${definition.experience_key}:${definition.version}`;

	// The dialog opens fresh each time, so the starting values are read once. A change of primary
	// experience is an assisted transition, so an existing profile offers only its own experience.
	// svelte-ignore state_referenced_locally
	const offered = current
		? definitions.filter((definition) => definition.experience_key === current.experience_key)
		: definitions;
	// svelte-ignore state_referenced_locally
	let selected = $state(
		offered.length === 1
			? definitionValue(offered[0])
			: current
				? definitionValue({
						experience_key: current.experience_key,
						version: current.definition_version
					})
				: ''
	);
	// svelte-ignore state_referenced_locally
	let businessType = $state(current?.business_type_key ?? '');
	// svelte-ignore state_referenced_locally
	let serviceShape = $state(current?.service_shape ?? '');
	let reason = $state('');
	let errors = $state<Record<string, string>>({});

	const definition = $derived(offered.find((item) => definitionValue(item) === selected) ?? null);
	const businessTypeOptions = $derived([
		{ value: '', label: 'Not yet confirmed' },
		...(definition?.business_types.map((type) => ({ value: type.key, label: type.label })) ?? [])
	]);

	function chooseDefinition(value: string) {
		selected = value;
		if (!definition?.business_types.some((type) => type.key === businessType)) businessType = '';
	}

	function submit(event: SubmitEvent) {
		event.preventDefault();
		const next: Record<string, string> = {};
		if (!definition) next.definition = 'Choose an Industry experience.';
		if (!serviceShape.trim()) next.service_shape = 'Describe the services you reviewed.';
		if (!reason.trim()) next.reason = 'Explain why this experience fits.';
		errors = next;
		if (!definition || Object.keys(next).length > 0) return;
		onSubmit({
			experience_key: definition.experience_key,
			definition_version: definition.version,
			business_type_key: businessType || null,
			service_shape: serviceShape.trim(),
			reason: reason.trim()
		});
	}
</script>

<Dialog
	open
	title={current ? 'Review experience profile' : 'Confirm experience'}
	initialFocusId={`${uid}-services`}
	{onClose}
>
	<form class="experience-dialog" onsubmit={submit} novalidate>
		<p class="experience-dialog__lead">
			This decides which Industry experience the business runs on. It is recorded with your name and
			kept in the history; an earlier decision is never changed.
		</p>
		<Select
			id={`${uid}-experience`}
			label="Industry experience"
			placeholder="Choose an experience"
			options={offered.map((item) => ({
				value: definitionValue(item),
				label: `${item.name} · definition v${item.version}`
			}))}
			value={selected}
			onchange={chooseDefinition}
			disabled={offered.length <= 1}
		/>
		{#if errors.definition}
			<p class="experience-dialog__error" role="alert">{errors.definition}</p>
		{/if}
		<Select
			id={`${uid}-business-type`}
			label="Business type"
			options={businessTypeOptions}
			bind:value={businessType}
		/>
		<Textarea
			id={`${uid}-services`}
			label="Services you reviewed"
			rows={3}
			maxlength={1000}
			required
			bind:value={serviceShape}
			invalid={Boolean(errors.service_shape) && !serviceShape.trim()}
			errorMessage={serviceShape.trim() ? '' : (errors.service_shape ?? '')}
		/>
		<Textarea
			id={`${uid}-reason`}
			label="Why this experience fits"
			rows={3}
			maxlength={1000}
			required
			bind:value={reason}
			invalid={Boolean(errors.reason) && !reason.trim()}
			errorMessage={reason.trim() ? '' : (errors.reason ?? '')}
		/>
		<p class="experience-dialog__agreement">
			Agreement recorded with this decision:
			<strong>{agreement ? agreement.package_name : 'No agreement in force'}</strong>
		</p>
		{#if error}
			<p class="experience-dialog__error" role="alert">{error}</p>
		{/if}
		<div class="experience-dialog__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending}>Record decision</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.experience-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__lead,
		&__agreement {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__agreement strong {
			color: var(--color-heading);
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}
	}
</style>
